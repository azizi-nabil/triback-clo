#!/usr/bin/env python3
import csv
import re
from pathlib import Path

# Scan all directories starting with logs
LOG_DIRS = list(Path(".").glob("logs*"))
MANIFEST = Path("results/configuration_manifest.csv")

def main():
    if not LOG_DIRS:
        print(f"Error: No log directories found.")
        return

    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    
    rows = []
    # Pattern: Algorithm_Dataset_Ratio_runID_Timestamp.log
    
    for log_dir in LOG_DIRS:
        if not log_dir.is_dir(): continue
        
        for log_file in log_dir.glob("*.log"):
            name = log_file.stem
            parts = name.split("_")
            
            run_idx = -1
            for i, p in enumerate(parts):
                if p.startswith("run"):
                    run_idx = i
                    break
            
            if run_idx < 2: continue
            
            algo = parts[0]
            ratio = parts[run_idx - 1]
            dataset = "_".join(parts[1:run_idx - 1])
            run_id_str = parts[run_idx]
            
            # Campaign ID is the timestamp part after runID
            campaign_id = "_".join(parts[run_idx + 1:]) if len(parts) > run_idx + 1 else "legacy"
            
            run_type = "warmup" if "warmup" in run_id_str else "measured"
            clean_id = run_id_str.replace("warmup", "").replace("run", "")
            
            try:
                minsup_pct = f"{float(ratio) * 100:g}%"
            except ValueError:
                minsup_pct = f"{ratio}%"

            group_id = f"{dataset}_{ratio}_group"
            
            rows.append({
                "dataset": dataset,
                "minsup": minsup_pct,
                "algorithm": algo,
                "run_type": run_type,
                "run_id": clean_id,
                "campaign_id": campaign_id,
                "expected_output_equivalent_group": group_id,
                "log_path": str(log_file)
            })

    # Sort by campaign (newest first roughly) then others
    rows.sort(key=lambda x: (x["campaign_id"], x["dataset"], x["minsup"], x["algorithm"], x["run_type"], x["run_id"]), reverse=True)

    with MANIFEST.open("w", newline="") as f:
        fieldnames = ["dataset", "minsup", "algorithm", "run_type", "run_id", "campaign_id", "expected_output_equivalent_group", "log_path"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    
    print(f"Reconstructed manifest with {len(rows)} entries from {len(LOG_DIRS)} directories in {MANIFEST}")

if __name__ == "__main__":
    main()
