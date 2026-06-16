#!/usr/bin/env python3
"""
Generate benchmark graphs: Time (s) vs Support for each dataset.
Similar to CloFAST paper style.
"""
import csv
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path
from collections import defaultdict

RESULTS_CSV = Path(__file__).parent / "results" / "benchmark_results.csv"
OUTPUT_DIR = Path(__file__).parent / "results" / "graphs"

# Algorithm display settings
ALGO_STYLES = {
    'BIDE+': {'color': 'blue', 'marker': 'o', 'linestyle': '--', 'linewidth': 1.5},
    'ClaSP': {'color': 'green', 'marker': '^', 'linestyle': ':', 'linewidth': 1.5},
    'CloSpan': {'color': 'purple', 'marker': 'd', 'linestyle': '-.', 'linewidth': 1.5},
    'CloFast': {'color': 'orange', 'marker': 'v', 'linestyle': '-', 'linewidth': 1.5},
    'TriBack-Clo': {'color': 'brown', 'marker': 'x', 'linestyle': '-', 'linewidth': 1.5},
}

def load_results():
    """Load results from CSV and compute averages."""
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    
    with open(RESULTS_CSV, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            dataset = row['dataset']
            algo = row['algorithm']
            ratio = float(row['ratio'])
            
            if row['mining_time_s']:
                time_s = float(row['mining_time_s'])
                data[dataset][algo][ratio].append(time_s)
    
    # Compute averages
    averages = {}
    for dataset, algos in data.items():
        averages[dataset] = {}
        for algo, ratios in algos.items():
            averages[dataset][algo] = {}
            for ratio, times in ratios.items():
                averages[dataset][algo][ratio] = sum(times) / len(times)
    
    return averages

def generate_graph(dataset, algo_data, output_path):
    """Generate a single graph for a dataset."""
    plt.figure(figsize=(8, 6))
    
    for algo, ratios in sorted(algo_data.items()):
        if not ratios:
            continue
        
        # Sort by ratio (descending for x-axis like the reference image)
        sorted_ratios = sorted(ratios.keys(), reverse=True)
        times = [ratios[r] for r in sorted_ratios]
        
        # Convert ratios to percentages for display
        support_pct = [r * 100 for r in sorted_ratios]
        
        style = ALGO_STYLES.get(algo, {'color': 'gray', 'marker': 'o', 'linestyle': '-', 'linewidth': 1})
        
        plt.plot(support_pct, times, 
                 label=algo,
                 color=style['color'],
                 marker=style['marker'],
                 linestyle=style['linestyle'],
                 linewidth=style['linewidth'],
                 markersize=8)
    
    plt.xlabel('Support (%)', fontsize=12)
    plt.ylabel('Time (s)', fontsize=12)
    plt.title(f'{dataset} Dataset - Execution Time Comparison', fontsize=14)
    plt.legend(loc='upper right', fontsize=10)
    plt.grid(True, alpha=0.3)
    
    # Use log scale for y-axis if there's a big range
    times_all = [t for algo_ratios in algo_data.values() for t in algo_ratios.values()]
    if times_all and max(times_all) / max(min(times_all), 0.001) > 100:
        plt.yscale('log')
    
    # Invert x-axis (lower support = harder = right side)
    plt.gca().invert_xaxis()
    
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"Generated: {output_path}")

def generate_latex_table(dataset, algo_data, output_path):
    """Generate LaTeX table for a dataset."""
    # Get all unique ratios
    all_ratios = set()
    for algo, ratios in algo_data.items():
        all_ratios.update(ratios.keys())
    all_ratios = sorted(all_ratios, reverse=True)
    
    # Get algorithms that have data
    algos = sorted([a for a in algo_data.keys() if algo_data[a]])
    
    with open(output_path, 'w') as f:
        # Header
        f.write(f"% {dataset} Dataset - Execution Time (seconds)\n")
        cols = 'l' + 'r' * len(algos)
        f.write(f"\\begin{{tabular}}{{{cols}}}\n")
        f.write("\\toprule\n")
        f.write("Support & " + " & ".join(algos) + " \\\\\n")
        f.write("\\midrule\n")
        
        # Data rows
        for ratio in all_ratios:
            row = [f"{ratio*100:.2f}\\%"]
            for algo in algos:
                time = algo_data[algo].get(ratio)
                if time is not None:
                    if time < 1:
                        row.append(f"{time:.3f}")
                    elif time < 100:
                        row.append(f"{time:.2f}")
                    else:
                        row.append(f"{time:.1f}")
                else:
                    row.append("--")
            f.write(" & ".join(row) + " \\\\\n")
        
        f.write("\\bottomrule\n")
        f.write("\\end{tabular}\n")
    
    print(f"Generated: {output_path}")

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    data = load_results()
    
    for dataset, algo_data in data.items():
        # Generate PNG graph
        graph_path = OUTPUT_DIR / f"{dataset}_time_comparison.png"
        generate_graph(dataset, algo_data, graph_path)
        
        # Generate LaTeX table
        table_path = OUTPUT_DIR / f"{dataset}_time_table.tex"
        generate_latex_table(dataset, algo_data, table_path)
    
    print(f"\nAll graphs and tables saved to: {OUTPUT_DIR}")

if __name__ == '__main__':
    main()
