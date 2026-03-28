#!/bin/bash
# =============================================================================
# GPU Hardware Profiler for RDMA Capability Analysis
# Collects all critical data needed to spoof/patch RTX 5090 as RTX 6000 Ada
# =============================================================================

set -e

OUTPUT_DIR="/workspace/gpu_profiler_$(hostname)_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "=============================================="
echo "GPU Hardware Profiler"
echo "Output: $OUTPUT_DIR"
echo "=============================================="
echo ""

# -------------------------------------------------------------------------
# 1. SYSTEM INFORMATION
# -------------------------------------------------------------------------
echo "[1/12] System Information..."
{
    echo "=== System Information ==="
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'="' -f2)"
    echo "Date: $(date)"
    echo ""
} | tee "$OUTPUT_DIR/01_system_info.txt"

# -------------------------------------------------------------------------
# 2. NVIDIA SMI FULL OUTPUT
# -------------------------------------------------------------------------
echo "[2/12] NVIDIA SMI Data..."
{
    echo "=== nvidia-smi Full Output ==="
    nvidia-smi -q
} | tee "$OUTPUT_DIR/02_nvidia_smi_full.txt"

# -------------------------------------------------------------------------
# 3. GPU DETAILS (Per-GPU Analysis)
# -------------------------------------------------------------------------
echo "[3/12] GPU Details..."
GPU_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)
echo "Found $GPU_COUNT GPUs"

for i in $(seq 0 $((GPU_COUNT - 1))); do
    echo "  Analyzing GPU $i..."
    {
        echo "=== GPU $i Details ==="
        echo "Name: $(nvidia-smi -i $i --query-gpu=name --format=csv,noheader)"
        echo "Memory Total: $(nvidia-smi -i $i --query-gpu=memory.total --format=csv,noheader)"
        echo "BAR1 Total: $(nvidia-smi -i $i --query-gpu=BAR1 --format=csv,noheader)"
        echo "BAR1 Free: $(nvidia-smi -i $i --query-gpu=bar1_free --format=csv,noheader)"
        echo "Driver Version: $(nvidia-smi -i $i --query-gpu=driver_version --format=csv,noheader)"
        echo "GPU UUID: $(nvidia-smi -i $i --query-gpu=uuid --format=csv,noheader)"
        echo "Compute Capability: $(nvidia-smi -i $i --query-gpu=compute_cap --format=csv,noheader)"
        echo "GSP Firmware: $(nvidia-smi -i $i --query-gpu=gsp_firmware_version --format=csv,noheader)"
        echo "VBIOS Version: $(nvidia-smi -i $i --query-gpu=vbios_version --format=csv,noheader)"
        echo "Serial: $(nvidia-smi -i $i --query-gpu=serial --format=csv,noheader)"
        echo "Part Number: $(nvidia-smi -i $i --query-gpu=part_number --format=csv,noheader)"
        echo ""
    } >> "$OUTPUT_DIR/03_gpu_details.txt"
done

# -------------------------------------------------------------------------
# 4. PCI DEVICE INFORMATION (CRITICAL for spoofing)
# -------------------------------------------------------------------------
echo "[4/12] PCI Device Info..."
{
    echo "=== PCI Device Information ==="
    echo ""
    echo "All NVIDIA devices:"
    lspci -nn | grep -i nvidia
    echo ""
    
    echo "Detailed info for each GPU:"
    for gpu_addr in $(lspci -nn | grep -i "NVIDIA Corporation.*VGA" | awk '{print $1}'); do
        echo "--- $gpu_addr ---"
        lspci -vvv -n -s $gpu_addr 2>/dev/null | grep -E "Device ID|Vendor ID|Class|BAR|Kernel driver" || true
        echo ""
    done
    
    echo "PCIe Topology:"
    lspci -tv 2>/dev/null | grep -A5 -B5 -i nvidia | head -50
} | tee "$OUTPUT_DIR/04_pci_info.txt"

# -------------------------------------------------------------------------
# 5. IOMMU GROUP ANALYSIS
# -------------------------------------------------------------------------
echo "[5/12] IOMMU Groups..."
{
    echo "=== IOMMU Group Analysis ==="
    echo ""
    
    if [ -d /sys/kernel/iommu_groups ]; then
        echo "IOMMU is enabled"
        echo ""
        
        for group_dir in /sys/kernel/iommu_groups/*; do
            group_id=$(basename "$group_dir")
            device_count=$(ls -1 "$group_dir"/devices/ 2>/dev/null | wc -l)
            
            if [ $device_count -gt 0 ]; then
                # Check if group contains NVIDIA or Mellanox
                has_nvidia=0
                has_mellanox=0
                
                for dev_link in "$group_dir"/devices/*; do
                    if [ -L "$dev_link" ]; then
                        dev_path=$(readlink "$dev_link" 2>/dev/null | xargs basename)
                        dev_info=$(lspci -n -s $dev_path 2>/dev/null || echo "")
                        
                        if echo "$dev_info" | grep -qi nvidia; then
                            has_nvidia=1
                        fi
                        if echo "$dev_info" | grep -qi -E "mellanox|connectx"; then
                            has_mellanox=1
                        fi
                    fi
                done
                
                if [ $has_nvidia -eq 1 ] || [ $has_mellanox -eq 1 ]; then
                    echo "Group $group_id (devices: $device_count):"
                    if [ $has_nvidia -eq 1 ]; then echo "  - Contains NVIDIA GPU(s)"; fi
                    if [ $has_mellanox -eq 1 ]; then echo "  - Contains Mellanox NIC(s)"; fi
                    
                    for dev_link in "$group_dir"/devices/*; do
                        if [ -L "$dev_link" ]; then
                            dev_path=$(readlink "$dev_link" 2>/dev/null | xargs basename)
                            dev_info=$(lspci -n -s $dev_path 2>/dev/null)
                            echo "    $dev_path: $dev_info"
                        fi
                    done
                    echo ""
                fi
            fi
        done
    else
        echo "IOMMU groups not found (IOMMU may be disabled)"
    fi
} | tee "$OUTPUT_DIR/05_iommu_groups.txt"

# -------------------------------------------------------------------------
# 6. KERNEL MODULES & PARAMETERS
# -------------------------------------------------------------------------
echo "[6/12] Kernel Modules..."
{
    echo "=== NVIDIA Kernel Modules ==="
    lsmod | grep -E "^nvidia|^mlx5|^ib_"
    echo ""
    
    echo "Module Info:"
    for mod in nvidia nvidia_uvm nvidia_peermem mlx5_core; do
        echo "--- $mod ---"
        if lsmod | grep -q "^$mod"; then
            modinfo $mod 2>/dev/null | grep -E "^vermagic|^depends|^parm" || echo "  (modinfo not available)"
        else
            echo "  (not loaded)"
        fi
        echo ""
    done
    
    echo "Module Parameters:"
    for mod in nvidia nvidia_uvm; do
        if [ -d "/sys/module/$mod/parameters" ]; then
            echo "--- $mod parameters ---"
            for param_file in /sys/module/$mod/parameters/*; do
                if [ -f "$param_file" ]; then
                    param_name=$(basename "$param_file")
                    param_value=$(cat "$param_file" 2>/dev/null || echo "unreadable")
                    echo "  $param_name: $param_value"
                fi
            done
            echo ""
        fi
    done
} | tee "$OUTPUT_DIR/06_kernel_modules.txt"

# -------------------------------------------------------------------------
# 7. BAR1 SIZE ANALYSIS (Critical for RDMA)
# -------------------------------------------------------------------------
echo "[7/12] BAR1 Analysis..."
{
    echo "=== BAR1 Size Analysis ==="
    echo ""
    echo "GPU Index,Name,BAR1_Total(MB),BAR1_Free(MB),BAR1_Used(MB)"
    
    for i in $(seq 0 $((GPU_COUNT - 1))); do
        name=$(nvidia-smi -i $i --query-gpu=name --format=csv,noheader | tr -d '"')
        bar1_total=$(nvidia-smi -i $i --query-gpu=BAR1 --format=csv,noheader | tr -d ' ')
        bar1_free=$(nvidia-smi -i $i --query-gpu=bar1_free --format=csv,noheader | tr -d ' ')
        
        # Convert to MB
        bar1_total_mb=$(echo "scale=2; $bar1_total / 1024 / 1024" | bc)
        bar1_free_mb=$(echo "scale=2; $bar1_free / 1024 / 1024" | bc)
        bar1_used_mb=$(echo "scale=2; ($bar1_total - $bar1_free) / 1024 / 1024" | bc)
        
        echo "$i,$name,$bar1_total_mb,$bar1_free_mb,$bar1_used_mb"
    done
    
    echo ""
    echo "Recommendation:"
    min_bar1=$(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | sort -n | head -1)
    min_bar1_mb=$(echo "scale=2; $min_bar1 / 1024 / 1024" | bc)
    
    if (( $(echo "$min_bar1_mb < 256" | bc -l) )); then
        echo "  WARNING: Minimum BAR1 free is ${min_bar1_mb}MB (< 256MB). RDMA may fail!"
        echo "  Consider increasing BAR1 size or reducing P2P allocations."
    elif (( $(echo "$min_bar1_mb < 512" | bc -l) )); then
        echo "  CAUTION: Minimum BAR1 free is ${min_bar1_mb}MB (< 512MB). RDMA might be limited."
    else
        echo "  OK: Minimum BAR1 free is ${min_bar1_mb}MB (>= 512MB). Should support RDMA."
    fi
} | tee "$OUTPUT_DIR/07_bar1_analysis.txt"

# -------------------------------------------------------------------------
# 8. VBIOS DUMP (For VBIOS spoofing strategy)
# -------------------------------------------------------------------------
echo "[8/12] VBIOS Information..."
{
    echo "=== VBIOS Information ==="
    echo ""
    
    for gpu_addr in $(lspci -nn | grep -i "NVIDIA Corporation.*VGA" | awk '{print $1}'); do
        echo "--- $gpu_addr ---"
        
        # Try to read VBIOS from sysfs
        if [ -f "/sys/class/drm/card${gpu_addr#*:}/device/rom" ]; then
            echo "VBIOS file found in sysfs"
            vbios_size=$(stat -c%s "/sys/class/drm/card${gpu_addr#*:}/device/rom" 2>/dev/null || echo "0")
            echo "  Size: $vbios_size bytes"
            
            # Extract product info from VBIOS (strings)
            echo "  Product strings in VBIOS:"
            strings "/sys/class/drm/card${gpu_addr#*:}/device/rom" 2>/dev/null | grep -i -E "rtx|geforce|quadro|nvidia" | head -5 || echo "    (none found)"
        else
            echo "VBIOS not accessible via sysfs"
        fi
        
        # Get VBIOS version from nvidia-smi
        vbios_ver=$(lspci -vv -s $gpu_addr 2>/dev/null | grep -i "VBIOS Version" | awk '{print $NF}' || echo "unknown")
        echo "  VBIOS Version (lspci): $vbios_ver"
        
        echo ""
    done
} | tee "$OUTPUT_DIR/08_vbios_info.txt"

# -------------------------------------------------------------------------
# 9. RDMA/INFINIBAND DEVICE INFO
# -------------------------------------------------------------------------
echo "[9/12] RDMA/InfiniBand Devices..."
{
    echo "=== RDMA Device Information ==="
    echo ""
    
    if command -v ibv_devinfo &> /dev/null; then
        echo "IB Devices:"
        ibv_devinfo 2>/dev/null | grep -E "device name|port state|Firmware Version" | head -20 || echo "  (no IB devices found)"
        echo ""
        
        echo "IB Devices List:"
        ibv_devices 2>/dev/null || echo "  (none)"
        echo ""
    else
        echo "ibv_devinfo not installed"
    fi
    
    echo "RDMA Core Devices:"
    ls /sys/class/infiniband/ 2>/dev/null || echo "  (none)"
    echo ""
    
    if [ -d /sys/kernel/debug/infiniband ]; then
        echo "Peer Memory Clients:"
        for dev in /sys/kernel/debug/infiniband/mlx5_*; do
            if [ -f "$dev/peer_memory_clients" ]; then
                echo "--- $(basename $dev) ---"
                cat "$dev/peer_memory_clients" 2>/dev/null || echo "  (none)"
            fi
        done
    fi
} | tee "$OUTPUT_DIR/09_rdma_devices.txt"

# -------------------------------------------------------------------------
# 10. EXPORTED SYMBOLS (Check if P2P symbols are available)
# -------------------------------------------------------------------------
echo "[10/12] Exported Symbols..."
{
    echo "=== NVIDIA P2P Exported Symbols ==="
    echo ""
    
    if [ -f "/sys/module/nvidia/sections/.export_symbols" ]; then
        echo "P2P-related symbols exported by nvidia.ko:"
        grep -i "nvidia_p2p" /sys/module/nvidia/sections/.export_symbols || echo "  (none found)"
        echo ""
        
        echo "Count: $(grep -ci "nvidia_p2p" /sys/module/nvidia/sections/.export_symbols 2>/dev/null || echo 0) symbols"
    else
        echo "/sys/module/nvidia/sections/.export_symbols not found"
    fi
    
    echo ""
    echo "Checking libnvidia-compiler.so:"
    if [ -f "/usr/lib/x86_64-linux-gnu/nvidia/libnvidia-compiler.so" ]; then
        nm -D /usr/lib/x86_64-linux-gnu/nvidia/libnvidia-compiler.so 2>/dev/null | grep " nvidia_p2p" | head -10 || echo "  (none)"
    else
        echo "  (file not found)"
    fi
} | tee "$OUTPUT_DIR/10_exported_symbols.txt"

# -------------------------------------------------------------------------
# 11. P2P CAPABILITY TEST
# -------------------------------------------------------------------------
echo "[11/12] P2P Capability Test..."
{
    echo "=== P2P Capability Matrix ==="
    echo ""
    
    nvidia-smi topo -m 2>/dev/null || echo "  (topology check failed)"
    echo ""
    
    echo "CUDA P2P Access Test:"
    if command -v python3 &> /dev/null && python3 -c "import cuda" 2>/dev/null; then
        python3 << 'PYTEST'
import cuda.cudart as cudart

device_count = cudart.cudaGetDeviceCount()
print(f"Found {device_count} CUDA devices")
print("")
print("P2P Access Matrix:")
print("       ", end="")
for j in range(device_count):
    print(f"GPU{j:2d}  ", end="")
print("")

for i in range(device_count):
    print(f"GPU{i:2d}: ", end="")
    cudart.cudaSetDevice(i)
    for j in range(device_count):
        if i == j:
            print("  --  ", end="")
        else:
            can_access = cudart.cudaDeviceCanAccessPeer(i, j)
            status = cudart.cudaGetDevicePeerCapabilityByP2PService(i, j, 0)
            if can_access == cuda.CUDA_SUCCESS:
                print(" YES  ", end="")
            else:
                print(" NO   ", end="")
    print("")
PYTEST
    else
        echo "  (Python CUDA module not available, skipping detailed P2P test)"
        
        # Fallback: use nvidia-smi
        echo ""
        echo "Using nvidia-smi for P2P info:"
        nvidia-smi --query-gpu=p2p_index --format=csv 2>/dev/null || echo "  (not available)"
    fi
} | tee "$OUTPUT_DIR/11_p2p_capability.txt"

# -------------------------------------------------------------------------
# 12. SUMMARY & RECOMMENDATIONS
# -------------------------------------------------------------------------
echo "[12/12] Generating Summary..."
{
    echo "=============================================="
    echo "GPU HARDWARE PROFILE SUMMARY"
    echo "=============================================="
    echo ""
    echo "System: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
    echo "GPUs: $GPU_COUNT"
    echo ""
    
    echo "GPU Inventory:"
    nvidia-smi --query-gpu=index,name,memory.total,BAR1,bar1_free --format=csv
    echo ""
    
    echo "PCI Device IDs (for spoofing reference):"
    lspci -nn | grep -i "NVIDIA.*VGA" | awk '{print $1 ": " $3}'
    echo ""
    
    echo "Mellanox NICs:"
    lspci -nn | grep -i -E "mellanox|connectx" || echo "  (none found)"
    echo ""
    
    echo "BAR1 Status:"
    min_bar1_mb=$(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | sort -n | head -1)
    min_bar1_mb=$(echo "scale=1; $min_bar1_mb / 1024 / 1024" | bc)
    echo "  Minimum free BAR1: ${min_bar1_mb} MB"
    
    if (( $(echo "$min_bar1_mb < 256" | bc -l) )); then
        echo "  Status: ⚠️  LOW (may need increase for RDMA)"
    else
        echo "  Status: ✅ OK"
    fi
    echo ""
    
    echo "P2P Symbols Exported:"
    if [ -f "/sys/module/nvidia/sections/.export_symbols" ]; then
        symbol_count=$(grep -ci "nvidia_p2p" /sys/module/nvidia/sections/.export_symbols 2>/dev/null || echo 0)
        echo "  Count: $symbol_count"
        if [ $symbol_count -ge 6 ]; then
            echo "  Status: ✅ All required symbols present"
        else
            echo "  Status: ⚠️  Missing symbols (need >= 6)"
        fi
    else
        echo "  Status: ❓ Cannot check"
    fi
    echo ""
    
    echo "RDMA Module Status:"
    if lsmod | grep -q "nvidia_peermem"; then
        echo "  nvidia-peermem: ✅ Loaded"
    else
        echo "  nvidia-peermem: ❌ Not loaded (may need manual load)"
    fi
    
    if ibv_devices &> /dev/null; then
        echo "  IB devices: ✅ Found ($(ibv_devices | wc -l))"
    else
        echo "  IB devices: ⚠️  None or ibverbs not installed"
    fi
    echo ""
    
    echo "=============================================="
    echo "RECOMMENDATIONS"
    echo "=============================================="
    echo ""
    
    # Check if this looks like a 5090 system
    if nvidia-smi --query-gpu=name --format=csv,noheader | grep -qi "5090"; then
        echo "🎯 TARGET: RTX 5090 detected - RDMA spoofing recommended"
        echo ""
        echo "Suggested approach:"
        echo "  1. Check if device ID can be spoofed to RTX 6000 Ada (0x2704)"
        echo "  2. Ensure BAR1 >= 512MB (current: ${min_bar1_mb}MB)"
        echo "  3. Load nvidia-peermem after driver patch"
        echo "  4. Test with RDMA registration"
        echo ""
        echo "Device ID reference:"
        echo "  RTX 5090:   $(lspci -nn | grep -i "5090" | grep -oE '[0-9a-f]{4}' | head -1)"
        echo "  RTX 6000:   0x2704 (target spoof ID)"
    elif nvidia-smi --query-gpu=name --format=csv,noheader | grep -qi "6000.*ada"; then
        echo "✅ REFERENCE: RTX 6000 Ada detected - should have native RDMA"
        echo ""
        echo "Use this system as golden reference for:"
        echo "  - BAR1 size requirements"
        echo "  - Exported symbols verification"
        echo "  - nvidia-peermem loading sequence"
        echo "  - RDMA performance baseline"
    else
        echo "ℹ️  GPU model: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
    fi
    
    echo ""
    echo "All detailed data saved to: $OUTPUT_DIR"
    echo "=============================================="
    
} | tee "$OUTPUT_DIR/12_summary.txt"

# -------------------------------------------------------------------------
# CREATE QUICK REFERENCE FILE
# -------------------------------------------------------------------------
echo ""
echo "Creating quick reference file..."

cat > "$OUTPUT_DIR/QUICK_REFERENCE.txt" << EOF
========================================
QUICK REFERENCE FOR RDMA SPOOFING
========================================

Hostname: $(hostname)
Date: $(date)

GPU COUNT: $GPU_COUNT

GPU MODELS & PCI ADDRESSES:
$(for i in $(seq 0 $((GPU_COUNT - 1))); do
    addr=$(nvidia-smi -i $i --query-gpu=pci.bus_id --format=csv,noheader | tr -d ' ')
    name=$(nvidia-smi -i $i --query-gpu=name --format=csv,noheader | tr -d '"')
    bar1=$(nvidia-smi -i $i --query-gpu=bar1_free --format=csv,noheader | tr -d ' ')
    bar1_mb=$(echo "scale=1; $bar1 / 1024 / 1024" | bc)
    echo "GPU $i: $name @ $addr (BAR1 free: ${bar1_mb}MB)"
done)

PCI DEVICE IDs (for lspci):
$(lspci -nn | grep -i "NVIDIA.*VGA" | awk '{print $1 ": " $3 " (" $4 ")"}')

TARGET SPOOF ID (RTX 6000 Ada):
Device ID: 0x2704
Part Number: 900-1G045-0000-020

NVIDIA PEERMEM STATUS:
$(if lsmod | grep -q "nvidia_peermem"; then echo "✅ Loaded"; else echo "❌ Not loaded"; fi)

IB DEVICES:
$(ibv_devices 2>/dev/null || echo "None found")

QUICK TEST COMMANDS:
1. Check P2P symbols: grep nvidia_p2p /sys/module/nvidia/sections/.export_symbols
2. Load peermem: sudo modprobe nvidia-peermem
3. Test RDMA: sudo ./test_rdma (if compiled)
4. Check BAR1: nvidia-smi --query-gpu=BAR1,bar1_free --format=csv

EOF

echo "Quick reference saved to: $OUTPUT_DIR/QUICK_REFERENCE.txt"

# -------------------------------------------------------------------------
# DONE
# -------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "✅ PROFILING COMPLETE"
echo "=========================================="
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "Total files: $(ls -1 $OUTPUT_DIR | wc -l)"
echo ""
echo "Next steps:"
echo "  1. Review $OUTPUT_DIR/12_summary.txt"
echo "  2. Check $OUTPUT_DIR/QUICK_REFERENCE.txt"
echo "  3. Compare with reference system (if RTX 6000 Ada)"
echo "  4. Proceed with spoofing/patching based on findings"
echo ""
