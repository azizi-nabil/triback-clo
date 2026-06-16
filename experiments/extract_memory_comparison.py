#!/usr/bin/env python3
import os
import re
import csv
import sys

# Paths
LOGS_DIR = "experiments/logs"
OUTPUT_FILE = "experiments/results/memory_comparison.csv"

# Regex for Internal Memory (SPMF format)
# "Max memory (mb) : 2350.85" or "Max memory (mb) : 22269"
REGEX_INTERNAL = re.compile(r"Max memory \(mb\) : ?([\d\.]+)")

# Regex for External Memory (MaxRSS from time command)
# "MaxRSS: 37999748 KB"
REGEX_EXTERNAL = re.compile(r"MaxRSS: ([0-9]+)")

def parse_log_file(filepath):
    """Extracts internal (MB) and external (KB -> MB) memory from log."""
    internal_mb = 0.0
    external_mb = 0.0
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            # Find Internal
            match_int = REGEX_INTERNAL.search(content)
            if match_int:
                internal_mb = float(match_int.group(1))
            
            # Find External
            match_ext = REGEX_EXTERNAL.search(content)
            if match_ext:
                kb = float(match_ext.group(1))
                external_mb = kb / 1024.0  # Convert KB to MB
                
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        return None

    return internal_mb, external_mb

def main():
    if not os.path.exists(LOGS_DIR):
        print(f"Directory {LOGS_DIR} not found.")
        return

    results = []
    
    print(f"Scanning logs in {LOGS_DIR}...")
    
    for filename in os.listdir(LOGS_DIR):
        if not filename.endswith(".log"):
            continue
            
        # Parse filename to get metadata
        # Format: Algorithm_Dataset_Ratio_runX_Timestamp.log
        # e.g., CloFast_Kosarak25k_0.002_run1_20260118.log
        # BUT: MSNBC_small has underscore in name!
        # Strategy: Split from the end to get known parts first
        base = filename.replace('.log', '')
        parts = base.split('_')
        
        # Last part is timestamp, second-to-last is runX
        if len(parts) < 5:
            continue
        
        # Find "runX" part (could be run1, run2, run3, runwarmup1)
        run_idx = -1
        for i, p in enumerate(parts):
            if p.startswith('run'):
                run_idx = i
                break
        
        if run_idx < 3:
            continue
            
        algo = parts[0]
        run_id = parts[run_idx]
        
        # Ratio is the part before runX
        try:
            ratio = parts[run_idx - 1]
            float(ratio)  # validate it's a number
        except (IndexError, ValueError):
            continue
        
        # Dataset is everything between algo and ratio
        dataset = '_'.join(parts[1:run_idx-1])
        
        # Skip warmups, only keep measured runs (run1, run2, run3)
        if "warmup" in run_id:
            continue
            
        filepath = os.path.join(LOGS_DIR, filename)
        mem_data = parse_log_file(filepath)
        
        if mem_data:
            internal, external = mem_data
            if internal > 0 and external > 0:
                results.append({
                    "Algorithm": algo,
                    "Dataset": dataset,
                    "Ratio": ratio,
                    "Run": run_id,
                    "Internal_MB": round(internal, 2),
                    "External_MB": round(external, 2),
                    "Gap_Factor": round(external / internal, 2) if internal > 0 else 0
                })

    # Sort results
    results.sort(key=lambda x: (x['Dataset'], x['Ratio'], x['Algorithm']))

    # Write to CSV
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    with open(OUTPUT_FILE, 'w', newline='') as f:
        fieldnames = ["Dataset", "Ratio", "Algorithm", "Run", "Internal_MB", "External_MB", "Gap_Factor"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"\nDone. Extracted {len(results)} valid memory comparisons.")
    print(f"Results saved to: {OUTPUT_FILE}")
    
    # Print preview
    print("\nPreview (top 15):")
    print(f"{'Dataset':<15} {'Ratio':<8} {'Algorithm':<12} {'Internal(MB)':<12} {'External(MB)':<12} {'Gap'}")
    print("-" * 70)
    for r in results[:15]:
        print(f"{r['Dataset']:<15} {r['Ratio']:<8} {r['Algorithm']:<12} {r['Internal_MB']:<12} {r['External_MB']:<12} {r['Gap_Factor']}x")

if __name__ == "__main__":
    main()
