#!/usr/bin/env python3
"""
TriBack-Clo Experimentation Framework
=====================================

This script automates rigorous benchmarking across multiple datasets and algorithms.

Experiments:
A. Performance Cliff (Runtime vs Support)
B. Memory Efficiency
C. Scalability (Data Size)
D. Legacy minimal ablation stub

Usage:
    python run_experiments.py --experiment A
    python run_experiments.py --experiment all
"""

import os
import subprocess
import time
import json
import argparse
from datetime import datetime
from pathlib import Path

# ============================================================
# CONFIGURATION
# ============================================================

BASE_DIR = Path(__file__).parent
DATASETS_DIR = BASE_DIR / "datasets"
LOGS_DIR = BASE_DIR / "logs"
RESULTS_DIR = BASE_DIR / "results"

TRIBACK_JAR = BASE_DIR.parent / "triback-clo-java" / "triback-clo.jar"
SPMF_JAR = BASE_DIR / "spmf.jar"

# JVM Settings
JVM_HEAP = "50g"
TIMEOUT_SEC = 1800  # 30 minutes

# Dataset Configurations (log-spaced grids from experimentation plan)
DATASETS = {
    # Flagship - deep sweep
    "Kosarak": {
        "file": "kosarak_sequences.txt",
        "ratios": [0.02, 0.01, 0.005, 0.0025, 0.001, 0.0005, 0.0002, 0.0001],
        "type": "sparse",
        "description": "Volume Stress Test - 990K sequences"
    },
    # Low minsup stress test
    "Kosarak25k": {
        "file": "kosarak25k.txt",
        "ratios": [0.01, 0.005, 0.0025, 0.002, 0.001, 0.0005, 0.0002],
        "type": "sparse",
        "description": "Low-Minsup Stress Test - 25K sequences"
    },
    # Mid-scale clickstream
    "BMS2": {
        "file": "BMS2.txt",
        "ratios": [0.05, 0.02, 0.01, 0.005, 0.0025, 0.001, 0.0005],
        "type": "sparse",
        "description": "BMSWebView2 - 77K clickstreams"
    },
    # Dense, longer sequences
    "FIFA": {
        "file": "FIFA.txt",
        "ratios": [0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001],
        "type": "medium",
        "description": "Length Stress Test - Avg 36.2 items"
    },
    # Similar to FIFA
    "BIKE": {
        "file": "BIKE.txt",
        "ratios": [0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001],
        "type": "medium",
        "description": "Dense sequences - 21K rides"
    },
    # Small dataset (overhead test)
    "SIGN": {
        "file": "SIGN.txt",
        "ratios": [0.3, 0.2, 0.15, 0.1, 0.05, 0.02, 0.01],
        "type": "small",
        "description": "Overhead Test - 800 sequences"
    },
    # Large clickstream
    "MSNBC": {
        "file": "MSNBC_SPMF.txt",
        "ratios": [0.05, 0.02, 0.01, 0.005, 0.0025, 0.001, 0.0005],
        "type": "sparse",
        "description": "Large Clickstream - 990K pageviews"
    }
}

# Algorithms to compare
ALGORITHMS = {
    "TriBack-Clo": "triback",
    "BIDE+": "BIDE+",
    "ClaSP": "ClaSP",
    "CloSpan": "CloSpan"
}

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

def get_timestamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")

def ensure_dirs():
    LOGS_DIR.mkdir(exist_ok=True)
    RESULTS_DIR.mkdir(exist_ok=True)

def log_result(experiment, dataset, algorithm, ratio, runtime, patterns, memory=None, notes=""):
    result = {
        "timestamp": get_timestamp(),
        "experiment": experiment,
        "dataset": dataset,
        "algorithm": algorithm,
        "ratio": ratio,
        "minsup_pct": f"{ratio * 100:.3f}%",
        "runtime_sec": runtime,
        "patterns": patterns,
        "memory_mb": memory,
        "notes": notes
    }
    
    # Append to results file
    results_file = RESULTS_DIR / f"experiment_{experiment}.jsonl"
    with open(results_file, "a") as f:
        f.write(json.dumps(result) + "\n")
    
    return result

# ============================================================
# ALGORITHM RUNNERS
# ============================================================

def run_triback(dataset_file, ratio, timeout=TIMEOUT_SEC, ablation_no_prune=False):
    """Run TriBack-Clo and return (runtime, patterns, memory)"""
    
    if not TRIBACK_JAR.exists():
        print(f"ERROR: TriBack-Clo JAR not found at {TRIBACK_JAR}")
        return None, None, None
    
    cmd = [
        "java", f"-Xmx{JVM_HEAP}",
        "-cp", f"{TRIBACK_JAR}:{SPMF_JAR}",
        "ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo",
        str(dataset_file),
        "/dev/null",
        f"{ratio * 100}%"
    ]
    
    if ablation_no_prune:
        cmd.append("--no-prune")
    
    print(f"  Running: {' '.join(cmd[:6])}...")
    
    start_time = time.time()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(BASE_DIR.parent)
        )
        runtime = time.time() - start_time
        
        # Parse output
        patterns = None
        for line in result.stdout.split("\n"):
            if "Pattern count" in line:
                patterns = int(line.split(":")[-1].strip().replace(",", ""))
        
        return runtime, patterns, None
        
    except subprocess.TimeoutExpired:
        return timeout, None, "TIMEOUT"
    except Exception as e:
        return None, None, str(e)

def run_spmf(algorithm, dataset_file, ratio, timeout=TIMEOUT_SEC):
    """Run SPMF algorithm and return (runtime, patterns, memory)"""
    
    if not SPMF_JAR.exists():
        print(f"ERROR: SPMF JAR not found at {SPMF_JAR}")
        print(f"       Download from: https://www.philippe-fournier-viger.com/spmf/")
        return None, None, None
    
    output_file = LOGS_DIR / f"spmf_output_{get_timestamp()}.txt"
    minsup_pct = f"{ratio * 100}%"
    
    cmd = [
        "java", f"-Xmx{JVM_HEAP}",
        "-jar", str(SPMF_JAR),
        "run", algorithm,
        str(dataset_file),
        str(output_file),
        minsup_pct
    ]
    
    print(f"  Running SPMF {algorithm}...")
    
    start_time = time.time()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        runtime = time.time() - start_time
        
        # Parse SPMF output for patterns and memory
        patterns = None
        memory = None
        for line in result.stdout.split("\n"):
            if "Pattern count" in line or "Frequent sequences count" in line:
                patterns = int(line.split(":")[-1].strip())
            if "Max memory" in line:
                memory = float(line.split(":")[-1].strip().split()[0])
        
        # Cleanup temp output
        if output_file.exists():
            output_file.unlink()
        
        return runtime, patterns, memory
        
    except subprocess.TimeoutExpired:
        return timeout, None, "TIMEOUT"
    except Exception as e:
        return None, None, str(e)

# ============================================================
# EXPERIMENTS
# ============================================================

def experiment_A_performance_cliff(datasets_to_run=None):
    """Experiment A: Runtime vs Support (Performance Cliff)"""
    print("\n" + "="*60)
    print("EXPERIMENT A: Performance Cliff (Runtime vs Support)")
    print("="*60)
    
    datasets_to_run = datasets_to_run or list(DATASETS.keys())
    
    for dataset_name in datasets_to_run:
        config = DATASETS.get(dataset_name)
        if not config:
            continue
            
        dataset_file = DATASETS_DIR / config["file"]
        if not dataset_file.exists():
            print(f"\nSkipping {dataset_name}: File not found at {dataset_file}")
            continue
        
        print(f"\n--- {dataset_name} ({config['description']}) ---")
        
        for ratio in config["ratios"]:
            print(f"\n  Minsup: {ratio*100:.3f}%")
            
            # Run TriBack-Clo
            runtime, patterns, mem = run_triback(dataset_file, ratio)
            if runtime:
                log_result("A", dataset_name, "TriBack-Clo", ratio, runtime, patterns, mem)
                print(f"    TriBack-Clo: {runtime:.2f}s, {patterns} patterns")
            
            # Run BIDE+
            runtime, patterns, mem = run_spmf("BIDE+", dataset_file, ratio)
            if runtime:
                log_result("A", dataset_name, "BIDE+", ratio, runtime, patterns, mem)
                print(f"    BIDE+: {runtime:.2f}s, {patterns} patterns")

def experiment_B_memory():
    """Experiment B: Memory Efficiency"""
    print("\n" + "="*60)
    print("EXPERIMENT B: Memory Efficiency")
    print("="*60)
    # Similar structure, focusing on dense datasets
    print("  [Requires memory profiling - implement with JMX or VisualVM]")

def experiment_C_scalability():
    """Experiment C: Scalability with Data Size"""
    print("\n" + "="*60)
    print("EXPERIMENT C: Scalability (Data Size)")
    print("="*60)
    print("  [Requires dataset sampling - implement with random sampling]")

def experiment_D_ablation():
    """Experiment D: Legacy minimal ablation stub.

    The journal-strength component analysis now lives in
    experiments/run_component_contribution_analysis.sh because it
    requires both NoPrune and NoGate variants plus multi-run summaries.
    """
    print("\n" + "="*60)
    print("EXPERIMENT D: Legacy Minimal Ablation")
    print("="*60)
    print("Use the dedicated runner instead:")
    print("  bash experiments/run_component_contribution_analysis.sh --profile journal --skip-existing")
    print("The Python driver is kept only for older exploratory runs.")

# ============================================================
# MAIN
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="TriBack-Clo Experimentation Framework")
    parser.add_argument("--experiment", "-e", choices=["A", "B", "C", "D", "all"], 
                        default="A", help="Which experiment to run")
    parser.add_argument("--datasets", "-d", nargs="+", help="Specific datasets to run")
    args = parser.parse_args()
    
    ensure_dirs()
    
    print("="*60)
    print("TriBack-Clo Experimentation Framework")
    print(f"Timestamp: {get_timestamp()}")
    print("="*60)
    
    if args.experiment == "A" or args.experiment == "all":
        experiment_A_performance_cliff(args.datasets)
    
    if args.experiment == "B" or args.experiment == "all":
        experiment_B_memory()
    
    if args.experiment == "C" or args.experiment == "all":
        experiment_C_scalability()
    
    if args.experiment == "D" or args.experiment == "all":
        experiment_D_ablation()
    
    print("\n" + "="*60)
    print("EXPERIMENTS COMPLETE")
    print(f"Results saved to: {RESULTS_DIR}")
    print("="*60)

if __name__ == "__main__":
    main()
