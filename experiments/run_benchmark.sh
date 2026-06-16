#!/bin/bash
#
# TriBack-Clo Benchmark Runner v2
# ================================
# 
# Paper-ready experimentation with:
# - Warmup run + 3 measured runs (median)
# - Timeout handling with proper set -e guard
# - Memory tracking via /usr/bin/time
# - CSV output for analysis
#
# Usage:
#   ./run_benchmark.sh [dataset] [mode]
#   ./run_benchmark.sh all         # Run all datasets
#   ./run_benchmark.sh FIFA        # Run FIFA only
#   ./run_benchmark.sh FIFA quick  # Quick test (fewer ratios)

# Don't use set -e globally - it breaks timeout handling
# But use pipefail for better pipeline exit codes
set -o pipefail

# ============================================================
# CONFIGURATION
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Java TriBack-Clo: JAR in triback-clo-java/triback-clo.jar, SPMF in spmf.jar
TRIBACK_CLASSPATH="$SCRIPT_DIR/../triback-clo-java/triback-clo.jar:$SCRIPT_DIR/spmf.jar"
SPMF_JAR="$SCRIPT_DIR/spmf.jar"
DATASETS_DIR="$SCRIPT_DIR/datasets"
RESULTS_DIR="$SCRIPT_DIR/results"
LOGS_DIR="$SCRIPT_DIR/logs"
MANIFEST_FILE="$RESULTS_DIR/configuration_manifest.csv"

# JVM Settings (SAME for all algorithms - fairness)
# For time+memory claims: low Xms allows RSS to reflect real usage
JVM_HEAP_START="16g"
JVM_HEAP_MAX="90g"
TIMEOUT_SEC=7200  # 2 hours

# Measurement settings
WARMUP_RUNS=1
MEASURED_RUNS=3  # Median of 3

# Algorithms to compare (can be overridden by 3rd argument: "triback" or "spmf" or "all")
ALGORITHMS=(\"TriBack-Clo\" \"BIDE+\" \"ClaSP\" \"CloSpan\")  # CloFast removed (broken in SPMF)

# Output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/benchmark_${TIMESTAMP}.csv"

# ============================================================
# DATASET CONFIGURATIONS (refined plan with absolute minsup)
# ============================================================

declare -A DATASET_FILES
declare -A DATASET_RATIOS

# Kosarak full (N=990,002) - flagship deep sweep
# 2%→19801, 1%→9901, 0.5%→4951, 0.2%→1981, 0.1%→991, 0.05%→496, 0.02%→198
DATASET_FILES["Kosarak"]="kosarak_sequences.txt"
DATASET_RATIOS["Kosarak"]="0.1 0.05 0.02 0.01 0.005 0.002 0.001"

# Kosarak25k (N=25,000) - low minsup stress test
# 1%→250, 0.5%→125, 0.2%→50, 0.1%→25, 0.05%→13, 0.02%→5
DATASET_FILES["Kosarak25k"]="kosarak25k.txt"
DATASET_RATIOS["Kosarak25k"]="0.1 0.01 0.005 0.002 0.001 0.0005 0.0002"

# BMSWebView2 (N=77,512) - short sequences, many items
# 5%→3876, 2%→1551, 1%→776, 0.5%→388, 0.2%→156, 0.1%→78
DATASET_FILES["BMS2"]="BMS2.txt"
DATASET_RATIOS["BMS2"]="0.2 0.1 0.05 0.02 0.01 0.005 0.001 0.0005 0.0001 0.00005 0.00001 0.000005"

# FIFA (N=20,450) - long sequences, dense scans
# 20%→4090, 10%→2045, 5%→1023, 2%→409, 1%→205, 0.5%→103
DATASET_FILES["FIFA"]="FIFA.txt"
DATASET_RATIOS["FIFA"]="0.2 0.1 0.05 0.02 0.01 0.005"

# BIKE (N=21,078) - small alphabet (67 items)
# 20%→4216, 10%→2108, 5%→1054, 2%→422, 1%→211, 0.5%→106
DATASET_FILES["BIKE"]="BIKE.txt"
DATASET_RATIOS["BIKE"]="0.2 0.1 0.05 0.02 0.01 0.005 0.002 0.001 0.0005 0.0001"

# SIGN (N=800) - small N, dense sequences (avg len 52)
# 20%→160, 10%→80, 5%→40, 2%→16, 1%→8
DATASET_FILES["SIGN"]="SIGN.txt"
DATASET_RATIOS["SIGN"]="0.2 0.1 0.05 0.02 0.01"

# MSNBC-full (N=989,818) - huge but low alphabet (17 items)
# 5%→49491, 2%→19797, 1%→9899, 0.5%→4950, 0.2%→1980, 0.1%→990, 0.05%→495
DATASET_FILES["MSNBC"]="MSNBC_SPMF.txt"
DATASET_RATIOS["MSNBC"]="0.05 0.02 0.01 0.005 0.002 0.001 0.0005"

# MSNBC-small (N=31,790) - filtered version
# 20%→6358, 10%→3179, 5%→1590, 2%→636, 1%→318, 0.5%→159
DATASET_FILES["MSNBC_small"]="MSNBC.txt"
DATASET_RATIOS["MSNBC_small"]="0.05 0.02 0.01 0.005 0.002 0.0005"


# Quick test ratios (for validation - 2 points per dataset)
declare -A DATASET_RATIOS_QUICK
DATASET_RATIOS_QUICK["Kosarak"]="0.005 0.001"
DATASET_RATIOS_QUICK["Kosarak25k"]="0.005 0.001"
DATASET_RATIOS_QUICK["BMS2"]="0.01 0.002"
DATASET_RATIOS_QUICK["FIFA"]="0.1 0.02"
DATASET_RATIOS_QUICK["BIKE"]="0.1 0.02"
DATASET_RATIOS_QUICK["SIGN"]="0.1 0.02"
DATASET_RATIOS_QUICK["MSNBC"]="0.01 0.002"
DATASET_RATIOS_QUICK["MSNBC_small"]="0.1 0.02"

# ============================================================
# FUNCTIONS
# ============================================================

init_csv() {
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    echo "timestamp,dataset,ratio,minsup_pct,algorithm,wall_sec,mining_sec,cpu_pct,maxrss_kb,patterns,status,run_type" > "$CSV_FILE"
    
    # Initialize manifest if not exists (preserve across restarts if desired, or wipe)
    if [ ! -f "$MANIFEST_FILE" ]; then
        echo "dataset,minsup,algorithm,run_type,run_id,expected_output_equivalent_group,log_path" > "$MANIFEST_FILE"
    fi
    echo "[INIT] Results will be saved to: $CSV_FILE"
    echo "[INIT] Manifest will be saved to: $MANIFEST_FILE"
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
        # Run Java TriBack-Clo (SPMF-compatible)
        # Convert ratio to percentage (ratio 0.005 = 0.5%)
        local minsup_pct
        minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.6f", r * 100}')
        (
            /usr/bin/time -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
                java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX -cp "$TRIBACK_CLASSPATH" \
                ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
                "$dataset_file" "/dev/null" "${minsup_pct}%"
        ) > "$log_file" 2>&1
        exit_code=$?
        
        # Log to manifest immediately after run
        local run_type_label="measured"
        local run_num="$run_id"
        if [[ "$run_id" == warmup* ]]; then
            run_type_label="warmup"
            run_num="${run_id#warmup}"
        fi
        local group_id="${dataset}_${ratio}_group"
        echo "${dataset},${minsup_pct}%,${algo},${run_type_label},${run_num},${group_id},${log_file}" >> "$MANIFEST_FILE"
        
        # Parse pattern count (SPMF format: "Pattern count : XXX")
        patterns=$(awk -F: '/Pattern count/ {gsub(/[^0-9]/,"",$2); print $2}' "$log_file" 2>/dev/null | head -1)
        
        # Parse internal mining time (Total time ~ XXX ms)
        mining_sec=$(awk '/Total time ~/ { for(i=1;i<=NF;i++) if($i=="~") { gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000 } }' "$log_file" 2>/dev/null | head -1)
    else
        # Run SPMF (subshell for correct exit code)
        local minsup_pct
        minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.6f", r * 100}')
        local output_file="/dev/null"  # Disable output for performance
        
        (
            /usr/bin/time -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
                java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX -jar "$SPMF_JAR" \
                run "$algo" "$dataset_file" "$output_file" "${minsup_pct}%"
        ) > "$log_file" 2>&1
        exit_code=$?
        
        # Log to manifest immediately after run
        local run_type_label="measured"
        local run_num="$run_id"
        if [[ "$run_id" == warmup* ]]; then
            run_type_label="warmup"
            run_num="${run_id#warmup}"
        fi
        local group_id="${dataset}_${ratio}_group"
        echo "${dataset},${minsup_pct}%,${algo},${run_type_label},${run_num},${group_id},${log_file}" >> "$MANIFEST_FILE"
        
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
    elif [ "$exit_code" -eq 139 ] || [ "$exit_code" -eq 134 ]; then
        status="OOM"  # Segmentation fault or abort often related to OOM in some environments, but let's be more specific if we can
    elif [ $exit_code -ne 0 ]; then
        status="FAILED" # Capture generic non-zero as FAILED per user request
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
JAVA_JAR="$SCRIPT_DIR/../triback-clo-java/triback-clo.jar"
if [ ! -f "$JAVA_JAR" ]; then
    echo "[ERROR] Java TriBack-Clo JAR not found: $JAVA_JAR"
    echo "        Run: ./triback-clo-java/build.sh"
    exit 1
fi

if [ ! -f "$SPMF_JAR" ]; then
    echo "[WARN] SPMF JAR not found: $SPMF_JAR"
    echo "       Download from: https://www.philippe-fournier-viger.com/spmf/"
    echo "       Continuing with TriBack-Clo only..."
    ALGORITHMS=("TriBack-Clo")
fi

init_csv


# Parse arguments with flexible ordering detection
ARG1="${1:-all}"
ARG2="${2:-full}"
ARG3="${3:-all}"

# Default assignments
TARGET="all"
MODE="full"
ALGO_FILTER="all"

# Helper to identify argument type
get_arg_type() {
    case "$1" in
        TriBack-Clo|BIDE+|ClaSP|CloSpan|triback|spmf) echo "ALGO" ;;
        run|full|valid|test) echo "MODE" ;;
        Kosarak|Kosarak25k|BMS2|FIFA|BIKE|SIGN|MSNBC|MSNBC_small|SyntheticDense|all) echo "TARGET" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# Intelligent parsing loop
for arg in "$ARG1" "$ARG2" "$ARG3"; do
    TYPE=$(get_arg_type "$arg")
    if [ "$TYPE" = "ALGO" ]; then ALGO_FILTER="$arg"; fi
    if [ "$TYPE" = "MODE" ]; then MODE="$arg"; fi
    if [ "$TYPE" = "TARGET" ]; then TARGET="$arg"; fi
done

# Filter algorithms based on detected filter
case "$ALGO_FILTER" in
    triback|TriBack-Clo)
        ALGORITHMS=("TriBack-Clo")
        echo "[INFO] Running only TriBack-Clo"
        ;;
    spmf)
        ALGORITHMS=("BIDE+" "ClaSP" "CloSpan")
        echo "[INFO] Running only SPMF algorithms"
        ;;
    *)
        ALGORITHMS=("TriBack-Clo" "BIDE+" "ClaSP" "CloSpan")
        ;;
esac

if [ "$TARGET" = "all" ]; then
    # Run only missing datasets as requested by user
    for dataset in BIKE SIGN MSNBC MSNBC_small SyntheticDense; do
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
