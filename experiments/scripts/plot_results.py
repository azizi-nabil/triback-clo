#!/usr/bin/env python3
"""
Plot experiment results for TriBack-Clo paper.
"""

import json
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path
from collections import defaultdict

RESULTS_DIR = Path(__file__).parent.parent / "results"
PLOTS_DIR = Path(__file__).parent.parent / "plots"

def load_results(experiment):
    """Load results from JSONL file"""
    results_file = RESULTS_DIR / f"experiment_{experiment}.jsonl"
    if not results_file.exists():
        return []
    
    results = []
    with open(results_file) as f:
        for line in f:
            results.append(json.loads(line))
    return results

def plot_experiment_A():
    """Plot Performance Cliff: Runtime vs Support"""
    results = load_results("A")
    if not results:
        print("No results for Experiment A")
        return
    
    # Group by dataset
    by_dataset = defaultdict(lambda: defaultdict(list))
    for r in results:
        by_dataset[r["dataset"]][r["algorithm"]].append((r["ratio"], r["runtime_sec"]))
    
    PLOTS_DIR.mkdir(exist_ok=True)
    
    for dataset, algos in by_dataset.items():
        plt.figure(figsize=(10, 6))
        
        for algo, points in algos.items():
            points = sorted(points, key=lambda x: -x[0])  # Sort by decreasing ratio
            ratios = [p[0] * 100 for p in points]  # Convert to %
            runtimes = [p[1] for p in points]
            
            marker = 'o' if algo == "TriBack-Clo" else 's'
            plt.plot(ratios, runtimes, marker=marker, label=algo, linewidth=2, markersize=8)
        
        plt.xlabel("Minimum Support (%)", fontsize=12)
        plt.ylabel("Runtime (seconds)", fontsize=12)
        plt.title(f"Performance Cliff: {dataset}", fontsize=14)
        plt.yscale("log")
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.gca().invert_xaxis()  # Decreasing support
        
        plt.tight_layout()
        plt.savefig(PLOTS_DIR / f"experiment_A_{dataset}.png", dpi=150)
        plt.close()
        print(f"Saved: experiment_A_{dataset}.png")

def plot_experiment_D():
    """Plot Ablation Study: Bar chart"""
    results = load_results("D")
    if not results:
        print("No results for Experiment D")
        return
    
    # Group by dataset
    by_dataset = defaultdict(dict)
    for r in results:
        by_dataset[r["dataset"]][r["algorithm"]] = r["runtime_sec"]
    
    PLOTS_DIR.mkdir(exist_ok=True)
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
    datasets = list(by_dataset.keys())
    x = np.arange(len(datasets))
    width = 0.35
    
    full_times = [by_dataset[d].get("TriBack-Clo (Full)", 0) for d in datasets]
    noprune_times = [by_dataset[d].get("TriBack-Clo (No Prune)", 0) for d in datasets]
    
    bars1 = ax.bar(x - width/2, full_times, width, label='TriBack-Clo (Full)', color='#2ecc71')
    bars2 = ax.bar(x + width/2, noprune_times, width, label='TriBack-Clo (No Prune)', color='#e74c3c')
    
    ax.set_xlabel('Dataset', fontsize=12)
    ax.set_ylabel('Runtime (seconds)', fontsize=12)
    ax.set_title('Ablation Study: BackScan Pruning Impact', fontsize=14)
    ax.set_xticks(x)
    ax.set_xticklabels(datasets)
    ax.legend()
    ax.grid(True, alpha=0.3, axis='y')
    
    # Add speedup annotations
    for i, (f, n) in enumerate(zip(full_times, noprune_times)):
        if f > 0 and n > 0:
            speedup = n / f
            ax.annotate(f'{speedup:.1f}x', xy=(i, max(f, n)), ha='center', va='bottom', fontsize=10)
    
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / "experiment_D_ablation.png", dpi=150)
    plt.close()
    print("Saved: experiment_D_ablation.png")

def generate_latex_table():
    """Generate LaTeX table for paper"""
    results = load_results("A")
    if not results:
        return
    
    print("\n% LaTeX Table for Paper")
    print("\\begin{table}[h]")
    print("\\centering")
    print("\\caption{Performance Comparison}")
    print("\\begin{tabular}{l|c|c|c|c}")
    print("\\hline")
    print("Dataset & minsup & TriBack-Clo & BIDE+ & Speedup \\\\")
    print("\\hline")
    
    # Group and display
    by_dataset_ratio = defaultdict(dict)
    for r in results:
        key = (r["dataset"], r["ratio"])
        by_dataset_ratio[key][r["algorithm"]] = r["runtime_sec"]
    
    for (dataset, ratio), algos in sorted(by_dataset_ratio.items()):
        tb = algos.get("TriBack-Clo", "-")
        bide = algos.get("BIDE+", "-")
        if isinstance(tb, float) and isinstance(bide, float):
            speedup = f"{bide/tb:.1f}x"
            print(f"{dataset} & {ratio*100:.2f}\\% & {tb:.1f}s & {bide:.1f}s & {speedup} \\\\")
    
    print("\\hline")
    print("\\end{tabular}")
    print("\\end{table}")

def main():
    print("Generating plots from experiment results...")
    plot_experiment_A()
    plot_experiment_D()
    generate_latex_table()
    print(f"\nPlots saved to: {PLOTS_DIR}")

if __name__ == "__main__":
    main()
