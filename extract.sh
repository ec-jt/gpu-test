#!/bin/bash
# =============================================================================
# Cross-System Comparison Script for RDMA Capability Analysis
# Run on both systems, then compare outputs
# =============================================================================

set -e

SYSTEM_NAME=$1
if [ -z "$SYSTEM_NAME" ]; then
    SYSTEM_NAME=$(hostname)
fi

OUTPUT_DIR="/workspace/gpu_compare_${SYSTEM_NAME}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "=== GPU Comparison Data Extractor ==="
echo "System: $SYSTEM_NAME"
echo "Output: $OUTPUT_DIR"
echo ""

# -------------------------------------------------------------------------
# EXTRACT KEY DATA POINTS FOR COMPARISON
# -------------------------------------------------------------------------

echo "[1/6] GPU Identification..."
{
    echo "=== GPU IDENTIFICATION ==="
    echo "Hostname: $SYSTEM_NAME"
    echo "Driver: $(nvidia-smi --version 2>/dev/null || echo 'unknown')"
    echo ""
    
    echo "GPU List (CSV format for easy comparison):"
    nvidia-smi --query-gpu=index,name,uuid,memory.total,BAR1,bar1_free,pci.bus_id,pci.device_id --format=csv,noheader
    echo ""
    
    echo "Unique GPU Models:"
    nvidia-smi --query-gpu=name --format=csv,noheader | sort | uniq -c
} | tee "$OUTPUT_DIR/01_gpu_id.txt"

echo "[2/6] PCI Device IDs..."
{
    echo "=== PCI DEVICE IDS ==="
    echo ""
    
    echo "All NVIDIA VGA devices:"
    lspci -nn | grep -i "NVIDIA.*VGA" | while read line; do
        addr=$(echo $line | awk '{print $1}')
        vendor=$(echo $line | awk '{print $3}')
        device=$(echo $line | awk '{print $4}' | tr -d '()')
        echo "  $addr: Vendor=0x$vendor, Device=0x$device"
    done
    echo ""
    
    echo "Device ID summary (for spoofing reference):"
    lspci -nn | grep -i "NVIDIA.*VGA" | awk '{print $3, $4}' | sort | uniq
} | tee "$OUTPUT_DIR/02_pci_ids.txt"

echo "[3/6] BAR1 Analysis..."
{
    echo "=== BAR1 SIZE ANALYSIS ==="
    echo ""
    
    echo "Per-GPU BAR1:"
    printf "%-3s %-25s %-12s %-12s %-12s\n" "GPU" "Name" "BAR1_Total" "BAR1_Free" "BAR1_Used"
    printf "%-3s %-25s %-12s %-12s %-12s\n" "---" "-------------------------" "------------" "------------" "------------"
    
    for i in $(seq 0 $(( $(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l) - 1 ))); do
        name=$(nvidia-smi -i $i --query-gpu=name --format=csv,noheader | cut -c1-25)
        bar1_total=$(nvidia-smi -i $i --query-gpu=BAR1 --format=csv,noheader | tr -d ' ')
        bar1_free=$(nvidia-smi -i $i --query-gpu=bar1_free --format=csv,noheader | tr -d ' ')
        
        total_mb=$(echo "scale=0; $bar1_total / 1024 / 1024" | bc)
        free_mb=$(echo "scale=0; $bar1_free / 1024 / 1024" | bc)
        used_mb=$(echo "scale=0; ($bar1_total - $bar1_free) / 1024 / 1024" | bc)
        
        printf "%-3d %-25s %-12s %-12s %-12s\n" $i "$name" "${total_mb}MB" "${free_mb}MB" "${used_mb}MB"
    done
    echo ""
    
    echo "Summary statistics:"
    echo "  Min BAR1 Free: $(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | sort -n | head -1 | xargs -I{} echo "scale=1; {} / 1024 / 1024" | bc)MB"
    echo "  Max BAR1 Free: $(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | sort -n | tail -1 | xargs -I{} echo "scale=1; {} / 1024 / 1024" | bc)MB"
    echo "  Avg BAR1 Free: $(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | awk '{sum+=$1; count++} END {print sum/count/1024/1024}')MB"
} | tee "$OUTPUT_DIR/03_bar1.txt"

echo "[4/6] Kernel Module Symbols..."
{
    echo "=== P2P SYMBOL EXPORTS ==="
    echo ""
    
    if [ -f "/sys/module/nvidia/sections/.export_symbols" ]; then
        echo "nvidia_p2p_* symbols exported:"
        grep "nvidia_p2p" /sys/module/nvidia/sections/.export_symbols | while read line; do
            symbol=$(echo $line | awk '{print $NF}')
            echo "  ✅ $symbol"
        done
        
        echo ""
        echo "Total nvidia_p2p symbols: $(grep -c "nvidia_p2p" /sys/module/nvidia/sections/.export_symbols)"
        
        # Check for required symbols
        echo ""
        echo "Required symbols check:"
        for sym in nvidia_p2p_get_pages nvidia_p2p_put_pages nvidia_p2p_dma_map_pages nvidia_p2p_dma_unmap_pages nvidia_p2p_free_page_table nvidia_p2p_free_dma_mapping; do
            if grep -q "$sym" /sys/module/nvidia/sections/.export_symbols; then
                echo "  ✅ $sym"
            else
                echo "  ❌ $sym (MISSING!)"
            fi
        done
    else
        echo "❌ Cannot check (export_symbols not available)"
    fi
} | tee "$OUTPUT_DIR/04_symbols.txt"

echo "[5/6] VBIOS Information..."
{
    echo "=== VBIOS DATA ==="
    echo ""
    
    echo "VBIOS versions from nvidia-smi:"
    nvidia-smi --query-gpu=index,name,vbios_version --format=csv
    echo ""
    
    echo "VBIOS from lspci:"
    lspci -vv | grep -A1 "NVIDIA.*VGA" | grep -i "VBIOS Version" || echo "  (not found)"
    echo ""
    
    echo "Product info strings from VBIOS ROM:"
    for i in $(seq 0 7); do
        if [ -f "/sys/class/drm/card${i}/device/rom" ]; then
            name=$(nvidia-smi -i $i --query-gpu=name --format=csv,noheader 2>/dev/null | tr -d '"' || echo "GPU$i")
            echo "  $name:"
            strings "/sys/class/drm/card${i}/device/rom" 2>/dev/null | grep -i -E "rtx|geforce|quadro" | head -2 | sed 's/^/    /'
        fi
    done
} | tee "$OUTPUT_DIR/05_vbios.txt"

echo "[6/6] RDMA Infrastructure..."
{
    echo "=== RDMA INFRASTRUCTURE ==="
    echo ""
    
    echo "nvidia-peermem module:"
    if lsmod | grep -q "nvidia_peermem"; then
        echo "  ✅ Loaded"
        lsmod | grep nvidia_peermem
    else
        echo "  ❌ Not loaded"
    fi
    echo ""
    
    echo "IB devices:"
    if command -v ibv_devices &> /dev/null; then
        ibv_devices 2>/dev/null | while read dev; do
            echo "  ✅ $dev"
        done || echo "  (none)"
    else
        echo "  ⚠️  ibv_devices not available"
    fi
    echo ""
    
    echo "Mellanox NICs:"
    lspci -nn | grep -i -E "mellanox|connectx" | while read line; do
        echo "  ✅ $line"
    done || echo "  (none found)"
} | tee "$OUTPUT_DIR/06_rdma.txt"

# -------------------------------------------------------------------------
# CREATE COMPARISON-READY SUMMARY
# -------------------------------------------------------------------------

echo ""
echo "Creating comparison summary..."

cat > "$OUTPUT_DIR/SUMMARY_FOR_COMPARISON.txt" << EOF
================================================================================
GPU SYSTEM SUMMARY - Ready for Cross-System Comparison
================================================================================

SYSTEM: $SYSTEM_NAME
DATE: $(date)
KERNEL: $(uname -r)
DRIVER: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)

GPU CONFIGURATION:
$(nvidia-smi --query-gpu=index,name,memory.total,BAR1,bar1_free,pci.device_id --format=csv)

PCI DEVICE IDS:
$(lspci -nn | grep -i "NVIDIA.*VGA" | awk '{print "  " $1 ": " $3 " -> Device ID " $4}')

BAR1 STATISTICS:
Min Free: $(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | sort -n | head -1 | xargs -I{} echo "scale=1; {} / 1024 / 1024" | bc)MB
Max Free: $(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | sort -n | tail -1 | xargs -I{} echo "scale=1; {} / 1024 / 1024" | bc)MB
Avg Free: $(nvidia-smi --query-gpu=bar1_free --format=csv,noheader | tr -d ' ' | awk '{sum+=$1; count++} END {printf "%.1f", sum/count/1024/1024}')MB

P2P SYMBOLS EXPORTED:
$([ -f /sys/module/nvidia/sections/.export_symbols ] && grep -c "nvidia_p2p" /sys/module/nvidia/sections/.export_symbols || echo "Unknown")

REQUIRED SYMBOLS STATUS:
$(if [ -f /sys/module/nvidia/sections/.export_symbols ]; then
    for sym in nvidia_p2p_get_pages nvidia_p2p_put_pages nvidia_p2p_dma_map_pages nvidia_p2p_free_dma_mapping; do
        if grep -q "$sym" /sys/module/nvidia/sections/.export_symbols; then
            echo "  ✅ $sym"
        else
            echo "  ❌ $sym"
        fi
    done
else
    echo "  (cannot check)"
fi)

RDMA MODULES:
$([ $(lsmod | grep -c "nvidia_peermem") -gt 0 ] && echo "  ✅ nvidia-peermem loaded" || echo "  ❌ nvidia-peermem not loaded")

IB DEVICES:
$(ibv_devices 2>/dev/null | sed 's/^/  ✅ /' || echo "  (none)")

MELLANOX NICs:
$(lspci -nn | grep -i -E "mellanox|connectx" | sed 's/^/  ✅ /' || echo "  (none)")

VBIOS VERSION:
$(nvidia-smi --query-gpu=index,vbios_version --format=csv | tail -n +2 | head -1 | cut -d',' -f2)

================================================================================
END OF SUMMARY
================================================================================
EOF

echo ""
echo "=== EXTRACTION COMPLETE ==="
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "Summary file: $OUTPUT_DIR/SUMMARY_FOR_COMPARISON.txt"
echo ""
echo "To compare two systems:"
echo "  1. Run this script on both systems"
echo "  2. Use: diff -u system_a/SUMMARY_FOR_COMPARISON.txt system_b/SUMMARY_FOR_COMPARISON.txt"
echo "  3. Or use the compare_gpu_systems.py script for detailed analysis"
echo ""
