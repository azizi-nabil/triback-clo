import csv
import os
import glob
from collections import defaultdict

# Find latest CSV
csv_files = glob.glob("experiments/results/benchmark_itemsets_*.csv")
if not csv_files:
    print("No CSV files found!")
    exit(1)
    
latest_csv = max(csv_files, key=os.path.getctime)
print(f"Reading from: {latest_csv}")

output_md = "experiments/results/BENCHMARK_RESULTS_ITEMSETS.md"

# Config
algo_order = ["TriBack-Clo-Java", "BIDE+", "CloFast", "ClaSP", "CloSpan"]
# Nicer names
algo_names = {
    "TriBack-Clo-Java": "**TriBack-Clo**",
    "BIDE+": "BIDE+",
    "CloFast": "CloFast",
    "ClaSP": "ClaSP",
    "CloSpan": "CloSpan"
}

data = defaultdict(dict)

with open(latest_csv, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        ds = row['dataset']
        ratio = row['ratio']
        algo = row['algorithm']
        
        # Key: (dataset, ratio)
        data[(ds, ratio)][algo] = row

# Helper to categorize datasets
def get_series(ds_name):
    if ds_name.startswith("D10"): return "D10 Series: Density Sweep (N=10k, T=20)"
    if ds_name.startswith("D20"): return "D20 Series: Long Sequences (N=20k, T=2.5)"
    if ds_name.startswith("D50"): return "D50 Series: Transaction Length Sweep (N=50k, C=20)"
    if ds_name.startswith("D5"): return "D5 Series: Small Testing (N=5k)"
    return "Other"

# Group datasets by series
series_data = defaultdict(list)
for (ds, ratio) in data.keys():
    series = get_series(ds)
    if (ds, ratio) not in series_data[series]:
        series_data[series].append((ds, ratio))

# Sort keys
for s in series_data:
    series_data[s].sort()

with open(output_md, 'w') as f:
    f.write("# TriBack-Clo Multi-Itemset Benchmark Results\n\n")
    f.write(f"*Source: {latest_csv}*\n\n")
    
    # Order of series
    ordered_series = [
        "D10 Series: Density Sweep (N=10k, T=20)",
        "D20 Series: Long Sequences (N=20k, T=2.5)",
        "D50 Series: Transaction Length Sweep (N=50k, C=20)",
        "D5 Series: Small Testing (N=5k)"
    ]
    
    for series_name in ordered_series:
        if series_name not in series_data: continue
        
        f.write(f"## {series_name}\n\n")
        
        datasets_in_series = series_data[series_name]
        
        for (ds, ratio) in datasets_in_series:
            pct = float(ratio) * 100
            f.write(f"### Dataset: {ds} (Support: {pct:g}%)\n\n")
            
            f.write("| Algorithm | Mining (s) | Wall (s) | Patterns | Memory (MB) | Status |\n")
            f.write("|-----------|------------|----------|----------|-------------|--------|\n")
            
            # Row for each algo in order
            for algo in algo_order:
                row = data[(ds, ratio)].get(algo)
                
                name = algo_names.get(algo, algo)
                
                if not row:
                    f.write(f"| {name} | - | - | - | - | MISSING |\n")
                    continue
                
                status = row['status']
                if status == "OK":
                    mining = float(row['mining_sec'])
                    wall = float(row['wall_sec'])
                    pats = int(row['patterns'])
                    mem_kb = int(row['maxrss_kb'])
                    mem_mb = mem_kb // 1024
                    
                    # Highlight best mining time (simple heuristic: if TriBack is fastest)
                    # For now just standard formatting with bold for TriBack cells
                    
                    mining_str = f"{mining:.3f}"
                    wall_str = f"{wall:.3f}"
                    
                    if algo == "TriBack-Clo-Java":
                        mining_str = f"**{mining_str}**"
                    
                    f.write(f"| {name} | {mining_str} | {wall_str} | {pats:,} | {mem_mb:,} | {status} |\n")
                else:
                    f.write(f"| {name} | - | - | - | - | **{status}** |\n")
            
            f.write("\n")

print(f"Report generated: {output_md}")
