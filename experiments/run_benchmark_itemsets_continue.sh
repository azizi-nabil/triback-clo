#!/bin/bash
#
# TriBack-Clo Multi-Itemset Benchmark Runner - CONTINUATION
# ===========================================================
#
# This script continues the interrupted benchmark from where it stopped.
# Only runs the remaining incomplete benchmarks.
#
# Incomplete items identified:
#   - D50T40: CloFast (run3), ClaSP (all), CloSpan (all)
#   - D5N1, D5N1.6, D5N2.5: All algorithms, all support thresholds
#
# Usage:
#   ./run_benchmark_itemsets_continue.sh
#

set -o pipefail

# ============================================================
# CONFIGURATION (same as original)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIBACK_CLASSPATH="$SCRIPT_DIR/../triback-clo-java/triback-clo.jar:$SCRIPT_DIR/spmf.jar"
SPMF_JAR="$SCRIPT_DIR/spmf.jar"
DATASETS_DIR="$SCRIPT_DIR/datasets/synthetic/clofast_paper"
RESULTS_DIR="$SCRIPT_DIR/results"
LOGS_DIR="$SCRIPT_DIR/logs_itemsets"

# JVM Settings
JVM_HEAP_START="16g"
JVM_HEAP_MAX="90g"
TIMEOUT_SEC=7200  # 2 hours

# Measurement settings
WARMUP_RUNS=1
MEASURED_RUNS=3

# Timestamp for this continuation run
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/benchmark_itemsets_continue_${TIMESTAMP}.csv"

# ============================================================
# DATASET CONFIGURATIONS
# ============================================================

declare -A DATASET_FILES
DATASET_FILES["D50T40"]="D50C20T40N2.5S6I4.txt"
DATASET_FILES["D5N1"]="D5C10T10N1S6I4.txt"
DATASET_FILES["D5N1.6"]="D5C10T10N1.6S6I4.txt"
DATASET_FILES["D5N2.5"]="D5C10T10N2.5S6I4.txt"

declare -A DATASET_RATIOS
DATASET_RATIOS["D50T40"]="0.4"
DATASET_RATIOS["D5N1"]="0.02 0.015 0.01 0.008 0.006 0.004 0.002 0.001"
DATASET_RATIOS["D5N1.6"]="0.02 0.015 0.01 0.008 0.006 0.004 0.002 0.001"
DATASET_RATIOS["D5N2.5"]="0.02 0.015 0.01 0.008 0.006 0.004 0.002 0.001"

# ============================================================
# FUNCTIONS (copied from original)
# ============================================================

init_csv() {
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    echo "timestamp,dataset,ratio,minsup_pct,algorithm,wall_sec,mining_sec,cpu_pct,maxrss_kb,patterns,status,run_type" > "$CSV_FILE"
    echo "[INIT] Results will be saved to: $CSV_FILE"
}

run_once() {
    local algo="$1"
    local dataset="$2"
    local dataset_file="$3"
    local ratio="$4"
    local run_id="$5"
    
    local log_file="$LOGS_DIR/${algo}_${dataset}_${ratio}_run${run_id}_${TIMESTAMP}.log"
    local time_file="/tmp/time_output_${run_id}_$$.txt"
    
    local exit_code wall_sec mining_sec cpu_pct maxrss patterns status
    local minsup_pct
    minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.6f", r * 100}')
    
    local num_seqs=$(wc -l < "$dataset_file")
    local minsup_abs=$(awk -v r="$ratio" -v n="$num_seqs" 'BEGIN {x=r*n; i=int(x); print (x>i)?i+1:i}')

    if [ "$algo" = "TriBack-Clo-Java" ]; then
        (
            /usr/bin/time -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
                java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX -cp "$TRIBACK_CLASSPATH" \
                ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
                "$dataset_file" "/dev/null" "$minsup_abs"
        ) > "$log_file" 2>&1
        exit_code=$?
        
        patterns=$(awk -F: '/Pattern count/ {gsub(/[^0-9]/,"",$2); print $2}' "$log_file" 2>/dev/null | head -1)
        mining_sec=$(awk '/Total time ~/ { for(i=1;i<=NF;i++) if($i=="~") { gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000 } }' "$log_file" 2>/dev/null | head -1)
    else
        local output_file="/dev/null"
        (
            /usr/bin/time -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
                java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX -jar "$SPMF_JAR" \
                run "$algo" "$dataset_file" "$output_file" "${minsup_pct}%"
        ) > "$log_file" 2>&1
        exit_code=$?
        
        patterns=$(awk -F: '/Pattern count|sequences count/ {gsub(/[^0-9]/,"",$2); print $2}' "$log_file" 2>/dev/null | head -1)
        mining_sec=$(awk '/Total time ~/ { for(i=1;i<=NF;i++) if($i=="~") { gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000 } }' "$log_file" 2>/dev/null | head -1)
    fi
    
    if [ -f "$time_file" ]; then
        local time_output=$(cat "$time_file" 2>/dev/null)
        wall_sec=$(echo "$time_output" | awk '{print $1}')
        cpu_pct=$(echo "$time_output" | awk '{print $2}' | tr -d '%')
        maxrss=$(echo "$time_output" | awk '{print $3}')
        rm -f "$time_file"
    else
        wall_sec="0"; cpu_pct="0"; maxrss="0"
    fi
    
    if [ "${exit_code:-0}" -eq 124 ] || [ "${exit_code:-0}" -eq 137 ]; then
        status="TIMEOUT"; wall_sec=$TIMEOUT_SEC
    elif [ $exit_code -ne 0 ]; then
        status="ERROR"
    else
        status="OK"
    fi
    
    [ -z "$patterns" ] && patterns="0"
    [ -z "$mining_sec" ] && mining_sec="$wall_sec"
    
    echo "$wall_sec $mining_sec $cpu_pct $maxrss $patterns $status"
}

get_median() {
    printf "%s\n" "$@" | LC_ALL=C sort -n | awk '
        {a[NR]=$1}
        END{
            if(NR==0) {print 0; exit}
            if(NR%2==1) { print a[(NR+1)/2] }
            else { print (a[NR/2] + a[NR/2+1]) / 2 }
        }'
}

run_trials() {
    local algo="$1"
    local dataset="$2"
    local dataset_file="$3"
    local ratio="$4"
    
    local minsup_pct
    minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.4f", r * 100}')
    echo -n "  $algo @ ${minsup_pct}%: "
    
    # Warmup
    for w in $(seq 1 $WARMUP_RUNS); do
        echo -n " warmup$w..."
        run_once "$algo" "$dataset" "$dataset_file" "$ratio" "warmup$w" > /dev/null
    done
    
    # Measured runs
    local walls=() mining_vals=() maxrss_vals=() cpu_vals=()
    local patterns_ref="" last_status="OK"
    
    for i in $(seq 1 $MEASURED_RUNS); do
        echo -n " run$i..."
        local result=$(run_once "$algo" "$dataset" "$dataset_file" "$ratio" "$i")
        local w=$(echo "$result" | awk '{print $1}')
        local m=$(echo "$result" | awk '{print $2}')
        local c=$(echo "$result" | awk '{print $3}')
        local r=$(echo "$result" | awk '{print $4}')
        local p=$(echo "$result" | awk '{print $5}')
        local s=$(echo "$result" | awk '{print $6}')
        
        walls+=("$w"); mining_vals+=("$m"); maxrss_vals+=("$r"); cpu_vals+=("$c")
        
        [ -z "$patterns_ref" ] && patterns_ref="$p"
        [ "$s" != "OK" ] && { last_status="$s"; break; }
    done
    
    local n_runs=${#walls[@]}
    local median_wall median_mining median_rss median_cpu
    if [ $n_runs -ge 3 ]; then
        median_wall=$(get_median "${walls[@]}")
        median_mining=$(get_median "${mining_vals[@]}")
        median_rss=$(get_median "${maxrss_vals[@]}")
        median_cpu=$(get_median "${cpu_vals[@]}")
    elif [ $n_runs -ge 1 ]; then
        median_wall="${walls[$((n_runs-1))]}"
        median_mining="${mining_vals[$((n_runs-1))]}"
        median_rss="${maxrss_vals[$((n_runs-1))]}"
        median_cpu="${cpu_vals[$((n_runs-1))]}"
    else
        median_wall="0"; median_mining="0"; median_rss="0"; median_cpu="0"
    fi
    
    local mem_mb=$(awk -v r="$median_rss" 'BEGIN {printf "%.0f", r/1024}')
    echo " done ($last_status, wall=${median_wall}s, mining=${median_mining}s, mem=${mem_mb}MB, ${patterns_ref:-0} patterns)"
    
    echo "$(date +%Y-%m-%d_%H:%M:%S),$dataset,$ratio,$minsup_pct,$algo,$median_wall,$median_mining,$median_cpu,$median_rss,${patterns_ref:-0},$last_status,median_of_${n_runs}" >> "$CSV_FILE"
}

run_dataset() {
    local dataset="$1"
    local algos_to_run="$2"
    
    echo ""
    echo "============================================================"
    echo "DATASET: $dataset (multi-itemset)"
    echo "============================================================"
    
    local dataset_file="$DATASETS_DIR/${DATASET_FILES[$dataset]}"
    
    if [ ! -f "$dataset_file" ]; then
        echo "[SKIP] Dataset file not found: $dataset_file"
        return
    fi
    
    cat "$dataset_file" > /dev/null 2>&1
    
    local ratios="${DATASET_RATIOS[$dataset]}"
    
    for ratio in $ratios; do
        echo ""
        echo "--- Ratio: $ratio ---"
        cat "$dataset_file" > /dev/null 2>&1
        
        for algo in $algos_to_run; do
            run_trials "$algo" "$dataset" "$dataset_file" "$ratio"
        done
    done
}

# ============================================================
# MAIN
# ============================================================

echo "============================================================"
echo "TriBack-Clo Multi-Itemset Benchmark - CONTINUATION"
echo "Timestamp: $TIMESTAMP"
echo "JVM Heap: -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX"
echo "Timeout: ${TIMEOUT_SEC}s"
echo "============================================================"

if [ ! -f "$SCRIPT_DIR/../triback-clo-java/triback-clo.jar" ]; then
    echo "[ERROR] Java TriBack-Clo JAR not found"
    exit 1
fi

init_csv

echo ""
echo "=== Completing D50T40 (missing: CloFast run3, ClaSP, CloSpan) ==="
run_dataset "D50T40" "CloFast ClaSP CloSpan"

echo ""
echo "=== Running D5 Series (all algorithms) ==="
ALL_ALGOS="TriBack-Clo-Java BIDE+ CloFast ClaSP CloSpan"
run_dataset "D5N1" "$ALL_ALGOS"
run_dataset "D5N1.6" "$ALL_ALGOS"
run_dataset "D5N2.5" "$ALL_ALGOS"

echo ""
echo "============================================================"
echo "CONTINUATION BENCHMARK COMPLETE"
echo "Results saved to: $CSV_FILE"
echo "============================================================"
