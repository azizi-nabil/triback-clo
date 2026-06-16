#!/usr/bin/env python3
import csv
import statistics
import argparse
from collections import defaultdict

INPUT = "results/raw_run_extract.csv"
OUTPUT = "results/run_variation_summary.csv"
LATEX_OUTPUT = "results/variation_table.tex"

def compute_range_pct(values):
    if not values: return 0.0
    med = statistics.median(values)
    if med == 0: return 0.0
    return (max(values) - min(values)) / med * 100.0

def latex_escape(s):
    return str(s).replace("%", "\\%").replace("_", "\\_")

def main():
    data = []
    try:
        with open(INPUT, "r") as f:
            data = list(csv.DictReader(f))
    except FileNotFoundError:
        print(f"Error: {INPUT} not found. Run extract_run_level.py first.")
        return

    # 1. Group all raw runs by (campaign_id, dataset, minsup, algorithm, group_id)
    raw_groups = defaultdict(list)
    for row in data:
        if row["run_type"] == "measured":
            group_id = row.get("group") or row.get("expected_output_equivalent_group")
            key = (row["campaign_id"], row["dataset"], row["minsup"], row["algorithm"], group_id)
            raw_groups[key].append(row)

    # 2. Compute stats for EVERY campaign/algo combination
    all_campaign_summaries = []
    for key, runs in raw_groups.items():
        campaign_id, dataset, minsup, algo, group_id = key
        
        ok_runs = [r for r in runs if r["status"] == "OK"]
        n_measured = len(runs)
        n_ok = len(ok_runs)
        
        patterns = [int(r["patterns"]) for r in ok_runs if r["patterns"] and int(r["patterns"]) != 0]
        wall_times = [float(r["wall_s"]) for r in ok_runs if r["wall_s"]]
        mem_vals = [float(r["external_mem_mb"]) for r in ok_runs if r["external_mem_mb"]]
        
        count_consistent = len(set(patterns)) == 1 if patterns else False
        avg_patterns = patterns[0] if patterns else 0
        
        n_timeout = sum(1 for r in runs if r["status"] == "TIMEOUT")
        n_oom = sum(1 for r in runs if r["status"] == "OOM")
        n_failed = sum(1 for r in runs if r["status"] == "FAILED")
        
        status_summary = f"{n_ok}/{n_measured} OK"
        if n_timeout: status_summary += f", {n_timeout} TIMEOUT"
        if n_oom: status_summary += f", {n_oom} OOM"
        if n_failed: status_summary += f", {n_failed} FAILED"

        summary = {
            "campaign_id": campaign_id,
            "dataset": dataset,
            "minsup": minsup,
            "algorithm": algo,
            "group": group_id,
            "n_measured": n_measured,
            "n_ok": n_ok,
            "status_summary": status_summary,
            "patterns": avg_patterns,
            "count_consistent": count_consistent,
            "wall_min_s": min(wall_times) if wall_times else None,
            "wall_median_s": statistics.median(wall_times) if wall_times else None,
            "wall_max_s": max(wall_times) if wall_times else None,
            "wall_range_pct": compute_range_pct(wall_times) if wall_times else None,
            "mem_min_mb": min(mem_vals) if mem_vals else None,
            "mem_median_mb": statistics.median(mem_vals) if mem_vals else None,
            "mem_max_mb": max(mem_vals) if mem_vals else None,
            "mem_range_pct": compute_range_pct(mem_vals) if mem_vals else None,
        }
        all_campaign_summaries.append(summary)

    # 3. Selection Logic: Pick the "Best" campaign for each (dataset, minsup, algorithm)
    best_campaigns = {}
    for s in all_campaign_summaries:
        key = (s["dataset"], s["minsup"], s["algorithm"])
        if key not in best_campaigns:
            best_campaigns[key] = s
            continue
        current_best = best_campaigns[key]
        def score(summary):
            if summary["n_ok"] == 3 and summary["n_measured"] == 3: return 100
            if summary["n_ok"] >= 3: return 80
            return summary["n_ok"]
        if score(s) > score(current_best):
            best_campaigns[key] = s
        elif score(s) == score(current_best):
            if s["campaign_id"] > current_best["campaign_id"]:
                best_campaigns[key] = s

    # 4. Final aggregation
    final_rows = []
    group_pattern_counts = defaultdict(set)
    for s in best_campaigns.values():
        if s["count_consistent"] and s["patterns"] > 0:
            group_pattern_counts[s["group"]].add(s["patterns"])

    for s in best_campaigns.values():
        counts_in_group = group_pattern_counts[s["group"]]
        s["output_equivalent"] = len(counts_in_group) == 1 if counts_in_group else False
        
        s["comparison_eligible"] = (
            s["output_equivalent"] and 
            s["count_consistent"] and 
            s["n_ok"] == 3 and 
            s["n_measured"] == 3 and
            s["patterns"] > 0 and
            s["wall_min_s"] is not None and
            s["mem_min_mb"] is not None
        )
        final_rows.append(s)

    final_rows.sort(key=lambda x: (x["dataset"], x["minsup"], x["algorithm"]))

    # Write CSV
    fieldnames = [
        "campaign_id", "dataset", "minsup", "algorithm", "group", "n_measured", "n_ok", "status_summary",
        "patterns", "count_consistent", "output_equivalent", "comparison_eligible",
        "wall_min_s", "wall_median_s", "wall_max_s", "wall_range_pct",
        "mem_min_mb", "mem_median_mb", "mem_max_mb", "mem_range_pct"
    ]
    with open(OUTPUT, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in final_rows:
            writer.writerow({k: (r[k] if r.get(k) is not None else "") for k in fieldnames})
    
    print(f"Summarized {len(final_rows)} configurations.")
    generate_latex(final_rows)

def generate_latex(rows):
    # Precise reordering: Real datasets first, then synthetic
    target_order = [
        ("Kosarak", "0.1%"),
        ("SIGN", "1%"),
        ("MSNBC", "0.05%"),
        ("D10C60", "40%"),
        ("D10C70", "40%"),
        ("D50T40", "40%")
    ]
    
    # Filter and sort rows according to target_order
    filtered_rows = []
    for t_ds, t_sup in target_order:
        matches = [r for r in rows if r["dataset"] == t_ds and r["minsup"] == t_sup and r["comparison_eligible"] and r["algorithm"] != "CloFast"]
        matches.sort(key=lambda x: x["algorithm"])
        filtered_rows.extend(matches)

    with open(LATEX_OUTPUT, "w") as f:
        f.write("% Auto-generated Variation Table (Final Supplement Version)\n")
        f.write("\\begin{table*}[t]\n\\centering\n\\footnotesize\n\\setlength{\\tabcolsep}{3pt}\n")
        f.write("\\caption{Run-to-run variation for representative output-equivalent benchmark configurations. Values report min/median/max over three measured runs; warm-up runs are excluded. Only configurations with three completed measured runs and matching pattern counts are included. TIMEOUT, OOM, and failed runs are treated as censored outcomes and are excluded from formal variance/statistical summaries. Runtime and memory comparisons are reported only for output-equivalent configurations.}\n")
        f.write("\\label{tab:run-variation}\n")
        f.write("\\begin{tabular}{lllc r r r c c}\n\\hline\n")
        f.write("Dataset & Support & Algorithm & Status & Patterns & Wall min/med/max (s) & MaxRSS min/med/max (MB) & Range$_W$ & Range$_M$ \\\\\n\\hline\n")
        
        last_dataset = ""
        for r in filtered_rows:
            ds_disp = r["dataset"] if r["dataset"] != last_dataset else ""
            last_dataset = r["dataset"]
            
            dataset = latex_escape(ds_disp)
            support = latex_escape(r["minsup"])
            algo = latex_escape(r["algorithm"])
            status = latex_escape(r["status_summary"])
            
            p_val = f"{r['patterns']:,}"
            wall_str = f"{r['wall_min_s']:.2f}/{r['wall_median_s']:.2f}/{r['wall_max_s']:.2f}"
            mem_str = f"{r['mem_min_mb']:.0f}/{r['mem_median_mb']:.0f}/{r['mem_max_mb']:.0f}"
            
            range_w = f"{r['wall_range_pct']:.1f}\\%"
            range_m = f"{r['mem_range_pct']:.1f}\\%"
            
            f.write(f"{dataset} & {support} & {algo} & {status} & {p_val} & {wall_str} & {mem_str} & {range_w} & {range_m} \\\\\n")
            
        f.write("\\hline\n\\end{tabular}\n")
        f.write("\\smallskip\n\\emph{Note.} Range$_W$ and Range$_M$ denote $(\\max-\\min)/\\mathrm{median}\\times100$ for wall time and MaxRSS, respectively. They are descriptive run-to-run ranges, not statistical variance estimates.\n")
        f.write("\\end{table*}\n")
    print(f"Wrote LaTeX table to {LATEX_OUTPUT}")

if __name__ == "__main__":
    main()
