#!/bin/bash
#
# Run D20 series benchmarks at LOW SUPPORT levels
# Shows detailed results (wall time, patterns, memory) after each run
#

# Removed 'set -e' to continue on errors (e.g., CloFast OOM)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
SPMF_JAR="$PROJECT_DIR/spmf.jar"
TRIBACK_JAR="$PROJECT_DIR/triback-clo-java/dist/triback-clo-java.jar"
TRIBACK_CLASSPATH="$PROJECT_DIR/triback-clo-java/build:$SPMF_JAR"
DATASET_DIR="$PROJECT_DIR/experiments/datasets/synthetic/clofast_paper"
LOGS_DIR="$PROJECT_DIR/experiments/logs_itemsets"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# D20 datasets
declare -A DATASET_FILES
DATASET_FILES["D20C20"]="D20C20T2.5N10S10I1.25.txt"
DATASET_FILES["D20C30"]="D20C30T2.5N10S10I1.25.txt"
DATASET_FILES["D20C40"]="D20C40T2.5N10S10I1.25.txt"
DATASET_FILES["D20C50"]="D20C50T2.5N10S10I1.25.txt"
DATASET_FILES["D20C60"]="D20C60T2.5N10S10I1.25.txt"
DATASET_FILES["D20C70"]="D20C70T2.5N10S10I1.25.txt"
DATASET_FILES["D20C80"]="D20C80T2.5N10S10I1.25.txt"

# Low support ratios (removed 0.1% - takes too long)
RATIOS=("0.01" "0.005")

# JVM settings
JVM_HEAP_MAX="70g"
JVM_HEAP_START="4g"

# Timeout (2 hours)
TIMEOUT_SEC=7200

# Number of runs
WARMUP_RUNS=1
MEASURED_RUNS=3

run_single() {
    local algo="$1"
    local dataset_file="$2"
    local ratio="$3"
    local log_file="$4"
    
    local time_file=$(mktemp)
    local exit_code=0
    local minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.4f", r * 100}')
    
    # Get sequence count for absolute minsup
    local seq_count=$(wc -l < "$dataset_file")
    local minsup_abs=$(awk -v s="$seq_count" -v r="$ratio" 'BEGIN {printf "%d", s * r}')
    
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
        (
            /usr/bin/time -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s $TIMEOUT_SEC \
                java -Xms$JVM_HEAP_START -Xmx$JVM_HEAP_MAX -jar "$SPMF_JAR" \
                run "$algo" "$dataset_file" "/dev/null" "${minsup_pct}%"
        ) > "$log_file" 2>&1
        exit_code=$?
        patterns=$(awk -F: '/Pattern count|sequences count/ {gsub(/[^0-9]/,"",$2); print $2}' "$log_file" 2>/dev/null | head -1)
        mining_sec=$(awk '/Total time ~/ { for(i=1;i<=NF;i++) if($i=="~") { gsub(/[^0-9]/,"",$(i+1)); printf "%.3f", $(i+1)/1000 } }' "$log_file" 2>/dev/null | head -1)
    fi
    
    local wall_sec="0" maxrss="0"
    if [ -f "$time_file" ]; then
        wall_sec=$(awk '{print $1}' "$time_file")
        maxrss=$(awk '{print $3}' "$time_file")
        rm -f "$time_file"
    fi
    
    local status="OK"
    if [ "${exit_code:-0}" -eq 124 ] || [ "${exit_code:-0}" -eq 137 ]; then
        status="TIMEOUT"; wall_sec=$TIMEOUT_SEC
    elif [ $exit_code -ne 0 ]; then
        status="ERROR"
    fi
    
    [ -z "$patterns" ] && patterns="0"
    [ -z "$mining_sec" ] && mining_sec="$wall_sec"
    
    # Output: wall_sec mining_sec maxrss patterns status
    echo "$wall_sec $mining_sec $maxrss $patterns $status"
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

echo "=============================================="
echo "D20 LOW SUPPORT BENCHMARK"
echo "Timestamp: $TIMESTAMP"
echo "Support levels: 1%, 0.5%"
echo "=============================================="

mkdir -p "$LOGS_DIR"

# Skip D20C20, D20C30, D20C40 (already completed) - only run remaining datasets
for dataset in D20C50 D20C60 D20C70 D20C80; do
    dataset_file="$DATASET_DIR/${DATASET_FILES[$dataset]}"
    
    if [[ ! -f "$dataset_file" ]]; then
        echo "[SKIP] Dataset not found: $dataset_file"
        continue
    fi
    
    echo ""
    echo "=============================================="
    echo "DATASET: $dataset"
    echo "=============================================="
    
    for ratio in "${RATIOS[@]}"; do
        minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.2f", r * 100}')
        echo ""
        echo "--- Support: ${minsup_pct}% ---"
        
        for algo in TriBack-Clo-Java BIDE+ CloFast ClaSP CloSpan; do
            echo -n "  $algo: "
            
            # Warmup
            for w in $(seq 1 $WARMUP_RUNS); do
                echo -n "warmup$w... "
                log_file="$LOGS_DIR/${algo}_${dataset}_${ratio}_runwarmup${w}_${TIMESTAMP}.log"
                run_single "$algo" "$dataset_file" "$ratio" "$log_file" > /dev/null
            done
            
            # Measured runs
            wall_times=()
            mining_times=()
            maxrss_vals=()
            patterns_vals=()
            final_status="OK"
            
            for r in $(seq 1 $MEASURED_RUNS); do
                echo -n "run$r... "
                log_file="$LOGS_DIR/${algo}_${dataset}_${ratio}_run${r}_${TIMESTAMP}.log"
                result=$(run_single "$algo" "$dataset_file" "$ratio" "$log_file")
                
                wall=$(echo "$result" | awk '{print $1}')
                mining=$(echo "$result" | awk '{print $2}')
                rss=$(echo "$result" | awk '{print $3}')
                pats=$(echo "$result" | awk '{print $4}')
                status=$(echo "$result" | awk '{print $5}')
                
                wall_times+=("$wall")
                mining_times+=("$mining")
                maxrss_vals+=("$rss")
                patterns_vals+=("$pats")
                
                if [ "$status" != "OK" ]; then
                    final_status="$status"
                fi
            done
            
            # Calculate medians
            med_wall=$(get_median "${wall_times[@]}")
            med_mining=$(get_median "${mining_times[@]}")
            med_rss=$(get_median "${maxrss_vals[@]}")
            med_patterns=$(get_median "${patterns_vals[@]}")
            
            # Format memory
            mem_gb=$(awk -v m="$med_rss" 'BEGIN {printf "%.2f", m/1024/1024}')
            
            echo "done ($final_status, wall=${med_wall}s, mining=${med_mining}s, ${med_patterns} patterns, ${mem_gb}GB)"
        done
    done
done

echo ""
echo "=============================================="
echo "BENCHMARK COMPLETE"
echo "Logs saved to: $LOGS_DIR"
echo "=============================================="
