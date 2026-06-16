#!/usr/bin/env python3
import os
import sys
from pathlib import Path
from collections import defaultdict
import parse_logs

EXPERIMENTS_DIR = Path(__file__).parent
OUTPUT_MD = EXPERIMENTS_DIR / "results" / "BENCHMARK_RESULTS_ITEMSETS.md"


def display_algorithm_name(name):
    if name in {"TriBack-Clo", "TriBack-Clo-Java"}:
        return "TriBack-Clo"
    if name == "CloFast":
        return "CloFAST"
    return name

def process_directory(log_dir, title):
    results = []
    
    for logfile in sorted(log_dir.glob('*.log')):
        filename = logfile.name
        
        if 'warmup' in filename:
            continue
            
        info = parse_logs.parse_filename(filename)
        if info['ratio'] is None:
            continue
            
        if 'TriBack-Clo' in filename:
            with open(logfile, 'r') as f:
                content = f.read()
            if 'SPMF-compatible' in content:
                data = parse_logs.parse_spmf_log(logfile)
            else:
                data = parse_logs.parse_tribackclo_log(logfile)
        else:
            data = parse_logs.parse_spmf_log(logfile)
            
        if not data:
            continue
            
        row = {
            'algorithm': info['algorithm'],
            'dataset': info['dataset'],
            'ratio': info['ratio'],
            'mining_time_s': data.get('mining_time_s', ''),
            'total_time_s': data.get('total_time_s', ''),
            'patterns': data.get('patterns', ''),
            'memory_mb': data.get('memory_mb', '')
        }
        results.append(row)
        
    # Aggregate by dataset, algorithm, ratio
    summary = defaultdict(lambda: defaultdict(list))
    for r in results:
        key = (r['dataset'], r['algorithm'], r['ratio'])
        if r['mining_time_s']:
            summary[key]['times'].append(r['mining_time_s'])
        if r['total_time_s']:
            summary[key]['wall_times'].append(r['total_time_s'])
        if r['patterns']:
            summary[key]['patterns'].append(r['patterns'])
        if r['memory_mb']:
            summary[key]['memory'].append(r['memory_mb'])

    aggregated = []
    for (dataset, algo, ratio), data in summary.items():
        avg_time = sum(data['times']) / len(data['times']) if data['times'] else 0
        avg_wall = sum(data['wall_times']) / len(data['wall_times']) if data['wall_times'] else 0
        patterns = data['patterns'][0] if data['patterns'] else 0
        memory = sum(data['memory']) / len(data['memory']) if data['memory'] else 0
        
        aggregated.append({
            'dataset': dataset,
            'Algorithm': algo,
            'Ratio': ratio,
            'mining_time': avg_time,
            'wall_time': avg_wall,
            'patterns': patterns,
            'memory': memory
        })

    # Group by Dataset and Ratio
    tables = defaultdict(list)
    for r in aggregated:
        tables[(r['dataset'], r['Ratio'])].append(r)
        
    markdown_output = f"\n\n---\n\n## {title}\n\n"
    
    # Sort datasets based on D-number then C/T if possible, or just alphabetically
    for (dataset, ratio) in sorted(tables.keys()):
        markdown_output += f"### {dataset} Dataset (Support {ratio*100}%)\n\n"
        markdown_output += "| Algorithm | Mining (s) | Wall (s) | Patterns | Memory (MB) | Status |\n"
        markdown_output += "|-----------|------------|----------|----------|-------------|--------|\n"
        
        algo_order = ["TriBack-Clo", "BIDE+", "CloFAST", "ClaSP", "CloSpan"]
        
        def algo_sort_key(item):
            algo_name = display_algorithm_name(item['Algorithm'])
            try:
                return algo_order.index(algo_name)
            except ValueError:
                return 999
                
        sorted_rows = sorted(tables[(dataset, ratio)], key=algo_sort_key)
        for r in sorted_rows:
            algo_name = display_algorithm_name(r['Algorithm'])
            if algo_name == 'TriBack-Clo':
                algo_name = '**TriBack-Clo**'
            
            memory_str = f"{r['memory']:.0f} MB" if r['memory'] > 0 else "—"
            if r['memory'] > 1024:
                memory_str = f"{r['memory']/1024:.2f} GB"
                
            mining_str = f"{r['mining_time']:.3f}" if r['mining_time'] > 0 else "—"
            wall_str = f"{r['wall_time']:.3f}" if r['wall_time'] > 0 else "—"
            
            patterns = r['patterns'] if r['patterns'] > 0 else 0
            
            status = "OK"
            if "CloFAST" in algo_name and r['mining_time'] == 0:
                 status = "OOM/Timeout"
                 
            markdown_output += f"| {algo_name} | {mining_str} | {wall_str} | {patterns} | {memory_str} | {status} |\n"
        
        markdown_output += "\n"

    with open(OUTPUT_MD, 'a') as f:
        f.write(markdown_output)

if __name__ == '__main__':
    log_dirs = {
        "logs_fig15": "S/I Parameter Grid Experiments (Varying Maximal Sequence Length and Planted Itemset Size)",
        "logs_scalability_D": "Scalability Experiments (Varying Number of Sequences)"
    }
    
    for dirname, title in log_dirs.items():
        d = EXPERIMENTS_DIR / dirname
        if d.exists():
            process_directory(d, title)
            print(f"Processed {dirname}")
        else:
            print(f"Directory {dirname} not found")
