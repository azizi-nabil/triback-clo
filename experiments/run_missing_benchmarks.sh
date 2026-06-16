#!/bin/bash
#
# TriBack-Clo MISSING Benchmark Runner
# ====================================
# 
# Runs ONLY the missing experiments based on log analysis (Dec 2024)
# 
# Missing datasets (complete runs needed):
#   - BIKE, SIGN, MSNBC, MSNBC_small
#
# Partial datasets (specific ratios):
#   - FIFA: 0.05, 0.02, 0.01, 0.005
#   - Kosarak: 0.001, 0.0005, 0.0002
#   - Kosarak25k: 0.0002, 0.0005, 0.001
#
# Usage:
#   ./run_missing_benchmarks.sh all      # Run all missing
#   ./run_missing_benchmarks.sh MSNBC    # Run MSNBC only
#   ./run_missing_benchmarks.sh all quick # Quick test

# Don't use set -e globally - it breaks timeout handling
# But use pipefail for better pipeline exit codes
set -o pipefail

# ============================================================
# CLEANUP HANDLER - Kill all child processes on exit
# ============================================================

# Track if script completed normally
SCRIPT_COMPLETED=false

cleanup() {
    # Skip cleanup message if script completed normally
    if [ "$SCRIPT_COMPLETED" = true ]; then
        return 0
    fi
    
    echo ""
    echo "[CLEANUP] Script interrupted, terminating running experiments..."
    
    # Kill any remaining java processes started by this script
    # Use pkill with parent PID to only kill our children
    pkill -TERM -P $$ java 2>/dev/null
    sleep 1
    pkill -KILL -P $$ java 2>/dev/null
    
    # Also kill any timeout processes we spawned
    pkill -TERM -P $$ timeout 2>/dev/null
    sleep 1
    pkill -KILL -P $$ timeout 2>/dev/null
    
    echo "[CLEANUP] Done. Partial results saved to: $CSV_FILE"
    exit 130  # Standard exit code for SIGINT
}

# Trap signals to ensure cleanup runs on interrupt
trap cleanup SIGINT SIGTERM SIGHUP

# ============================================================
# CONFIGURATION
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIBACK_JAR="$SCRIPT_DIR/../target/scala-2.13/triback-clo.jar"
SPMF_JAR="$SCRIPT_DIR/spmf.jar"
DATASETS_DIR="$SCRIPT_DIR/datasets"
RESULTS_DIR="$SCRIPT_DIR/results"
LOGS_DIR="$SCRIPT_DIR/logs"

# JVM Settings (SAME for all algorithms - fairness)
# For time+memory claims: low Xms allows RSS to reflect real usage
JVM_HEAP_START="4g"
JVM_HEAP_MAX="80g"
# GC flags to prevent system freeze (fail fast instead of thrashing)
JVM_GC_FLAGS="-XX:+UseParallelGC -XX:+UseGCOverheadLimit -XX:GCTimeLimit=90"
TIMEOUT_SEC=7200  # 2 hours

# Measurement settings
WARMUP_RUNS=1
MEASURED_RUNS=3  # Median of 3

# Algorithms to compare
ALGORITHMS=("TriBack-Clo" "BIDE+" "ClaSP" "CloSpan")  # CloFast removed (broken in SPMF)

# Output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/benchmark_${TIMESTAMP}.csv"

# ============================================================
# DATASET CONFIGURATIONS - MISSING EXPERIMENTS ONLY
# Based on logs analysis (Dec 29, 2024 15:53)
# 
# ✅ Complete: Kosarak25k 0.002
# ✅ Almost complete: MSNBC (only CloSpan 0.002 needs 1 more run)
# ⚠️ Partial: FIFA, Kosarak (need more runs)
# ❌ Missing: SIGN, MSNBC_small
# ============================================================

declare -A DATASET_FILES
declare -A DATASET_RATIOS

# SIGN - All ratios completely missing
DATASET_FILES["SIGN"]="SIGN.txt"
DATASET_RATIOS["SIGN"]="0.05 0.02 0.01"

# FIFA - Has 1 run each, needs 2 more runs per ratio
DATASET_FILES["FIFA"]="FIFA.txt"
DATASET_RATIOS["FIFA"]="0.02 0.01"

# Kosarak - TriBack-Clo complete, SPMF algorithms need more runs
DATASET_FILES["Kosarak"]="kosarak_sequences.txt"
DATASET_RATIOS["Kosarak"]="0.001"

# Kosarak25k - COMPLETE, removed from missing list
# DATASET_FILES["Kosarak25k"]="kosarak25k.txt"
# DATASET_RATIOS["Kosarak25k"]="0.002"

# MSNBC - Almost complete (only CloSpan 0.002 missing 1 run)
# Keeping it but can skip if you want
DATASET_FILES["MSNBC"]="MSNBC_SPMF.txt"
DATASET_RATIOS["MSNBC"]="0.002"

# MSNBC_small - Completely missing
DATASET_FILES["MSNBC_small"]="MSNBC.txt"
DATASET_RATIOS["MSNBC_small"]="0.05 0.02 0.01 0.03 0.005 0.002"

# Quick test ratios (for validation)
declare -A DATASET_RATIOS_QUICK
DATASET_RATIOS_QUICK["SIGN"]="0.05"
DATASET_RATIOS_QUICK["FIFA"]="0.02"
DATASET_RATIOS_QUICK["Kosarak"]="0.001"
DATASET_RATIOS_QUICK["MSNBC"]="0.002"
DATASET_RATIOS_QUICK["MSNBC_small"]="0.05"

# ============================================================
# FUNCTIONS
# ============================================================

init_csv() {
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    echo "timestamp,dataset,ratio,minsup_pct,algorithm,wall_sec,mining_sec,cpu_pct,maxrss_kb,patterns,status,run_type" > "$CSV_FILE"
    echo "[INIT] Results will be saved to: $CSV_FILE"
}

# Run a single trial and return: wall cpu rss patterns status
run_once() {
    local algo="$1"
    local dataset="$2"
    local dataset_file="$3"
    local ratio="$4"
    local run_id="$5"
    
    local log_file="$LOGS_DIR/${algo}_${dataset}_${ratio}_run${run_id}_${TIMESTAMP}.log"
    local time_file="/tmp/time_output_${run_id}_$$.txt"
    
    local exit_code wall_sec mining_sec cpu_pct maxrss patterns status
    
    if [ "$algo" = "TriBack-Clo" ]; then
        # Run TriBack-Clo (subshell for correct exit code)
        (
            /usr/bin/time -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
                java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX $JVM_GC_FLAGS -cp "$TRIBACK_JAR" tribackclo.TriBackClo_Main \
                --input "$dataset_file" --ratio "$ratio"
        ) > "$log_file" 2>&1
        exit_code=$?
        
        # Parse pattern count with awk (portable, no grep -P dependency)
        patterns=$(awk '
            /Found[[:space:]]+[0-9]/ {
                gsub(/,/,"");
                for(i=1;i<=NF;i++){
                    if($i ~ /^[0-9]+$/ && $(i-1)=="Found"){ print $i; exit }
                }
            }' "$log_file" 2>/dev/null)
        
        # Parse internal mining time (Mining: X.XXX s)
        mining_sec=$(awk '/Mining:/ { for(i=1;i<=NF;i++) if($i=="Mining:") print $(i+1) }' "$log_file" 2>/dev/null | head -1)
    else
        # Run SPMF (subshell for correct exit code)
        local minsup_pct
        minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.6f", r * 100}')
        local output_file="/dev/null"  # Disable output for performance
        
        (
            /usr/bin/time -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
                java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX $JVM_GC_FLAGS -jar "$SPMF_JAR" \
                run "$algo" "$dataset_file" "$output_file" "${minsup_pct}%"
        ) > "$log_file" 2>&1
        exit_code=$?
        
        # Parse pattern count with awk (matches all SPMF output formats)
        patterns=$(awk -F: '/Pattern count|sequences count/ {gsub(/[^0-9]/,"",$2); print $2}' "$log_file" 2>/dev/null | head -1)
        
        # Parse internal mining time (Total time ~ XXX ms)
        mining_sec=$(awk '/Total time ~/ { for(i=1;i<=NF;i++) if($i=="~") { gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000 } }' "$log_file" 2>/dev/null | head -1)
    fi
    
    # Parse time output and append to log
    if [ -f "$time_file" ]; then
        local time_output=$(cat "$time_file" 2>/dev/null)
        wall_sec=$(echo "$time_output" | awk '{print $1}')
        cpu_pct=$(echo "$time_output" | awk '{print $2}' | tr -d '%')
        maxrss=$(echo "$time_output" | awk '{print $3}')
        # Append wall time and memory to log file for reference
        echo "" >> "$log_file"
        echo "============================================================" >> "$log_file"
        echo "[RESOURCE] Wall time: ${wall_sec} sec | CPU: ${cpu_pct}% | MaxRSS: ${maxrss} KB" >> "$log_file"
        echo "============================================================" >> "$log_file"
        rm -f "$time_file"
    else
        wall_sec="0"
        cpu_pct="0"
        maxrss="0"
    fi
    
    # Determine status (124=timeout, 125=timeout error, 137=SIGKILL, 143=SIGTERM)
    if [ "${exit_code:-0}" -eq 124 ] || [ "${exit_code:-0}" -eq 125 ] || [ "${exit_code:-0}" -eq 137 ] || [ "${exit_code:-0}" -eq 143 ]; then
        status="TIMEOUT"
        wall_sec=$TIMEOUT_SEC
    elif [ $exit_code -ne 0 ]; then
        status="ERROR"
    else
        status="OK"
    fi
    
    [ -z "$patterns" ] && patterns="0"
    [ -z "$mining_sec" ] && mining_sec="$wall_sec"  # Fallback to wall time if mining time not found
    
    echo "$wall_sec $mining_sec $cpu_pct $maxrss $patterns $status"
}

# Get median of array (handles even N by averaging middle two)
get_median() {
    printf "%s\n" "$@" | LC_ALL=C sort -n | awk '
        {a[NR]=$1}
        END{
            if(NR==0) {print 0; exit}
            if(NR%2==1) {
                print a[(NR+1)/2]
            } else {
                print (a[NR/2] + a[NR/2+1]) / 2
            }
        }'
}

# Run with warmup + measured trials, return median
run_trials() {
    local algo="$1"
    local dataset="$2"
    local dataset_file="$3"
    local ratio="$4"
    
    local minsup_pct
    minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.4f", r * 100}')
    echo -n "  $algo @ ${minsup_pct}%: "
    
    # Warmup runs (not recorded)
    for w in $(seq 1 $WARMUP_RUNS); do
        echo -n " warmup$w..."
        run_once "$algo" "$dataset" "$dataset_file" "$ratio" "warmup$w" > /dev/null
    done
    
    # Measured runs
    local walls=()
    local mining_vals=()
    local maxrss_vals=()
    local cpu_vals=()
    local patterns_ref_ok=""   # Reference from OK runs only
    local patterns_any=""      # Fallback from any run
    local last_status="OK"
    
    for i in $(seq 1 $MEASURED_RUNS); do
        echo -n " run$i..."
        local result=$(run_once "$algo" "$dataset" "$dataset_file" "$ratio" "$i")
        local w=$(echo "$result" | awk '{print $1}')
        local m=$(echo "$result" | awk '{print $2}')
        local c=$(echo "$result" | awk '{print $3}')
        local r=$(echo "$result" | awk '{print $4}')
        local p=$(echo "$result" | awk '{print $5}')
        local s=$(echo "$result" | awk '{print $6}')
        
        walls+=("$w")
        mining_vals+=("$m")
        maxrss_vals+=("$r")
        cpu_vals+=("$c")
        
        # Always capture first pattern count as fallback
        if [ -z "$patterns_any" ]; then
            patterns_any="${p:-0}"
        fi
        
        # Pattern consistency check (only between OK runs)
        if [ "$s" = "OK" ]; then
            if [ -z "$patterns_ref_ok" ]; then
                patterns_ref_ok="$p"
            elif [ "$p" != "$patterns_ref_ok" ]; then
                last_status="MISMATCH"
                echo -n " [WARN: pattern mismatch $patterns_ref_ok vs $p]"
                break
            fi
        fi
        
        # Track status (keep worst)
        if [ "$s" != "OK" ]; then
            last_status="$s"
            break  # Don't continue on error/timeout
        fi
    done
    
    # Compute medians (portable: avoid negative indices)
    local median_wall median_mining median_rss median_cpu
    local n_runs=${#walls[@]}
    if [ $n_runs -ge 3 ]; then
        median_wall=$(get_median "${walls[@]}")
        median_mining=$(get_median "${mining_vals[@]}")
        median_rss=$(get_median "${maxrss_vals[@]}")
        median_cpu=$(get_median "${cpu_vals[@]}")
    elif [ $n_runs -ge 1 ]; then
        # Use last element (portable)
        median_wall="${walls[$((n_runs-1))]}"
        median_mining="${mining_vals[$((n_runs-1))]}"
        median_rss="${maxrss_vals[$((n_runs-1))]}"
        median_cpu="${cpu_vals[$((n_runs-1))]}"
    else
        median_wall="0"
        median_mining="0"
        median_rss="0"
        median_cpu="0"
    fi
    
    # Use OK pattern count if available, else fallback
    local patterns_for_csv="${patterns_ref_ok:-$patterns_any}"
    [ -z "$patterns_for_csv" ] && patterns_for_csv="0"
    
    echo " done ($last_status, wall=${median_wall}s, mining=${median_mining}s, ${patterns_for_csv} patterns)"
    
    # Write to CSV
    echo "$(date +%Y-%m-%d_%H:%M:%S),$dataset,$ratio,$minsup_pct,$algo,$median_wall,$median_mining,$median_cpu,$median_rss,$patterns_for_csv,$last_status,median_of_${n_runs}" >> "$CSV_FILE"
}

run_dataset() {
    local dataset="$1"
    local mode="${2:-full}"
    
    # Check if dataset key exists
    if [ -z "${DATASET_FILES[$dataset]+x}" ]; then
        echo "[SKIP] Unknown dataset key: $dataset (check spelling)"
        return
    fi
    
    echo ""
    echo "============================================================"
    echo "DATASET: $dataset"
    echo "============================================================"
    
    local dataset_file="$DATASETS_DIR/${DATASET_FILES[$dataset]}"
    
    if [ ! -f "$dataset_file" ]; then
        echo "[SKIP] Dataset file not found: $dataset_file"
        return
    fi
    
    # Warm OS cache at dataset start
    echo "[CACHE] Warming OS file cache for $dataset..."
    cat "$dataset_file" > /dev/null 2>&1
    
    local ratios
    if [ "$mode" = "quick" ]; then
        ratios="${DATASET_RATIOS_QUICK[$dataset]}"
    else
        ratios="${DATASET_RATIOS[$dataset]}"
    fi
    
    if [ -z "$ratios" ]; then
        echo "[SKIP] Unknown dataset: $dataset"
        return
    fi
    
    for ratio in $ratios; do
        echo ""
        echo "--- Ratio: $ratio ---"
        
        # Warm OS file cache for fair comparison
        cat "$dataset_file" > /dev/null 2>&1
        
        for algo in "${ALGORITHMS[@]}"; do
            run_trials "$algo" "$dataset" "$dataset_file" "$ratio"
        done
    done
}

# ============================================================
# MAIN
# ============================================================

echo "============================================================"
echo "TriBack-Clo Benchmark Runner v2"
echo "Timestamp: $TIMESTAMP"
echo "JVM Heap: -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX"
echo "Timeout: ${TIMEOUT_SEC}s"
echo "Trials: $WARMUP_RUNS warmup + $MEASURED_RUNS measured (median)"
echo "============================================================"

# Check prerequisites
if [ ! -f "$TRIBACK_JAR" ]; then
    echo "[ERROR] TriBack-Clo JAR not found: $TRIBACK_JAR"
    echo "        Run: cd .. && sbt assembly"
    exit 1
fi

if [ ! -f "$SPMF_JAR" ]; then
    echo "[WARN] SPMF JAR not found: $SPMF_JAR"
    echo "       Download from: https://www.philippe-fournier-viger.com/spmf/"
    echo "       Continuing with TriBack-Clo only..."
    ALGORITHMS=("TriBack-Clo")
fi

init_csv

# Parse arguments
TARGET="${1:-all}"
MODE="${2:-full}"

if [ "$TARGET" = "all" ]; then
    # Only datasets with missing experiments
    # Removed: Kosarak25k (complete)
    for dataset in SIGN FIFA Kosarak MSNBC MSNBC_small; do
        run_dataset "$dataset" "$MODE"
    done
else
    run_dataset "$TARGET" "$MODE"
fi

echo ""
echo "============================================================"
echo "BENCHMARK COMPLETE"
echo "Results saved to: $CSV_FILE"
echo "============================================================"

# Mark script as completed normally (prevents cleanup message)
SCRIPT_COMPLETED=true
