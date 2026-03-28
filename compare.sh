#!/bin/bash
# Quick GPU Data Comparison Script
# Usage: ./compare.sh <server1_data_dir> <server2_data_dir>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <server1_profiler_dir> <server2_profiler_dir>"
    echo "Example: $0 gpu_profiler_dc-kh-inferno-04_* gpu_profiler_ec-james_*"
    exit 1
fi

DIR1=$(ls -d $1 2>/dev/null | head -1)
DIR2=$(ls -d $2 2>/dev/null | head -1)

if [ -z "$DIR1" ] || [ -z "$DIR2" ]; then
    echo "❌ One or both directories not found!"
    echo "DIR1: $DIR1"
    echo "DIR2: $DIR2"
    echo ""
    echo "Available directories:"
    ls -d gpu_* 2>/dev/null || echo "  (none)"
    exit 1
fi

echo "=============================================="
echo "GPU SYSTEM QUICK COMPARISON"
echo "=============================================="
echo ""
echo "System 1: $DIR1"
echo "System 2: $DIR2"
echo ""

# Compare GPU counts
echo "[1] GPU Count"
if [ -f "$DIR1/01_system_info.txt" ]; then
    GPU1=$(grep -i "Found.*GPUs" "$DIR1/11_p2p_capability.txt" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    echo "  System 1: ${GPU1:-unknown} GPUs"
fi
if [ -f "$DIR2/01_system_info.txt" ]; then
    GPU2=$(grep -i "Found.*GPUs" "$DIR2/11_p2p_capability.txt" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    echo "  System 2: ${GPU2:-unknown} GPUs"
fi
echo ""

# Compare GPU models
echo "[2] GPU Models"
if [ -f "$DIR1/03_gpu_details.txt" ]; then
    echo "  System 1:"
    grep "Name:" "$DIR1/03_gpu_details.txt" 2>/dev/null | head -8 | sed 's/^/    /'
fi
if [ -f "$DIR2/03_gpu_details.txt" ]; then
    echo "  System 2:"
    grep "Name:" "$DIR2/03_gpu_details.txt" 2>/dev/null | head -8 | sed 's/^/    /'
fi
echo ""

# Compare PCI Device IDs
echo "[3] PCI Device IDs (for spoofing)"
if [ -f "$DIR1/04_pci_info.txt" ]; then
    echo "  System 1:"
    grep -i "NVIDIA.*VGA" "$DIR1/04_pci_info.txt" 2>/dev/null | head -4 | sed 's/^/    /'
fi
if [ -f "$DIR2/04_pci_info.txt" ]; then
    echo "  System 2:"
    grep -i "NVIDIA.*VGA" "$DIR2/04_pci_info.txt" 2>/dev/null | head -4 | sed 's/^/    /'
fi
echo ""

# Compare BAR1 sizes
echo "[4] BAR1 Free Space (critical for RDMA)"
if [ -f "$DIR1/07_bar1_analysis.txt" ]; then
    echo "  System 1:"
    grep -A3 "Recommendation:" "$DIR1/07_bar1_analysis.txt" 2>/dev/null | sed 's/^/    /'
fi
if [ -f "$DIR2/07_bar1_analysis.txt" ]; then
    echo "  System 2:"
    grep -A3 "Recommendation:" "$DIR2/07_bar1_analysis.txt" 2>/dev/null | sed 's/^/    /'
fi
echo ""

# Compare P2P symbols
echo "[5] P2P Exported Symbols"
if [ -f "$DIR1/10_exported_symbols.txt" ]; then
    COUNT1=$(grep -c "nvidia_p2p" "$DIR1/10_exported_symbols.txt" 2>/dev/null || echo 0)
    echo "  System 1: $COUNT1 symbols"
fi
if [ -f "$DIR2/10_exported_symbols.txt" ]; then
    COUNT2=$(grep -c "nvidia_p2p" "$DIR2/10_exported_symbols.txt" 2>/dev/null || echo 0)
    echo "  System 2: $COUNT2 symbols"
fi
echo ""

# Compare nvidia-peermem status
echo "[6] RDMA Module Status"
if [ -f "$DIR1/09_rdma_devices.txt" ]; then
    echo "  System 1:"
    grep -A2 "Peer Memory" "$DIR1/09_rdma_devices.txt" 2>/dev/null | sed 's/^/    /' | head -3
fi
if [ -f "$DIR2/09_rdma_devices.txt" ]; then
    echo "  System 2:"
    grep -A2 "Peer Memory" "$DIR2/09_rdma_devices.txt" 2>/dev/null | sed 's/^/    /' | head -3
fi
echo ""

# Check for QUICK_REFERENCE files
echo "[7] Quick Reference Files"
if [ -f "$DIR1/QUICK_REFERENCE.txt" ]; then
    echo "  ✅ System 1 has QUICK_REFERENCE.txt"
    grep "TARGET SPOOF" "$DIR1/QUICK_REFERENCE.txt" 2>/dev/null | sed 's/^/    /'
fi
if [ -f "$DIR2/QUICK_REFERENCE.txt" ]; then
    echo "  ✅ System 2 has QUICK_REFERENCE.txt"
    grep "TARGET SPOOF" "$DIR2/QUICK_REFERENCE.txt" 2>/dev/null | sed 's/^/    /'
fi
echo ""

echo "=============================================="
echo "COMPARISON COMPLETE"
echo "=============================================="
echo ""
echo "For detailed comparison, use:"
echo "  python3 compare_gpu_systems.py $DIR1 $DIR2"
echo ""
