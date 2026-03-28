# GPU Hardware Profiling Scripts - Usage Guide

## Overview

Three scripts to collect, extract, and compare GPU hardware data for RDMA capability analysis.

---

## Script 1: `gpu_hardware_profiler.sh`

**Purpose**: Comprehensive hardware profiling of a single system

**What it does**:
- Collects 12 categories of GPU/RDMA data
- Analyzes BAR1 sizes and IOMMU groups
- Checks exported P2P symbols
- Tests P2P capability
- Generates detailed summary with recommendations

**Usage**:
```bash
chmod +x gpu_hardware_profiler.sh
./gpu_hardware_profiler.sh
```

**Output**: `/workspace/gpu_profiler_<hostname>_YYYYMMDD_HHMMSS/` with:
- `01_system_info.txt` - Basic system details
- `02_nvidia_smi_full.txt` - Complete nvidia-smi output
- `03_gpu_details.txt` - Per-GPU analysis
- `04_pci_info.txt` - PCI device IDs (critical for spoofing)
- `05_iommu_groups.txt` - IOMMU topology
- `06_kernel_modules.txt` - Loaded modules and parameters
- `07_bar1_analysis.txt` - BAR1 size analysis
- `08_vbios_info.txt` - VBIOS data
- `09_rdma_devices.txt` - InfiniBand/RDMA info
- `10_exported_symbols.txt` - P2P symbol exports
- `11_p2p_capability.txt` - P2P access matrix
- `12_summary.txt` - Executive summary
- `QUICK_REFERENCE.txt` - Quick lookup for spoofing

**Run on**: Both RTX 6000 Ada and RTX 5090 systems

---

## Script 2: `gpu_comparison_extractor.sh`

**Purpose**: Extract comparison-ready data from a system

**What it does**:
- Pulls 6 key data categories for easy comparison
- Creates `SUMMARY_FOR_COMPARISON.txt` with side-by-side ready data
- Focuses on differences that matter for RDMA spoofing

**Usage**:
```bash
chmod +x gpu_comparison_extractor.sh

# Optional: specify system name
./gpu_comparison_extractor.sh "RTX6000-ServerA"
./gpu_comparison_extractor.sh "RTX5090-ServerB"
```

**Output**: `/workspace/gpu_compare_<name>_YYYYMMDD_HHMMSS/` with:
- `01_gpu_id.txt` - GPU identification
- `02_pci_ids.txt` - PCI device IDs
- `03_bar1.txt` - BAR1 analysis
- `04_symbols.txt` - P2P symbol exports
- `05_vbios.txt` - VBIOS data
- `06_rdma.txt` - RDMA infrastructure
- `SUMMARY_FOR_COMPARISON.txt` - Consolidated summary

**Run on**: Both systems, then compare outputs

---

## Script 3: `compare_gpu_systems.py`

**Purpose**: Automated comparison of two systems' GPU data

**What it does**:
- Parses `SUMMARY_FOR_COMPARISON.txt` from both systems
- Compares GPU configs, BAR1 sizes, symbols
- Generates recommendations for spoofing approach
- Identifies exact differences

**Usage**:
```bash
chmod +x compare_gpu_systems.py

# After running extraction on both systems:
python3 compare_gpu_systems.py \
    /workspace/gpu_compare_RTX6000-* \
    /workspace/gpu_compare_RTX5090-*
```

**Output**: Terminal display showing:
- ✅ Identical configurations
- ⚠️ Differences found
- ❌ Missing components
- Recommendations for RDMA enablement

---

## Complete Workflow

### Step 1: Profile Both Systems (Deep Analysis)

```bash
# On RTX 6000 Ada system
./gpu_hardware_profiler.sh
# Output: /workspace/gpu_profiler_server-ada-xxx/

# On RTX 5090 system  
./gpu_hardware_profiler.sh
# Output: /workspace/gpu_profiler_server-5090-xxx/
```

### Step 2: Extract Comparison Data

```bash
# On RTX 6000 Ada system
./gpu_comparison_extractor.sh "ADA-REFERENCE"
# Output: /workspace/gpu_compare_ADA-REFERENCE-xxx/

# On RTX 5090 system
./gpu_comparison_extractor.sh "5090-TARGET"
# Output: /workspace/gpu_compare_5090-TARGET-xxx/
```

### Step 3: Compare and Analyze

```bash
# On either system (after copying outputs)
python3 compare_gpu_systems.py \
    /workspace/gpu_compare_ADA-REFERENCE-* \
    /workspace/gpu_compare_5090-TARGET-*
```

### Step 4: Review Key Files

```bash
# Critical data for spoofing:
cat /workspace/gpu_compare_*/02_pci_ids.txt      # Device IDs
cat /workspace/gpu_compare_*/03_bar1.txt          # BAR1 sizes
cat /workspace/gpu_compare_*/04_symbols.txt       # Exported symbols
cat /workspace/gpu_compare_*/05_vbios.txt         # VBIOS info
```

---

## Quick Reference: What to Look For

### ✅ Good Signs (RDMA should work)
- Both systems have same PCI device ID format
- BAR1 free >= 512MB on both
- All 6 P2P symbols exported on both
- Same number of GPUs
- nvidia-peermem loads on both

### ⚠️ Potential Issues
- Different PCI device IDs (obvious - that's what we're spoofing)
- BAR1 < 256MB on 5090 (may need increase)
- Missing P2P symbols (need driver patch)
- nvidia-peermem not loading (dependency issue)

### 🎯 Spoofing Targets
From `02_pci_ids.txt`:
```
RTX 6000 Ada: Device ID = 0x2704  ← TARGET
RTX 5090:     Device ID = 0x2707  ← CURRENT
```

From `03_bar1.txt`:
```
RTX 6000 Ada: BAR1 free = 512-1024MB  ← EXPECTED
RTX 5090:     BAR1 free = 256MB       ← MAY NEED INCREASE
```

---

## Example Output Interpretation

### Device ID Section (from 02_pci_ids.txt)
```
All NVIDIA VGA devices:
  01:00.0: Vendor=0x10de, Device=0x2704  ← RTX 6000 Ada
  01:00.0: Vendor=0x10de, Device=0x2707  ← RTX 5090

Target spoof: Change 0x2707 → 0x2704
```

### BAR1 Section (from 03_bar1.txt)
```
GPU Name                    BAR1_Total    BAR1_Free     BAR1_Used
0   NVIDIA RTX 6000 Ada     1024MB        890MB         134MB    ← GOOD
0   NVIDIA GeForce RTX 5090 256MB         198MB         58MB     ← LOW
```

**Interpretation**: 5090 has smaller BAR1, may need increase for RDMA

### Symbols Section (from 04_symbols.txt)
```
nvidia_p2p_* symbols exported:
  ✅ nvidia_p2p_get_pages
  ✅ nvidia_p2p_put_pages
  ✅ nvidia_p2p_dma_map_pages
  ✅ nvidia_p2p_dma_unmap_pages
  ✅ nvidia_p2p_free_page_table
  ✅ nvidia_p2p_free_dma_mapping

Total nvidia_p2p symbols: 6  ← PERFECT
```

**Interpretation**: All required symbols present, ready for RDMA

---

## Troubleshooting

### Issue: Script says "IB devices: None found"
**Solution**: Install rdma-core:
```bash
sudo apt install rdma-core libibverbs1
```

### Issue: "Cannot check export_symbols"
**Solution**: Load nvidia module first:
```bash
sudo modprobe nvidia
```

### Issue: VBIOS strings not found
**Solution**: May need root or different access method:
```bash
sudo cat /sys/class/drm/card0/device/rom | strings | grep -i nvidia
```

### Issue: BAR1 shows 0 or very low
**Solution**: May need to unload P2P allocations:
```bash
# Reset GPU
sudo nvidia-smi -r -i 0
```

---

## Next Steps After Profiling

Once you've compared both systems:

1. **If BAR1 is sufficient** (>= 512MB):
   - Proceed with device ID spoofing
   - Or apply driver patch

2. **If BAR1 is low** (< 256MB):
   - Consider VBIOS modification to increase BAR1
   - Or use RESIZE_BAR in BIOS

3. **If symbols missing**:
   - Patch the driver to export symbols
   - Or use different driver version

4. **If everything matches except device ID**:
   - Easy spoof! Just change PCI device ID
   - Use module parameter or driver patch

---

## Files Created Summary

After running all scripts on both systems, you'll have:

```
/workspace/
├── gpu_profiler_<system1>_*/      # 12 detailed files + summary
├── gpu_profiler_<system2>_*/      # 12 detailed files + summary
├── gpu_compare_<system1>_*/       # 6 comparison files + summary
├── gpu_compare_<system2>_*/       # 6 comparison files + summary
├── gpu_hardware_profiler.sh       # Script 1
├── gpu_comparison_extractor.sh    # Script 2
├── compare_gpu_systems.py         # Script 3
└── PROFILING_README.md            # This file
```

**Total runtime**: ~5 minutes per system
**Data collected**: Complete hardware fingerprint for RDMA spoofing

---

*Created for RTX 6000 Ada vs RTX 5090 RDMA capability analysis*
