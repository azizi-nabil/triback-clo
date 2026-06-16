#!/usr/bin/env python3
import csv
import re
from pathlib import Path

MANIFEST = Path("results/configuration_manifest.csv")
OUTPUT = Path("results/raw_run_extract.csv")

def parse_memory_to_mb(value, unit):
    if value is None: return None
    value = float(value)
    unit = unit.upper()
    if unit == "GB": return value * 1024
    if unit == "MB": return value
    if unit == "KB": return value / 1024
    return value

def extract_metrics(text):
    # Normalize Algorithm Name if found in text or implied
    # (Some logs use TriBack-Clo-Java, we want TriBack-Clo)
    
    # Status detection (Priority: TIMEOUT > OOM > FAILED > OK)
    status = "OK"
    if re.search(r"TIMEOUT|timed out|timeout", text, re.I):
        status = "TIMEOUT"
    elif re.search(r"OutOfMemory|OOM|out of memory", text, re.I):
        status = "OOM"
    elif re.search(r"FAILED|ERROR|Command terminated|exited with|exception|error", text, re.I):
        # Only set FAILED if not already TIMEOUT/OOM
        if status == "OK": status = "FAILED"

    patterns = None
    mining_s = None
    wall_s = None
    external_mem_mb = None
    
    # Internal Mining Time (Total time ~ XXX ms)
    m = re.search(r"Total time ~\s*([\d,]+)\s*ms", text, re.I)
    if m:
        mining_s = float(m.group(1).replace(",", "")) / 1000.0

    # Resource Info from shell script (handles potential line mangling)
    # [RESOURCE] Wall time: 1.63 sec | CPU: 149% | MaxRSS: 532196 KB
    resource_text = text.replace("\n", " ") # Flatten for easier regex
    m = re.search(r"Wall time:\s*([\d.]+)\s*sec", resource_text, re.I)
    if m:
        wall_s = float(m.group(1))
        
    # Fallbacks for older logs missing [RESOURCE] block
    if wall_s is None and mining_s is not None:
        wall_s = mining_s
        
    m = re.search(r"MaxRSS:\s*([\d.]+)\s*KB", resource_text, re.I)
    if m:
        external_mem_mb = parse_memory_to_mb(m.group(1), "KB")

    m = re.search(r"Max memory \(mb\)\s*[:=]\s*([\d.]+)", text, re.I)
    if external_mem_mb is None and m:
        external_mem_mb = float(m.group(1))

    # Patterns
    m = re.search(r"patterns?\s*count\s*[:=]\s*([\d,]+)", text, re.I)
    if m:
        patterns = int(m.group(1).replace(",", ""))
    else:
        m = re.search(r"sequences\s*count\s*[:=]\s*([\d,]+)", text, re.I)
        if m:
            patterns = int(m.group(1).replace(",", ""))

    return {
        "status": status,
        "patterns": patterns,
        "mining_s": mining_s,
        "wall_s": wall_s,
        "external_mem_mb": external_mem_mb,
    }

def main():
    if not MANIFEST.exists():
        print(f"Error: {MANIFEST} not found. Run the benchmark first.")
        return

    rows = []
    with MANIFEST.open("r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            log_path = Path(row["log_path"])
            if not log_path.exists():
                print(f"Warning: Log file {log_path} not found. Skipping.")
                continue
            
            text = log_path.read_text(errors="ignore")
            metrics = extract_metrics(text)
            
            algo = row["algorithm"]
            if "TriBack-Clo" in algo: algo = "TriBack-Clo"
            
            rows.append({
                "dataset": row["dataset"],
                "minsup": row["minsup"],
                "algorithm": algo,
                "run_type": row["run_type"],
                "run_id": row["run_id"],
                "campaign_id": row.get("campaign_id", "legacy"),
                "group": row["expected_output_equivalent_group"],
                "status": metrics["status"],
                "patterns": metrics["patterns"],
                "mining_s": metrics["mining_s"],
                "wall_s": metrics["wall_s"],
                "external_mem_mb": metrics["external_mem_mb"],
                "log_path": str(log_path)
            })

    with OUTPUT.open("w", newline="") as f:
        fieldnames = [
            "dataset", "minsup", "algorithm", "run_type", "run_id", "campaign_id", "group",
            "status", "patterns", "mining_s", "wall_s", "external_mem_mb", "log_path"
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    
    print(f"Wrote {len(rows)} runs to {OUTPUT}")

if __name__ == "__main__":
    main()
