#!/usr/bin/env bash
#
# TriBack-Clo lazy-vs-eager exact-verification diagnostic ablation
# =================================================================
#
# Purpose:
#   Compare the default lazy exact-verification pipeline against the
#   eager-before-gating diagnostic variant (--eager-verify).
#
# Variants:
#   - Lazy/default: exact verification runs after same-support forward screening
#     and node gating.
#   - Eager-before-gating: exact verification runs before node gating for every
#     forward-closed, non-pruned node.
#
# Recommended experiment set:
#   1) D5N1 @ 0.4%    : gate-heavy, main case
#   2) D20C20 @ 0.1%  : secondary case with meaningful gating
#   3) D20C60 @ 1.0%  : near-neutral/control case
#   4) D20C30 @ 0.1%  : optional expensive gate-heavy case
#
# Protocol:
#   1 warm-up + 3 measured runs per dataset/variant.
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Adjust these paths if your directory layout differs.
BUILD_DIR="$SCRIPT_DIR/../triback-clo-java/build"
SPMF_JAR="$SCRIPT_DIR/spmf.jar"
CLASSPATH="$SPMF_JAR:$BUILD_DIR"

DATASETS_DIR="$SCRIPT_DIR/datasets/synthetic/clofast_paper"
RESULTS_DIR="$SCRIPT_DIR/results"
LOGS_DIR="$SCRIPT_DIR/logs_eager_verify"

JVM_HEAP_START="16g"
JVM_HEAP_MAX="80g"
TIMEOUT_SEC=7200

WARMUP_RUNS=1
MEASURED_RUNS=3

# Set RUN_EXPENSIVE=1 to include D20C30 @ 0.1%.
RUN_EXPENSIVE="${RUN_EXPENSIVE:-0}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/eager_verification_ablation_${TIMESTAMP}.csv"

# Dataset files.
declare -A DATASET_FILES
DATASET_FILES["D5N1"]="D5C10T10N1S6I4.txt"
DATASET_FILES["D20C20"]="D20C20T2.5N10S10I1.25.txt"
DATASET_FILES["D20C60"]="D20C60T2.5N10S10I1.25.txt"
DATASET_FILES["D20C30"]="D20C30T2.5N10S10I1.25.txt"

# Ratios as fractions, not percentages.
declare -A DATASET_RATIOS
DATASET_RATIOS["D5N1"]="0.004"
DATASET_RATIOS["D20C20"]="0.001"
DATASET_RATIOS["D20C60"]="0.01"
DATASET_RATIOS["D20C30"]="0.001"

init_csv() {
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    echo "timestamp,dataset,ratio,minsup_pct,variant,flags,wall_sec,mining_sec,cpu_pct,maxrss_kb,maxrss_mb,patterns,nodes_visited,subtrees_pruned,nodes_gated,exact_verifier_calls,eager_wasted_verifier_calls,status,run_type,log_file" > "$CSV_FILE"
    echo "[INIT] Results: $CSV_FILE"
    echo "[INIT] Logs:    $LOGS_DIR"
}

get_median() {
    if [ "$#" -eq 0 ]; then
        echo "0"
        return
    fi
    printf "%s\n" "$@" | LC_ALL=C sort -n | awk '{a[NR]=$1} END{if(NR==0){print 0}else if(NR%2==1){print a[(NR+1)/2]}else{print (a[NR/2]+a[NR/2+1])/2}}'
}

extract_stat_colon() {
    local pattern="$1"
    local file="$2"
    awk -F: -v pat="$pattern" '$0 ~ pat {gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/[^0-9.]/, "", $2); print $2; exit}' "$file"
}

run_once() {
    local dataset="$1"
    local dataset_file="$2"
    local ratio="$3"
    local variant="$4"
    local flags="$5"
    local run_id="$6"

    local safe_ratio
    safe_ratio=$(awk -v r="$ratio" 'BEGIN {gsub(/\./,"p",r); print r}')
    local log_file="$LOGS_DIR/${variant}_${dataset}_${safe_ratio}_${run_id}_${TIMESTAMP}.log"
    local time_file="/tmp/time_eager_verify_${dataset}_${variant}_${run_id}_$$.txt"

    local num_seqs minsup_abs minsup_pct
    num_seqs=$(wc -l < "$dataset_file")
    minsup_abs=$(awk -v r="$ratio" -v n="$num_seqs" 'BEGIN {x=r*n; i=int(x); print (x>i)?i+1:i}')
    minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.6f", r * 100}')

    ( /usr/bin/time -f "%e %P %M" -o "$time_file" \
        timeout --signal=TERM --kill-after=10s "$TIMEOUT_SEC" \
        java -Xms"$JVM_HEAP_START" -Xmx"$JVM_HEAP_MAX" -cp "$CLASSPATH" \
        ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
        "$dataset_file" "/dev/null" "$minsup_abs" $flags ) > "$log_file" 2>&1

    local exit_code=$?

    local wall_sec="0" cpu_pct="0" maxrss_kb="0"
    if [ -f "$time_file" ]; then
        read wall_sec cpu_pct maxrss_kb < <(awk '{gsub(/%/,"",$2); print $1, $2, $3}' "$time_file")
        rm -f "$time_file"
    fi

    local status="OK"
    if [ "${exit_code:-0}" -eq 124 ] || [ "${exit_code:-0}" -eq 137 ]; then
        status="TIMEOUT"
        wall_sec="$TIMEOUT_SEC"
    elif [ "${exit_code:-0}" -ne 0 ]; then
        status="ERROR"
    fi

    local mining_sec patterns nodes_visited subtrees_pruned nodes_gated verifier_calls wasted_calls maxrss_mb
    mining_sec=$(awk '/Total time ~/ {for(i=1;i<=NF;i++) if($i=="~"){gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000; exit}}' "$log_file")
    patterns=$(extract_stat_colon "Pattern count" "$log_file")
    nodes_visited=$(extract_stat_colon "Nodes visited" "$log_file")
    subtrees_pruned=$(extract_stat_colon "Subtrees pruned" "$log_file")
    nodes_gated=$(extract_stat_colon "Nodes gated" "$log_file")
    verifier_calls=$(extract_stat_colon "Exact verifier calls" "$log_file")
    wasted_calls=$(extract_stat_colon "Eager wasted verifier calls" "$log_file")

    [ -z "$mining_sec" ] && mining_sec="$wall_sec"
    [ -z "$patterns" ] && patterns="0"
    [ -z "$nodes_visited" ] && nodes_visited="0"
    [ -z "$subtrees_pruned" ] && subtrees_pruned="0"
    [ -z "$nodes_gated" ] && nodes_gated="0"
    [ -z "$verifier_calls" ] && verifier_calls="0"
    [ -z "$wasted_calls" ] && wasted_calls="0"
    maxrss_mb=$(awk -v r="$maxrss_kb" 'BEGIN {printf "%.0f", r/1024}')

    echo "$wall_sec $mining_sec $cpu_pct $maxrss_kb $maxrss_mb $patterns $nodes_visited $subtrees_pruned $nodes_gated $verifier_calls $wasted_calls $status $log_file"
}

run_trials() {
    local dataset="$1"
    local dataset_file="$2"
    local ratio="$3"
    local variant="$4"
    local flags="$5"

    local minsup_pct
    minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.4f", r * 100}')
    echo -n "  $variant @ ${minsup_pct}%:"

    for w in $(seq 1 "$WARMUP_RUNS"); do
        echo -n " warmup$w..."
        run_once "$dataset" "$dataset_file" "$ratio" "$variant" "$flags" "warmup$w" > /dev/null
    done

    local walls=() mining_vals=() cpu_vals=() rss_vals=() rss_mb_vals=()
    local patterns_vals=() nodes_vals=() pruned_vals=() gated_vals=() verifier_vals=() wasted_vals=()
    local last_status="OK"
    local last_log=""

    for i in $(seq 1 "$MEASURED_RUNS"); do
        echo -n " run$i..."
        local result
        result=$(run_once "$dataset" "$dataset_file" "$ratio" "$variant" "$flags" "$i")

        walls+=("$(echo "$result" | awk '{print $1}')")
        mining_vals+=("$(echo "$result" | awk '{print $2}')")
        cpu_vals+=("$(echo "$result" | awk '{print $3}')")
        rss_vals+=("$(echo "$result" | awk '{print $4}')")
        rss_mb_vals+=("$(echo "$result" | awk '{print $5}')")
        patterns_vals+=("$(echo "$result" | awk '{print $6}')")
        nodes_vals+=("$(echo "$result" | awk '{print $7}')")
        pruned_vals+=("$(echo "$result" | awk '{print $8}')")
        gated_vals+=("$(echo "$result" | awk '{print $9}')")
        verifier_vals+=("$(echo "$result" | awk '{print $10}')")
        wasted_vals+=("$(echo "$result" | awk '{print $11}')")
        last_status=$(echo "$result" | awk '{print $12}')
        last_log=$(echo "$result" | awk '{print $13}')

        if [ "$last_status" != "OK" ]; then
            break
        fi
    done

    local n=${#walls[@]}
    local med_wall med_mining med_cpu med_rss med_rss_mb med_patterns med_nodes med_pruned med_gated med_verifier med_wasted
    med_wall=$(get_median "${walls[@]}")
    med_mining=$(get_median "${mining_vals[@]}")
    med_cpu=$(get_median "${cpu_vals[@]}")
    med_rss=$(get_median "${rss_vals[@]}")
    med_rss_mb=$(get_median "${rss_mb_vals[@]}")
    med_patterns=$(get_median "${patterns_vals[@]}")
    med_nodes=$(get_median "${nodes_vals[@]}")
    med_pruned=$(get_median "${pruned_vals[@]}")
    med_gated=$(get_median "${gated_vals[@]}")
    med_verifier=$(get_median "${verifier_vals[@]}")
    med_wasted=$(get_median "${wasted_vals[@]}")

    echo " done ($last_status, wall=${med_wall}s, mining=${med_mining}s, mem=${med_rss_mb}MB, patterns=${med_patterns}, verifier=${med_verifier}, gated=${med_gated})"

    echo "$(date +%Y-%m-%d_%H:%M:%S),$dataset,$ratio,$minsup_pct,$variant,\"$flags\",$med_wall,$med_mining,$med_cpu,$med_rss,$med_rss_mb,$med_patterns,$med_nodes,$med_pruned,$med_gated,$med_verifier,$med_wasted,$last_status,median_of_${n},$last_log" >> "$CSV_FILE"
}

run_dataset() {
    local dataset="$1"
    local ratio="${DATASET_RATIOS[$dataset]}"
    local dataset_file="$DATASETS_DIR/${DATASET_FILES[$dataset]}"

    echo
    echo "============================================================"
    echo "DATASET: $dataset | ratio=$ratio | file=${DATASET_FILES[$dataset]}"
    echo "============================================================"

    if [ ! -f "$dataset_file" ]; then
        echo "[SKIP] File not found: $dataset_file"
        return
    fi

    run_trials "$dataset" "$dataset_file" "$ratio" "LazyDefault" ""
    run_trials "$dataset" "$dataset_file" "$ratio" "EagerBeforeGate" "--eager-verify"

    echo "[CHECK] Compare the two rows for $dataset: pattern count and nodes visited should match."
    echo "[CHECK] Expected: eager verifier calls - lazy verifier calls should be close to lazy/eager nodes gated."
}

echo "============================================================"
echo "TriBack-Clo lazy-vs-eager exact-verification ablation"
echo "============================================================"
echo "Classpath: $CLASSPATH"
echo "Datasets: $DATASETS_DIR"
echo "RUN_EXPENSIVE=$RUN_EXPENSIVE"

init_csv

run_dataset "D5N1"
run_dataset "D20C20"
run_dataset "D20C60"

if [ "$RUN_EXPENSIVE" = "1" ]; then
    run_dataset "D20C30"
else
    echo
    echo "[INFO] Skipping D20C30 @ 0.1% by default because it is expensive."
    echo "[INFO] To include it, run: RUN_EXPENSIVE=1 $0"
fi

echo
echo "============================================================"
echo "COMPLETE"
echo "Results: $CSV_FILE"
echo "============================================================"
