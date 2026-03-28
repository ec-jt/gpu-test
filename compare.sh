
#!/usr/bin/env python3
"""
GPU System Comparison Tool
Compares two GPU profiler outputs to identify differences for RDMA spoofing
"""

import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

def parse_gpu_summary(filepath):
    """Parse SUMMARY_FOR_COMPARISON.txt file"""
    data = {}
    
    try:
        with open(filepath, 'r') as f:
            content = f.read()
            
        # Extract key sections
        if 'SYSTEM:' in content:
            data['system'] = content.split('SYSTEM:')[1].split('\n')[0].strip()
        if 'DRIVER:' in content:
            data['driver'] = content.split('DRIVER:')[1].split('\n')[0].strip()
        if 'GPU CONFIGURATION:' in content:
            gpu_section = content.split('GPU CONFIGURATION:')[1].split('PCI DEVICE IDS:')[0]
            data['gpu_config'] = gpu_section.strip()
        if 'BAR1 STATISTICS:' in content:
            bar1_section = content.split('BAR1 STATISTICS:')[1].split('P2P SYMBOLS')[0]
            data['bar1_stats'] = bar1_section.strip()
        if 'REQUIRED SYMBOLS STATUS:' in content:
            symbols_section = content.split('REQUIRED SYMBOLS STATUS:')[1].split('RDMA MODULES:')[0]
            data['symbols'] = symbols_section.strip()
            
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        
    return data

def compare_systems(dir1, dir2):
    """Compare two GPU profiler output directories"""
    
    print("=" * 80)
    print("GPU SYSTEM COMPARISON ANALYSIS")
    print("=" * 80)
    print()
    
    # Find summary files
    summary1 = list(Path(dir1).glob("SUMMARY_FOR_COMPARISON.txt"))
    summary2 = list(Path(dir2).glob("SUMMARY_FOR_COMPARISON.txt"))
    
    if not summary1 or not summary2:
        print("❌ SUMMARY_FOR_COMPARISON.txt not found in one or both directories")
        print("   Run gpu_comparison_extractor.sh on both systems first")
        return
    
    summary1 = summary1[0]
    summary2 = summary2[0]
    
    print(f"System 1: {summary1.parent.name}")
    print(f"System 2: {summary2.parent.name}")
    print()
    
    # Parse both summaries
    data1 = parse_gpu_summary(summary1)
    data2 = parse_gpu_summary(summary2)
    
    # Compare basic info
    print("-" * 80)
    print("BASIC INFORMATION")
    print("-" * 80)
    print(f"{'Attribute':<20} {'System 1':<40} {'System 2':<40}")
    print(f"{'-'*20} {'-'*40} {'-'*40}")
    print(f"{'Hostname':<20} {data1.get('system', 'N/A'):<40} {data2.get('system', 'N/A'):40}")
    print(f"{'Driver Version':<20} {data1.get('driver', 'N/A'):<40} {data2.get('driver', 'N/A'):40}")
    print()
    
    # Compare GPU configurations
    print("-" * 80)
    print("GPU CONFIGURATION")
    print("-" * 80)
    
    config1 = data1.get('gpu_config', '')
    config2 = data2.get('gpu_config', '')
    
    if config1 == config2:
        print("✅ Both systems have IDENTICAL GPU configuration")
    else:
        print("⚠️  GPU configurations DIFFER:")
        print("\nSystem 1:")
        print(config1)
        print("\nSystem 2:")
        print(config2)
    print()
    
    # Compare BAR1 statistics
    print("-" * 80)
    print("BAR1 STATISTICS")
    print("-" * 80)
    
    bar1_1 = data1.get('bar1_stats', '')
    bar1_2 = data2.get('bar1_stats', '')
    
    # Extract min values
    min1 = [line for line in bar1_1.split('\n') if 'Min Free:' in line]
    min2 = [line for line in bar1_2.split('\n') if 'Min Free:' in line]
    
    if min1 and min2:
        print(f"System 1 Min BAR1 Free: {min1[0]}")
        print(f"System 2 Min BAR1 Free: {min2[0]}")
        
        # Parse values
        try:
            val1 = float(min1[0].split(':')[1].strip().replace('MB', ''))
            val2 = float(min2[0].split(':')[1].strip().replace('MB', ''))
            
            if abs(val1 - val2) < 10:
                print("✅ BAR1 sizes are SIMILAR (within 10MB)")
            else:
                print(f"⚠️  BAR1 size difference: {abs(val1 - val2):.1f}MB")
        except:
            pass
    print()
    
    # Compare symbols
    print("-" * 80)
    print("P2P SYMBOL EXPORTS")
    print("-" * 80)
    
    syms1 = data1.get('symbols', '')
    syms2 = data2.get('symbols', '')
    
    check1 = syms1.count('✅')
    check2 = syms2.count('✅')
    cross1 = syms1.count('❌')
    cross2 = syms2.count('❌')
    
    print(f"System 1: {check1} exported, {cross1} missing")
    print(f"System 2: {check2} exported, {cross2} missing")
    
    if check1 == check2 == 6:
        print("✅ Both systems have ALL required symbols exported")
    elif cross1 > 0 or cross2 > 0:
        print("⚠️  Some symbols missing - RDMA may not work!")
        print("\nSystem 1 symbols:")
        print(syms1)
        print("\nSystem 2 symbols:")
        print(syms2)
    print()
    
    # Detailed file comparison
    print("-" * 80)
    print("DETAILED FILE COMPARISON")
    print("-" * 80)
    
    files1 = sorted([f.name for f in Path(dir1).glob("*.txt")])
    files2 = sorted([f.name for f in Path(dir2).glob("*.txt")])
    
    common_files = set(files1) & set(files2)
    
    for filename in sorted(common_files):
        if filename in ['SUMMARY_FOR_COMPARISON.txt', 'QUICK_REFERENCE.txt']:
            continue
            
        file1 = Path(dir1) / filename
        file2 = Path(dir2) / filename
        
        # Simple line count comparison
        lines1 = len(file1.read_text().split('\n'))
        lines2 = len(file2.read_text().split('\n'))
        
        if lines1 == lines2:
            status = "✅"
        else:
            status = "⚠️"
            
        print(f"{status} {filename:<30} System1: {lines1:4d} lines, System2: {lines2:4d} lines")
    
    print()
    
    # Generate recommendations
    print("=" * 80)
    print("RECOMMENDATIONS")
    print("=" * 80)
    print()
    
    recommendations = []
    
    # Check if one system looks like Ada and other like 5090
    if '6000' in config1 and '5090' in config2:
        recommendations.append("🎯 Perfect setup! System 1 (RTX 6000 Ada) can be golden reference for System 2 (RTX 5090)")
    elif '5090' in config1 and '6000' in config2:
        recommendations.append("🎯 Perfect setup! System 2 (RTX 6000 Ada) can be golden reference for System 1 (RTX 5090)")
    
    # BAR1 recommendations
    if min1 and min2:
        try:
            val1 = float(min1[0].split(':')[1].strip().replace('MB', ''))
            val2 = float(min2[0].split(':')[1].strip().replace('MB', ''))
            
            if val1 < 256 or val2 < 256:
                recommendations.append("⚠️  Low BAR1 detected! Consider increasing BAR1 size before RDMA testing")
            if abs(val1 - val2) > 100:
                recommendations.append(f"⚠️  Large BAR1 difference ({abs(val1-val2):.0f}MB) - may affect RDMA compatibility")
        except:
            pass
    
    # Symbol recommendations
    if cross1 > 0 or cross2 > 0:
        recommendations.append("❌ Missing P2P symbols! Need to patch driver or use different version")
    elif check1 == check2 == 6:
        recommendations.append("✅ All P2P symbols present - ready for RDMA patching")
    
    # General recommendations
    recommendations.append("📋 Next steps:")
    recommendations.append("   1. Review detailed outputs in both directories")
    recommendations.append("   2. If symbols match, proceed with RDMA capability patch")
    recommendations.append("   3. If BAR1 differs, may need VBIOS or firmware modification")
    recommendations.append("   4. Use the reference system to test patches first")
    
    for rec in recommendations:
        print(rec)
    
    print()
    print("=" * 80)
    print(f"Analysis complete at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)

def main():
    parser = argparse.ArgumentParser(description='Compare two GPU profiler outputs')
    parser.add_argument('system1', help='Path to first system profiler output')
    parser.add_argument('system2', help='Path to second system profiler output')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    if not os.path.isdir(args.system1):
        print(f"❌ Directory not found: {args.system1}")
        sys.exit(1)
    
    if not os.path.isdir(args.system2):
        print(f"❌ Directory not found: {args.system2}")
        sys.exit(1)
    
    compare_systems(args.system1, args.system2)

if __name__ == '__main__':
    main()
