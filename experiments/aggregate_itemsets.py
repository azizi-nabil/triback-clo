import os
import re

logs_dir = "experiments/logs_itemsets"
algorithms = ["TriBack-Clo-Java", "BIDE+", "CloFast", "ClaSP", "CloSpan"]

def parse_log(filepath):
    wall_time = 0
    mining_time = 0
    patterns = -1 # Use -1 to indicate not found
    rss = 0
    status = "OK"
    
    if not os.path.exists(filepath):
        return None

    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        
        if "TIMEOUT" in content or "Timed out" in content:
            status = "TIMEOUT"
        
        mining_match = re.search(r"Total time ~ (\d+) ms", content)
        if mining_match:
            mining_time = int(mining_match.group(1)) / 1000.0
            
        patterns_match = re.search(r"Pattern count : (\d+)", content)
        if not patterns_match:
            patterns_match = re.search(r"Frequent sequences count : (\d+)", content)
            
        if patterns_match:
            patterns = int(patterns_match.group(1))
            
        wall_match = re.search(r"Wall time: ([\d.]+) sec", content)
        if wall_match:
            wall_time = float(wall_match.group(1))
            
        rss_match = re.search(r"MaxRSS: (\d+) KB", content)
        if rss_match:
            rss = int(rss_match.group(1))
            
    return wall_time, mining_time, patterns, rss, status

results = {}

files = sorted(os.listdir(logs_dir))
for f in files:
    if "runwarmup" in f: continue
    
    # TriBack-Clo-Java_D10C80_0.4_run1_20260112_221617.log
    # BIDE+_D10C80_0.4_run1_20260112_221617.log
    # CloFast_D10C80_0.4_run1_20260112_221617.log
    
    match = re.match(r"^([^_]+(?:-[^_]+)?(?:-Java)?|BIDE\+)_([^_]+)_([\d.]+)_run(\d+)_", f)
    if not match: continue
    
    algo = match.group(1)
    dataset = match.group(2)
    ratio = match.group(3)
    run = match.group(4)
    
    key = (dataset, ratio, algo)
    if key not in results:
        results[key] = []
        
    res = parse_log(os.path.join(logs_dir, f))
    if res:
        results[key].append(res)

# Group by (dataset, ratio)
configs = {}
for (ds, r, algo), vals in results.items():
    if (ds, r) not in configs:
        configs[(ds, r)] = {}
    configs[(ds, r)][algo] = vals

print("# Multi-Itemset Benchmark Results Summary\n")

for (ds, r) in sorted(configs.keys()):
    print(f"## Dataset: {ds} | Support: {float(r)*100}%")
    print("| Algorithm | Mining (s) | Wall (s) | Patterns | Memory (MB) | Status |")
    print("|-----------|------------|----------|----------|-------------|--------|")
    
    for algo in algorithms:
        if algo not in configs[(ds, r)]:
            # print(f"| {algo} | - | - | - | - | MISSING |")
            continue
            
        vals = configs[(ds, r)][algo]
        
        # Filter successful runs
        success_runs = [v for v in vals if v[4] == "OK" and v[2] != -1]
        
        if not success_runs:
            # Check for timeout in any run
            if any(v[4] == "TIMEOUT" for v in vals):
                print(f"| {algo} | >TIMEOUT | - | - | - | TIMEOUT |")
            else:
                print(f"| {algo} | - | - | - | - | ERROR |")
            continue
            
        avg_mining = sum(v[1] for v in success_runs) / len(success_runs)
        avg_wall = sum(v[0] for v in success_runs) / len(success_runs)
        avg_patterns = int(sum(v[2] for v in success_runs) / len(success_runs))
        avg_mem = int(sum(v[3] for v in success_runs) / (len(success_runs) * 1024))
        
        print(f"| {algo} | {avg_mining:.3f} | {avg_wall:.1f} | {avg_patterns:,} | {avg_mem} | OK |")
    print("\n")
