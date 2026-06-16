#!/bin/bash
#
# TriBack-Clo Multi-Itemset Benchmark Runner
# ============================================
# 
# Benchmarks for CloFAST-style synthetic datasets with multi-item itemsets.
# Based on run_benchmark.sh structure for consistency.
#
# Datasets match CloFAST paper (Fumarola et al. 2016):
#   - D10C20-80: Density sweep (10k sequences)
#   - D20C20-80: Long sequences variant (20k sequences)  
#   - D50C20T10-40: Transaction length sweep (50k sequences)
#   - D5C10T10: Small tests (5k sequences)
#
# Usage:
#   ./run_benchmark_itemsets.sh [dataset_group] [mode] [algo_filter]
#   ./run_benchmark_itemsets.sh all              # Run all datasets
#   ./run_benchmark_itemsets.sh D10              # Run D10k series only
#   ./run_benchmark_itemsets.sh D10 quick        # Quick test
#   ./run_benchmark_itemsets.sh all full triback # Only TriBack-Clo

set -o pipefail

# ============================================================
# CONFIGURATION
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

# Default algorithms (all SPMF closed sequence miners)
ALGORITHMS=("TriBack-Clo-Java" "BIDE+" "CloFast" "ClaSP" "CloSpan")

# Output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/benchmark_itemsets_${TIMESTAMP}.csv"

# ============================================================
# DATASET CONFIGURATIONS - CloFAST Paper Style
# ============================================================

declare -A DATASET_FILES
declare -A DATASET_RATIOS

# D10 Series: Density sweep (N=10k, T=20, varying C)
DATASET_FILES["D10C20"]="D10C20T20N5S6I4.txt"
DATASET_FILES["D10C30"]="D10C30T20N5S6I4.txt"
DATASET_FILES["D10C40"]="D10C40T20N5S6I4.txt"
DATASET_FILES["D10C50"]="D10C50T20N5S6I4.txt"
DATASET_FILES["D10C60"]="D10C60T20N5S6I4.txt"
DATASET_FILES["D10C70"]="D10C70T20N5S6I4.txt"
DATASET_FILES["D10C80"]="D10C80T20N5S6I4.txt"

# D20 Series: Long sequences (N=20k, T=2.5, N_items=10)
DATASET_FILES["D20C20"]="D20C20T2.5N10S10I1.25.txt"
DATASET_FILES["D20C30"]="D20C30T2.5N10S10I1.25.txt"
DATASET_FILES["D20C40"]="D20C40T2.5N10S10I1.25.txt"
DATASET_FILES["D20C50"]="D20C50T2.5N10S10I1.25.txt"
DATASET_FILES["D20C60"]="D20C60T2.5N10S10I1.25.txt"
DATASET_FILES["D20C70"]="D20C70T2.5N10S10I1.25.txt"
DATASET_FILES["D20C80"]="D20C80T2.5N10S10I1.25.txt"

# D50 Series: Transaction length sweep (N=50k, C=20, varying T)
DATASET_FILES["D50T10"]="D50C20T10N2.5S6I4.txt"
DATASET_FILES["D50T20"]="D50C20T20N2.5S6I4.txt"
DATASET_FILES["D50T30"]="D50C20T30N2.5S6I4.txt"
DATASET_FILES["D50T40"]="D50C20T40N2.5S6I4.txt"

# D5 Series: Small tests (N=5k)
DATASET_FILES["D5N1"]="D5C10T10N1S6I4.txt"
DATASET_FILES["D5N1.6"]="D5C10T10N1.6S6I4.txt"
DATASET_FILES["D5N2.5"]="D5C10T10N2.5S6I4.txt"

# =============================================================
# CloFAST Paper Figure 10 Exact Configurations
# =============================================================
# Fig 10a,d: D20C[20-80]T2.5N10S10I1.25 min_sup = 0.05 (sparse)
# Fig 10b,e: D20C[20-80]T2.5N10S10I1.25 min_sup = 0.1 (sparse)
# Fig 10c,f: D10C[20-80]T20N5S6I4 min_sup = 0.4 (dense)
# C values: 20, 40, 60, 80 only
# =============================================================

# D10 series (Dense): min_sup = 0.4 (40%) - Fig 10c,f
DATASET_RATIOS["D10C20"]="0.4"
DATASET_RATIOS["D10C30"]="0.4"  # Not in Fig 10, but available
DATASET_RATIOS["D10C40"]="0.4"
DATASET_RATIOS["D10C50"]="0.4"  # Not in Fig 10, but available
DATASET_RATIOS["D10C60"]="0.4"
DATASET_RATIOS["D10C70"]="0.4"  # Not in Fig 10, but available
DATASET_RATIOS["D10C80"]="0.4"

# D20 series (Sparse): min_sup = 0.05 and 0.1 - Fig 10a,b,d,e
DATASET_RATIOS["D20C20"]="0.1 0.05"
DATASET_RATIOS["D20C30"]="0.1 0.05"  # Not in Fig 10, but available
DATASET_RATIOS["D20C40"]="0.1 0.05"
DATASET_RATIOS["D20C50"]="0.1 0.05"  # Not in Fig 10, but available
DATASET_RATIOS["D20C60"]="0.1 0.05"
DATASET_RATIOS["D20C70"]="0.1 0.05"  # Not in Fig 10, but available
DATASET_RATIOS["D20C80"]="0.1 0.05"

# =============================================================
# CloFAST Paper Figure 9 Exact Configurations
# =============================================================
# Fig 9: D50C20T[10-40]N2.5S6I4 min_sup = 0.4
# T/N = {4, 8, 12, 16} → T = {10, 20, 30, 40} with N = 2.5
# D = 50k, C = 20, min_sup = 40%
# =============================================================

# D50 series - Figure 9: Transaction length sweep
DATASET_RATIOS["D50T10"]="0.4"  # T/N = 4
DATASET_RATIOS["D50T20"]="0.4"  # T/N = 8
DATASET_RATIOS["D50T30"]="0.4"  # T/N = 12
DATASET_RATIOS["D50T40"]="0.4"  # T/N = 16

# =============================================================
# CloFAST Paper Figure 8 Exact Configurations
# =============================================================
# Fig 8a,d: D5C10T10N2.5S6I4 - varying min_sup
# Fig 8b,e: D5C10T10N1.6S6I4 - varying min_sup
# Fig 8c,f: D5C10T10N1S6I4 - varying min_sup
# D = 5k, C = 10, T = 10, N = {2.5, 1.6, 1}
# =============================================================

# D5 series - Figure 8: varying min_sup from low to high
# Based on typical CloFAST paper ranges (0.1% to 2%)
DATASET_RATIOS["D5N2.5"]="0.02 0.015 0.01 0.008 0.006 0.004 0.002 0.001"
DATASET_RATIOS["D5N1.6"]="0.02 0.015 0.01 0.008 0.006 0.004 0.002 0.001"
DATASET_RATIOS["D5N1"]="0.02 0.015 0.01 0.008 0.006 0.004 0.002 0.001"

# Quick test ratios
declare -A DATASET_RATIOS_QUICK
for key in "${!DATASET_FILES[@]}"; do
    DATASET_RATIOS_QUICK[$key]="0.01 0.005"
done

# ============================================================
# FUNCTIONS (same as run_benchmark.sh)
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
    
    # Calculate absolute support for TriBack-Clo to avoid double-loading in Java
    local num_seqs=$(wc -l < "$dataset_file")
    local minsup_abs=$(awk -v r="$ratio" -v n="$num_seqs" 'BEGIN {val=r*n; if (val<1) val=1; printf "%.0f", val}') # Round? Ceil? Using simple logic.
    # Ideally ceil:
    minsup_abs=$(awk -v r="$ratio" -v n="$num_seqs" 'BEGIN {x=r*n; i=int(x); print (x>i)?i+1:i}')

    if [ "$algo" = "TriBack-Clo-Java" ] || [ "$algo" = "TriBack-Clo" ]; then
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
    
    # Compute medians
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
    
    # Convert MaxRSS from KB to MB for display
    local mem_mb=$(awk -v r="$median_rss" 'BEGIN {printf "%.0f", r/1024}')
    echo " done ($last_status, wall=${median_wall}s, mining=${median_mining}s, mem=${mem_mb}MB, ${patterns_ref:-0} patterns)"
    
    echo "$(date +%Y-%m-%d_%H:%M:%S),$dataset,$ratio,$minsup_pct,$algo,$median_wall,$median_mining,$median_cpu,$median_rss,${patterns_ref:-0},$last_status,median_of_${n_runs}" >> "$CSV_FILE"
}

run_dataset() {
    local dataset="$1"
    local mode="${2:-full}"
    
    if [ -z "${DATASET_FILES[$dataset]+x}" ]; then
        echo "[SKIP] Unknown dataset: $dataset"
        return
    fi
    
    echo ""
    echo "============================================================"
    echo "DATASET: $dataset (multi-itemset)"
    echo "============================================================"
    
    local dataset_file="$DATASETS_DIR/${DATASET_FILES[$dataset]}"
    
    if [ ! -f "$dataset_file" ]; then
        echo "[SKIP] Dataset file not found: $dataset_file"
        return
    fi
    
    # Cache warmup
    cat "$dataset_file" > /dev/null 2>&1
    
    local ratios
    if [ "$mode" = "quick" ]; then
        ratios="${DATASET_RATIOS_QUICK[$dataset]}"
    else
        ratios="${DATASET_RATIOS[$dataset]}"
    fi
    
    for ratio in $ratios; do
        echo ""
        echo "--- Ratio: $ratio ---"
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
echo "TriBack-Clo Multi-Itemset Benchmark Runner"
echo "Timestamp: $TIMESTAMP"
echo "JVM Heap: -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX"
echo "Timeout: ${TIMEOUT_SEC}s"
echo "Trials: $WARMUP_RUNS warmup + $MEASURED_RUNS measured (median)"
echo "============================================================"

# Check prerequisites
if [ ! -f "$SCRIPT_DIR/../triback-clo-java/triback-clo.jar" ]; then
    echo "[ERROR] Java TriBack-Clo JAR not found"
    echo "        Run: ./triback-clo-java/build.sh"
    exit 1
fi

if [ ! -f "$SPMF_JAR" ]; then
    echo "[WARN] SPMF JAR not found: $SPMF_JAR"
    ALGORITHMS=("TriBack-Clo")
fi

init_csv

# Parse arguments
ARG1="${1:-all}"
ARG2="${2:-full}"
ARG3="${3:-all}"

MODE="full"
ALGO_FILTER="all"
TARGET="all"

# Detect argument types
for arg in "$ARG1" "$ARG2" "$ARG3"; do
    case "$arg" in
        quick|full) MODE="$arg" ;;
        triback|TriBack-Clo) ALGO_FILTER="triback" ;;
        spmf) ALGO_FILTER="spmf" ;;
        D10|D20|D50|D5|all) TARGET="$arg" ;;
        D10C*|D20C*|D50T*|D5N*) TARGET="$arg" ;;
    esac
done

# Filter algorithms
case "$ALGO_FILTER" in
    triback) ALGORITHMS=("TriBack-Clo"); echo "[INFO] Running only TriBack-Clo" ;;
    spmf) ALGORITHMS=("BIDE+" "ClaSP" "CloSpan"); echo "[INFO] Running only SPMF algorithms" ;;
esac

# Run datasets
case "$TARGET" in
    all)
        for ds in D10C20 D10C30 D10C40 D10C50 D10C60 D10C70 D10C80 \
                  D20C20 D20C30 D20C40 D20C50 D20C60 D20C70 D20C80 \
                  D50T10 D50T20 D50T30 D50T40 \
                  D5N1 D5N1.6 D5N2.5; do
            run_dataset "$ds" "$MODE"
        done
        ;;
    D10)
        for ds in D10C20 D10C30 D10C40 D10C50 D10C60 D10C70 D10C80; do
            run_dataset "$ds" "$MODE"
        done
        ;;
    D20)
        for ds in D20C20 D20C30 D20C40 D20C50 D20C60 D20C70 D20C80; do
            run_dataset "$ds" "$MODE"
        done
        ;;
    D50)
        for ds in D50T10 D50T20 D50T30 D50T40; do
            run_dataset "$ds" "$MODE"
        done
        ;;
    D5)
        for ds in D5N1 D5N1.6 D5N2.5; do
            run_dataset "$ds" "$MODE"
        done
        ;;
    *)
        run_dataset "$TARGET" "$MODE"
        ;;
esac

echo ""
echo "============================================================"
echo "BENCHMARK COMPLETE"
echo "Results saved to: $CSV_FILE"
echo "============================================================"
