#!/usr/bin/env python3
"""
Parse experiment logs and generate benchmark results CSV.
"""
import os
import re
import csv
from pathlib import Path
from collections import defaultdict

LOGS_DIR = Path(__file__).parent / "logs"
OUTPUT_CSV = Path(__file__).parent / "results" / "benchmark_results.csv"

def parse_tribackclo_log(filepath):
    """Parse TriBack-Clo log file."""
    with open(filepath, 'r') as f:
        content = f.read()
    
    result = {}
    
    # Mining time
    match = re.search(r'Mining completed in ([\d.]+) seconds', content)
    if match:
        result['mining_time_s'] = float(match.group(1))

    match = re.search(r'\bMining:\s+([\d.]+)\s+seconds\b', content)
    if match:
        result['mining_time_s'] = float(match.group(1))
    
    # Total time
    match = re.search(r'\[TIME\].*Mining: ([\d.]+) s.*Total: ([\d.]+) s', content)
    if match:
        result['mining_time_s'] = float(match.group(1))
        result['total_time_s'] = float(match.group(2))

    match = re.search(r'Total time ~\s*(\d+)\s*ms', content)
    if match:
        total_s = int(match.group(1)) / 1000.0
        result['mining_time_s'] = total_s
        result['total_time_s'] = total_s
    
    # Patterns
    match = re.search(r'Closed patterns found: ([\d,]+)', content)
    if match:
        result['patterns'] = int(match.group(1).replace(',', ''))

    match = re.search(r'Pattern count\s*:\s*([\d,]+)', content)
    if match:
        result['patterns'] = int(match.group(1).replace(',', ''))
    
    # Nodes visited
    match = re.search(r'Nodes visited: ([\d,]+)', content)
    if match:
        result['nodes'] = int(match.group(1).replace(',', ''))
    
    # Subtrees pruned
    match = re.search(r'Subtrees pruned: ([\d,]+)', content)
    if match:
        result['pruned'] = int(match.group(1).replace(',', ''))

    # Memory
    match = re.search(r'Max memory \(mb\)\s*:\s*([\d.]+)', content)
    if match:
        result['memory_mb'] = float(match.group(1))
    
    return result

def parse_spmf_log(filepath):
    """Parse SPMF algorithm log file (BIDE+, ClaSP, CloSpan, CloFast)."""
    with open(filepath, 'r') as f:
        content = f.read()
    
    result = {}
    
    # Total time
    match = re.search(r'Total time ~ (\d+) ms', content)
    if match:
        result['mining_time_s'] = int(match.group(1)) / 1000.0
        result['total_time_s'] = result['mining_time_s']

    match = re.search(r'Total time:\s*([\d.]+)\s*s', content)
    if match:
        total_s = float(match.group(1))
        result['mining_time_s'] = total_s
        result['total_time_s'] = total_s
    
    # Pattern count
    match = re.search(r'Pattern count : (\d+)', content)
    if match:
        result['patterns'] = int(match.group(1))

    match = re.search(r'Frequent closed sequences count\s*:\s*([\d,]+)', content)
    if match:
        result['patterns'] = int(match.group(1).replace(',', ''))

    match = re.search(r'Frequent sequences count\s*:\s*([\d,]+)', content)
    if match:
        result['patterns'] = int(match.group(1).replace(',', ''))

    match = re.search(r'Number of closed Patterns found\s*:\s*([\d,]+)', content)
    if match:
        result['patterns'] = int(match.group(1).replace(',', ''))
    
    # Memory
    match = re.search(r'Max memory \(mb\) : ([\d.]+)', content)
    if match:
        result['memory_mb'] = float(match.group(1))

    match = re.search(r'Max memory \(mb\):\s*([\d.]+)', content)
    if match:
        result['memory_mb'] = float(match.group(1))
    
    return result

def parse_filename(filename):
    """Extract algorithm, dataset, ratio, run from filename."""
    # Format: Algorithm_Dataset_Ratio_RunType_Timestamp.log
    # Example: TriBack-Clo_BMS2_0.01_run1_20251223_163244.log
    # The dataset segment may itself contain underscores, e.g. MSNBC_small.
    stem = filename.replace('.log', '')
    match = re.match(
        r'^(?P<algorithm>[^_]+)_(?P<dataset>.+?)_(?P<ratio>0\.\d+)_(?P<run>run(?:warmup\d+|\d+))(?:_|$)',
        stem,
    )

    if not match:
        return {
            'algorithm': None,
            'dataset': None,
            'ratio': None,
            'run_type': None
        }

    return {
        'algorithm': match.group('algorithm'),
        'dataset': match.group('dataset'),
        'ratio': float(match.group('ratio')),
        'run_type': match.group('run')
    }

def main():
    results = []
    
    for logfile in sorted(LOGS_DIR.glob('*.log')):
        filename = logfile.name
        
        # Skip warmup runs for final results
        if 'warmup' in filename:
            continue
        
        # Parse filename
        info = parse_filename(filename)
        if info['ratio'] is None:
            continue
        
        # Parse log content based on algorithm
        if 'TriBack-Clo' in filename:
            data = parse_tribackclo_log(logfile)
        else:
            data = parse_spmf_log(logfile)
        
        if not data:
            continue
        
        # Merge info and data
        row = {
            'algorithm': info['algorithm'],
            'dataset': info['dataset'],
            'ratio': info['ratio'],
            'run': info['run_type'],
            'mining_time_s': data.get('mining_time_s', ''),
            'total_time_s': data.get('total_time_s', ''),
            'patterns': data.get('patterns', ''),
            'nodes': data.get('nodes', ''),
            'pruned': data.get('pruned', ''),
            'memory_mb': data.get('memory_mb', '')
        }
        results.append(row)
    
    # Sort by dataset, ratio, algorithm, run
    results.sort(key=lambda x: (x['dataset'], x['ratio'], x['algorithm'], x['run'] or ''))
    
    # Write CSV
    OUTPUT_CSV.parent.mkdir(exist_ok=True)
    with open(OUTPUT_CSV, 'w', newline='') as f:
        fieldnames = ['algorithm', 'dataset', 'ratio', 'run', 'mining_time_s', 'total_time_s', 'patterns', 'nodes', 'pruned', 'memory_mb']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)
    
    print(f"Generated {OUTPUT_CSV} with {len(results)} rows")
    
    # Print summary statistics
    print("\n=== Summary by Dataset and Algorithm ===")
    summary = defaultdict(lambda: defaultdict(list))
    for r in results:
        key = (r['dataset'], r['algorithm'], r['ratio'])
        if r['mining_time_s']:
            summary[key]['times'].append(r['mining_time_s'])
        if r['patterns']:
            summary[key]['patterns'].append(r['patterns'])
    
    for (dataset, algo, ratio), data in sorted(summary.items()):
        times = data['times']
        patterns = data['patterns']
        if times:
            avg_time = sum(times) / len(times)
            pattern_count = patterns[0] if patterns else 0
            print(f"{dataset:12} {algo:12} {ratio:.4f}: {avg_time:8.3f}s  {pattern_count:6} patterns")

if __name__ == '__main__':
    main()
