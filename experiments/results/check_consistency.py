import csv
import glob
import re
import math
import os

def parse_md_table(filepath):
    data = []
    current_dataset = None
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            # Dataset header
            m = re.match(r'^##\s+([A-Za-z0-9_\.]+)', line)
            if m:
                header_text = m.group(1)
                if "Dataset" in line:
                    current_dataset = header_text
            
            # For ITEMSETS: "### Dataset: D10C20 (Support: 40%)"
            m = re.match(r'^### Dataset:\s*([A-Za-z0-9_\.]+)', line)
            if m:
                current_dataset = m.group(1)

            if line.startswith('|') and 'Algorithm' not in line and '---' not in line:
                cols = [c.strip() for c in line.split('|')]
                if len(cols) >= 8:
                    sup_str = cols[1].replace('%', '')
                    algo = cols[2].replace('**', '')
                    mining_str = cols[3].replace('**', '')
                    wall_str = cols[4]
                    pat_str = cols[5].replace(',', '')
                    
                    try:
                        sup = float(sup_str)
                    except:
                        continue 
                        
                    status = cols[-2] if cols[-2] != '—' and cols[-2] != '' and not cols[-2].startswith('<') else cols[-1]
                    if len(cols) >= 10: status = cols[9]
                    else: status = cols[8] if len(cols) > 8 else "OK"
                    
                    data.append({
                        'dataset': current_dataset,
                        'support': sup,
                        'algo': algo,
                        'mining': mining_str,
                        'wall': wall_str,
                        'patterns': pat_str,
                        'status': status
                    })
    return data

def main():
    md1 = "/home/icosi/habilitation-project/TriBack-Clo/experiments/results/BENCHMARK_RESULTS.md"
    md2 = "/home/icosi/habilitation-project/TriBack-Clo/experiments/results/BENCHMARK_RESULTS_ITEMSETS.md"
    
    md_data1 = parse_md_table(md1)
    md_data2 = parse_md_table(md2)
    md_data = md_data1 + md_data2
    
    csv_files = glob.glob("/home/icosi/habilitation-project/TriBack-Clo/experiments/results/*.csv")
    
    csv_rows = []
    for cf in csv_files:
        with open(cf, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                ds = row.get('dataset') or row.get('Dataset')
                ratio = row.get('ratio') or row.get('Ratio')
                if not ds or not ratio: continue
                try:
                    sup = round(float(ratio) * 100, 4)
                except: continue
                
                algo = row.get('algorithm') or row.get('Algorithm')
                csv_rows.append({
                    'dataset': ds,
                    'support': sup,
                    'algo': algo,
                    'row': row,
                    'file': os.path.basename(cf)
                })

    mismatches = 0
    checks = 0

    for m in md_data:
        if m['status'] != 'OK': continue
        if m['mining'] == '—': continue
        ds = m['dataset']
        algo = m['algo']
        sup = m['support']
        
        matches = [c for c in csv_rows if c['dataset'] == ds and c['algo'] == algo and abs(c['support'] - sup) < 1e-4]
        
        found_match = False
        options_printed = []
        for c in matches:
            row = c['row']
            c_mining = row.get('mining_sec') or row.get('mining_sec_mean')
            c_wall = row.get('wall_sec') or row.get('wall_sec_mean')
            c_pats = row.get('patterns')
            
            if not c_mining: continue
            options_printed.append({'file': c['file'], 'm': c_mining, 'w': c_wall, 'p': c_pats})
            
            try: c_mining_f = f"{float(c_mining):.3f}"
            except: c_mining_f = str(c_mining)
            
            md_mining_f = m['mining']
            if "." in md_mining_f: md_mining_f = f"{float(md_mining_f):.3f}"
            
            if c_mining_f == md_mining_f and c_pats == m['patterns']:
                found_match = True
                break
                
        if not found_match and len(matches) > 0:
            print(f"Mismatch: {ds} {sup}% {algo}")
            print(f"MD: mining={m['mining']}, wall={m['wall']}, patterns={m['patterns']}")
            print(f"CSV options: {options_printed}")
            mismatches += 1
        elif len(matches) == 0:
            print(f"Missing in CSV: {ds} {sup}% {algo}")
            mismatches += 1
        else:
            checks += 1
            
    print(f"Checked {checks} OK entries. Mismatches/missing: {mismatches}")

if __name__ == "__main__":
    main()
