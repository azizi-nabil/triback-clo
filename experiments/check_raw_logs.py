import os
import re
import glob

def parse_log(filepath):
    wall_time = None
    mining_time = None
    patterns = None
    rss = None
    status = "OK"
    
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        
        if "TIMEOUT" in content or "Timed out" in content:
            status = "TIMEOUT"
            return wall_time, mining_time, patterns, rss, status
        if "Exception" in content and "OutOfMemoryError" in content:
            status = "OOM"
            return wall_time, mining_time, patterns, rss, status
            
        # TriBack-Clo-Java / Scala
        m_mining = re.search(r"Total time \~ (\d+) ms", content)
        if m_mining: mining_time = int(m_mining.group(1)) / 1000.0
        
        m_pat = re.search(r"Pattern count : (\d+)", content)
        if not m_pat: m_pat = re.search(r"Frequent sequences count : (\d+)", content)
        if m_pat: patterns = int(m_pat.group(1))
            
        m_wall = re.search(r"Wall time:\s*([\d.]+)\s*sec", content)
        if m_wall: wall_time = float(m_wall.group(1))
            
        m_rss = re.search(r"MaxRSS:\s*(\d+)\s*KB", content)
        if m_rss: rss = int(m_rss.group(1))
        
        # fallback for algorithms without standard wall time output
        if wall_time is None and mining_time is not None:
            # Some logs might not have exact wall time wrapper
            wall_time = mining_time
            
    return wall_time, mining_time, patterns, rss, status

def get_logs_data(logs_dir):
    results = {}
    files = glob.glob(os.path.join(logs_dir, "*.log"))
    for f in files:
        base = os.path.basename(f)
        # Expected format: Algo_Dataset_Ratio_runX_timestamp.log
        # or similar
        # e.g. TriBack-Clo-Java_D10C80_0.4_run1_20260112_221617.log
        # or TriBack-Clo_FIFA_0.1_run1_...
        
        m = re.match(r"^([^_]+(?:-[^_]+)?(?:-Java)?|BIDE\+)_([^_]+)_([\d.]+)_run(warmup|\d+)", base)
        if not m:
            continue
        algo = m.group(1)
        ds = m.group(2)
        ratio = m.group(3)
        run = m.group(4)
        
        sup = round(float(ratio) * 100, 4)
        
        parsed = parse_log(f)
        key = (ds, sup, algo)
        if key not in results: results[key] = {}
        results[key][run] = parsed
        
    return results

def main():
    import json
    data_itemsets = get_logs_data("/home/icosi/habilitation-project/TriBack-Clo/experiments/logs_itemsets")
    data_single = get_logs_data("/home/icosi/habilitation-project/TriBack-Clo/experiments/logs")
    
    # Merge
    all_data = {**data_single, **data_itemsets}
    
    # Check if they have warmup + 3 runs
    complete = 0
    incomplete = 0
    
    for k, runs in all_data.items():
        if "warmup" in runs and "1" in runs and "2" in runs and "3" in runs:
            complete += 1
        else:
            incomplete += 1
            # print(f"Incomplete {k}: {list(runs.keys())}")
            
    print(f"Total configurations with completely formed logs (warmup+3 runs): {complete}")
    print(f"Configurations missing some runs: {incomplete}")

if __name__ == '__main__':
    main()
