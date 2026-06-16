#!/bin/bash
#
# TriBack-Clo D5 Series - CloFAST Figure 8 Ratios
# ================================================
#
# Supplements the continuation benchmark with higher support thresholds
# matching CloFAST paper Figure 8: 10%, 8%, 7%, 6%, 5%, 4%, 3%
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIBACK_CLASSPATH="$SCRIPT_DIR/../triback-clo-java/triback-clo.jar:$SCRIPT_DIR/spmf.jar"
SPMF_JAR="$SCRIPT_DIR/spmf.jar"
DATASETS_DIR="$SCRIPT_DIR/datasets/synthetic/clofast_paper"
RESULTS_DIR="$SCRIPT_DIR/results"
LOGS_DIR="$SCRIPT_DIR/logs_itemsets"

JVM_HEAP_START="16g"
JVM_HEAP_MAX="90g"
TIMEOUT_SEC=7200

WARMUP_RUNS=1
MEASURED_RUNS=3

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/benchmark_d5_fig8_${TIMESTAMP}.csv"

declare -A DATASET_FILES
DATASET_FILES["D5N1"]="D5C10T10N1S6I4.txt"
DATASET_FILES["D5N1.6"]="D5C10T10N1.6S6I4.txt"
DATASET_FILES["D5N2.5"]="D5C10T10N2.5S6I4.txt"

# CloFAST Figure 8 ratios (higher support thresholds)
declare -A DATASET_RATIOS
DATASET_RATIOS["D5N1"]="0.1 0.08 0.07 0.06 0.05 0.04 0.03"
DATASET_RATIOS["D5N1.6"]="0.1 0.08 0.07 0.06 0.05 0.04 0.03"
DATASET_RATIOS["D5N2.5"]="0.1 0.08 0.07 0.06 0.05 0.04 0.03"

init_csv() {
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    echo "timestamp,dataset,ratio,minsup_pct,algorithm,wall_sec,mining_sec,cpu_pct,maxrss_kb,patterns,status,run_type" > "$CSV_FILE"
    echo "[INIT] Results: $CSV_FILE"
}

run_once() {
    local algo="$1" dataset="$2" dataset_file="$3" ratio="$4" run_id="$5"
    local log_file="$LOGS_DIR/${algo}_${dataset}_${ratio}_run${run_id}_${TIMESTAMP}.log"
    local time_file="/tmp/time_output_${run_id}_$$.txt"
    local minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.6f", r * 100}')
    local num_seqs=$(wc -l < "$dataset_file")
    local minsup_abs=$(awk -v r="$ratio" -v n="$num_seqs" 'BEGIN {x=r*n; i=int(x); print (x>i)?i+1:i}')

    if [ "$algo" = "TriBack-Clo-Java" ]; then
        ( /usr/bin/time -f "%e %P %M" -o "$time_file" \
            timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
            java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX -cp "$TRIBACK_CLASSPATH" \
            ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
            "$dataset_file" "/dev/null" "$minsup_abs" ) > "$log_file" 2>&1
        exit_code=$?
        patterns=$(awk -F: '/Pattern count/ {gsub(/[^0-9]/,"",$2); print $2}' "$log_file" | head -1)
        mining_sec=$(awk '/Total time ~/ { for(i=1;i<=NF;i++) if($i=="~") { gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000 } }' "$log_file" | head -1)
    else
        ( /usr/bin/time -f "%e %P %M" -o "$time_file" \
            timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
            java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX -jar "$SPMF_JAR" \
            run "$algo" "$dataset_file" "/dev/null" "${minsup_pct}%" ) > "$log_file" 2>&1
        exit_code=$?
        patterns=$(awk -F: '/Pattern count|sequences count/ {gsub(/[^0-9]/,"",$2); print $2}' "$log_file" | head -1)
        mining_sec=$(awk '/Total time ~/ { for(i=1;i<=NF;i++) if($i=="~") { gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000 } }' "$log_file" | head -1)
    fi

    if [ -f "$time_file" ]; then
        read wall_sec cpu_pct maxrss <<< $(cat "$time_file" | awk '{gsub(/%/,"",$2); print $1, $2, $3}')
        rm -f "$time_file"
    else
        wall_sec="0"; cpu_pct="0"; maxrss="0"
    fi

    local status="OK"
    [ "${exit_code:-0}" -eq 124 ] || [ "${exit_code:-0}" -eq 137 ] && { status="TIMEOUT"; wall_sec=$TIMEOUT_SEC; }
    [ $exit_code -ne 0 ] && [ "$status" = "OK" ] && status="ERROR"
    [ -z "$patterns" ] && patterns="0"
    [ -z "$mining_sec" ] && mining_sec="$wall_sec"
    
    echo "$wall_sec $mining_sec $cpu_pct $maxrss $patterns $status"
}

get_median() {
    printf "%s\n" "$@" | LC_ALL=C sort -n | awk '{a[NR]=$1} END{if(NR==0){print 0}else if(NR%2==1){print a[(NR+1)/2]}else{print (a[NR/2]+a[NR/2+1])/2}}'
}

run_trials() {
    local algo="$1" dataset="$2" dataset_file="$3" ratio="$4"
    local minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.4f", r * 100}')
    echo -n "  $algo @ ${minsup_pct}%: "
    
    for w in $(seq 1 $WARMUP_RUNS); do echo -n " warmup$w..."; run_once "$algo" "$dataset" "$dataset_file" "$ratio" "warmup$w" > /dev/null; done
    
    local walls=() mining_vals=() maxrss_vals=() cpu_vals=() patterns_ref="" last_status="OK"
    for i in $(seq 1 $MEASURED_RUNS); do
        echo -n " run$i..."
        local result=$(run_once "$algo" "$dataset" "$dataset_file" "$ratio" "$i")
        walls+=($(echo "$result" | awk '{print $1}'))
        mining_vals+=($(echo "$result" | awk '{print $2}'))
        cpu_vals+=($(echo "$result" | awk '{print $3}'))
        maxrss_vals+=($(echo "$result" | awk '{print $4}'))
        [ -z "$patterns_ref" ] && patterns_ref=$(echo "$result" | awk '{print $5}')
        local s=$(echo "$result" | awk '{print $6}')
        [ "$s" != "OK" ] && { last_status="$s"; break; }
    done
    
    local n=${#walls[@]}
    local median_wall=$(get_median "${walls[@]}") median_mining=$(get_median "${mining_vals[@]}")
    local median_rss=$(get_median "${maxrss_vals[@]}") median_cpu=$(get_median "${cpu_vals[@]}")
    local mem_mb=$(awk -v r="$median_rss" 'BEGIN {printf "%.0f", r/1024}')
    
    echo " done ($last_status, wall=${median_wall}s, mining=${median_mining}s, mem=${mem_mb}MB, ${patterns_ref:-0} patterns)"
    echo "$(date +%Y-%m-%d_%H:%M:%S),$dataset,$ratio,$minsup_pct,$algo,$median_wall,$median_mining,$median_cpu,$median_rss,${patterns_ref:-0},$last_status,median_of_${n}" >> "$CSV_FILE"
}

run_dataset() {
    local dataset="$1" algos="$2"
    echo -e "\n============================================================"
    echo "DATASET: $dataset (CloFAST Fig 8 ratios)"
    echo "============================================================"
    
    local dataset_file="$DATASETS_DIR/${DATASET_FILES[$dataset]}"
    [ ! -f "$dataset_file" ] && { echo "[SKIP] File not found: $dataset_file"; return; }
    cat "$dataset_file" > /dev/null 2>&1
    
    for ratio in ${DATASET_RATIOS[$dataset]}; do
        echo -e "\n--- Ratio: $ratio ---"
        for algo in $algos; do run_trials "$algo" "$dataset" "$dataset_file" "$ratio"; done
    done
}

echo "============================================================"
echo "TriBack-Clo D5 Series - CloFAST Figure 8 Ratios"
echo "Ratios: 10%, 8%, 7%, 6%, 5%, 4%, 3%"
echo "============================================================"

init_csv
ALL_ALGOS="TriBack-Clo-Java BIDE+ CloFast ClaSP CloSpan"
run_dataset "D5N1" "$ALL_ALGOS"
run_dataset "D5N1.6" "$ALL_ALGOS"
run_dataset "D5N2.5" "$ALL_ALGOS"

echo -e "\n============================================================"
echo "COMPLETE. Results: $CSV_FILE"
echo "============================================================"
