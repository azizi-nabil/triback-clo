
import csv
import os
import sys

# Define input files (newest first to prioritize latest runs)
CSV_FILES = [
    "experiments/results/benchmark_20260119_105918.csv", # Kosarak, BMS2, FIFA
    "experiments/results/benchmark_20260118_211632.csv", # BIKE, SIGN, MSNBC
    "experiments/results/benchmark_20260118_170953.csv", # Partial BIKE
]

OUTPUT_FILE = "experiments/results/clofast_summary.md"

def load_data():
    data = {} # (dataset, ratio) -> row_dict
    
    for csv_file in CSV_FILES:
        if not os.path.exists(csv_file):
            continue
            
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row['algorithm'] != "CloFast":
                    continue
                
                key = (row['dataset'], row['ratio'])
                if key not in data:
                    data[key] = row
    return data

def format_time(seconds):
    try:
        s = float(seconds)
        if s >= 7200:
            return "TIMEOUT"
        return f"{s:.3f}"
    except:
        return "TIMEOUT"

def format_mem(kb):
    try:
        kb = float(kb)
        mb = kb / 1024
        if mb > 1000:
            return f"{mb/1024:.2f} GB"
        return f"{mb:.0f} MB"
    except:
        return "-"

def main():
    data = load_data()
    
    # Datasets to report
    datasets = ["BIKE", "SIGN", "MSNBC", "MSNBC_small", "Kosarak", "Kosarak25k", "BMS2", "FIFA"]
    
    with open(OUTPUT_FILE, 'w') as out:
        out.write("# CloFast Single-Itemset Results\n\n")
        
        for dataset in datasets:
            out.write(f"## {dataset}\n\n")
            out.write("| Ratio | Support % | Wall Time (s) | Memory |\n")
            out.write("|---|---|---|---|\n")
            
            # Find rows for this dataset
            rows = []
            for (ds, r), row in data.items():
                if ds == dataset:
                    rows.append(row)
            
            # Sort by ratio descending (0.1 -> 0.01)
            rows.sort(key=lambda x: float(x['ratio']), reverse=True)
            
            for row in rows:
                wall = format_time(row['wall_sec'])
                mem = format_mem(row['maxrss_kb'])
                pct = float(row['minsup_pct'])
                
                # Format percentage nicely
                if pct < 0.1:
                    pct_str = f"{pct:.4f}%"
                else:
                    pct_str = f"{pct:.2f}%"
                    
                out.write(f"| {row['ratio']} | {pct_str} | {wall} | {mem} |\n")
            out.write("\n")

if __name__ == "__main__":
    main()
