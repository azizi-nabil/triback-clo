#!/bin/bash
#
# Benchmark D-varying scalability datasets (CloFast Section 7.4)
# Fixed: C=20, T=20, N=2.5, S=6, I=4, min_sup=0.4 (40%)
# Vary: D = {50k, 100k, 150k, 200k, 250k, 300k}
#

# Remove 'set -e' to continue on errors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
SPMF_JAR="$PROJECT_DIR/experiments/spmf.jar"
TRIBACK_CLASSPATH="$PROJECT_DIR/triback-clo-java/triback-clo.jar:$SPMF_JAR"
DATASET_DIR="$PROJECT_DIR/experiments/datasets/synthetic/clofast_paper"
LOGS_DIR="$PROJECT_DIR/experiments/logs_scalability_D"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Fixed support: 30%
RATIO="0.3"

# JVM settings
JVM_HEAP_MAX="70g"
JVM_HEAP_START="4g"

# Timeout (1 hour)
TIMEOUT_SEC=3600

# Number of runs
WARMUP_RUNS=1
MEASURED_RUNS=3
ALGORITHMS_FILTER=""

usage() {
    cat <<'EOF'
Usage: ./run_benchmark_scalability_D.sh [options]

Options:
  --algorithms TriBack-Clo-Java|BIDE+|CloFast|ClaSP|CloSpan[, ...]
      run only the selected algorithm subset for each D point

  --help
      show this help and exit
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --algorithms)
            ALGORITHMS_FILTER="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

declare -a ALGORITHMS=(
    "TriBack-Clo-Java"
    "BIDE+"
    "CloFast"
    "ClaSP"
    "CloSpan"
)

if [ -n "$ALGORITHMS_FILTER" ]; then
    OLD_IFS="$IFS"
    IFS=',' read -r -a REQUESTED_ALGORITHMS <<< "$ALGORITHMS_FILTER"
    IFS="$OLD_IFS"

    ALGORITHMS=()
    for algo in "${REQUESTED_ALGORITHMS[@]}"; do
        case "$algo" in
            TriBack-Clo-Java|BIDE+|CloFast|ClaSP|CloSpan)
                ALGORITHMS+=("$algo")
                ;;
            *)
                echo "[ERROR] Invalid algorithm in --algorithms: $algo" >&2
                usage
                exit 1
                ;;
        esac
    done
fi

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
echo "D-VARYING SCALABILITY BENCHMARK (Section 7.4)"
echo "Varying D (50k to 300k), Fixed support: 30%"
if [ -n "$ALGORITHMS_FILTER" ]; then
    echo "Algorithms: ${ALGORITHMS[*]}"
else
    echo "Algorithms: ${ALGORITHMS[*]}"
fi
echo "Timestamp: $TIMESTAMP"
echo "=============================================="

mkdir -p "$LOGS_DIR"

# D values (in thousands)
D_VALUES=(50 100 150 200 250 300)

for D in "${D_VALUES[@]}"; do
    dataset="D${D}C20T20N2.5S6I4"
    dataset_file="$DATASET_DIR/${dataset}.txt"
    
    if [[ ! -f "$dataset_file" ]]; then
        echo "[SKIP] Dataset not found: $dataset_file"
        continue
    fi
    
    echo ""
    echo "=============================================="
    echo "DATASET: $dataset (D=${D}k sequences)"
    echo "=============================================="
    
    for algo in "${ALGORITHMS[@]}"; do
        echo -n "  $algo: "
        
        # Warmup
        for w in $(seq 1 $WARMUP_RUNS); do
            echo -n "warmup$w... "
            log_file="$LOGS_DIR/${algo}_${dataset}_${RATIO}_runwarmup${w}_${TIMESTAMP}.log"
            run_single "$algo" "$dataset_file" "$RATIO" "$log_file" > /dev/null
        done
        
        # Measured runs
        wall_times=()
        mining_times=()
        maxrss_vals=()
        patterns_vals=()
        final_status="OK"
        
        for r in $(seq 1 $MEASURED_RUNS); do
            echo -n "run$r... "
            log_file="$LOGS_DIR/${algo}_${dataset}_${RATIO}_run${r}_${TIMESTAMP}.log"
            result=$(run_single "$algo" "$dataset_file" "$RATIO" "$log_file")
            
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

echo ""
echo "=============================================="
echo "BENCHMARK COMPLETE"
echo "Logs saved to: $LOGS_DIR"
echo "=============================================="
