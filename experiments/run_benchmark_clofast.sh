#!/bin/bash
# Dedicated benchmark runner for CloFAST paper experiments
# Figure 10: Varying Sequence Length (C) on Sparse and Dense datasets

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------

TRIBACK_JAR="triback-clo-java/triback-clo.jar"
SPMF_JAR="experiments/spmf.jar"
RESULTS_DIR="experiments/results"
DATA_DIR="experiments/datasets/synthetic/clofast_paper"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CSV_FILE="$RESULTS_DIR/benchmark_clofast_fig10_$TIMESTAMP.csv"
TIMEOUT_SEC=1200 # 20 minutes timeout per run
JVM_HEAP="8g" # 8GB heap for dense datasets

# Algorithms to test: TriBack-Clo, BIDE+, ClaSP, and CloFAST
# Note: CloFAST is "CloFast" in SPMF command line (verified)
ALGORITHMS=("TriBack-Clo" "BIDE+" "ClaSP" "CloFast") 

# ---------------------------------------------------------
# SETUP
# ---------------------------------------------------------
mkdir -p "$RESULTS_DIR"
if [ ! -f "$TRIBACK_JAR" ]; then
    echo "Error: TriBack-Clo JAR not found at $TRIBACK_JAR"
    exit 1
fi
if [ ! -f "$SPMF_JAR" ]; then
    echo "Error: SPMF JAR not found at $SPMF_JAR"
    exit 1
fi

echo "timestamp,dataset,C,density_type,support,algorithm,time_sec,memory_mb,patterns,status" > "$CSV_FILE"
echo "Results will be written to: $CSV_FILE"

# ---------------------------------------------------------
# RUNNER FUNCTION
# ---------------------------------------------------------
run_test() {
    local dataset_name=$1
    local support=$2
    local density_type=$3 # "Sparse" or "Dense"
    local C_val=$4
    
    local file_path="$DATA_DIR/$dataset_name"
    
    if [ ! -f "$file_path" ]; then
        echo "Missing dataset: $file_path"
        return
    fi
    
    echo "----------------------------------------------------------------"
    echo "Benchmarking $dataset_name ($density_type C=$C_val) @ Sup=$support"
    echo "----------------------------------------------------------------"
    
    for algo in "${ALGORITHMS[@]}"; do
        echo -n "  Running $algo... "
        
        LOG_FILE="/tmp/bench_${algo}_${TIMESTAMP}.log"
        START_TIME=$(date +%s%N)
        
        # Run Algorithm
        if [ "$algo" == "TriBack-Clo" ]; then
             java -Xms -Xmx -cp ":" \
                ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
                "" /dev/null "" \
                > "$LOG_FILE" 2>&1 &
             PID=$!
        elif [ "$algo" == "BIDE+" ]; then
             java -Xms$JVM_HEAP -Xmx$JVM_HEAP -jar "$SPMF_JAR" run BIDE+ \
                "$file_path" /dev/null "$support" \
                > "$LOG_FILE" 2>&1 &
             PID=$!
        elif [ "$algo" == "ClaSP" ]; then
             java -Xms$JVM_HEAP -Xmx$JVM_HEAP -jar "$SPMF_JAR" run ClaSP \
                "$file_path" /dev/null "$support" \
                > "$LOG_FILE" 2>&1 &
             PID=$!
        elif [ "$algo" == "CloFast" ]; then
             # SPMF Algo name is CloFast
             java -Xms$JVM_HEAP -Xmx$JVM_HEAP -jar "$SPMF_JAR" run CloFast \
                "$file_path" /dev/null "$support" \
                > "$LOG_FILE" 2>&1 &
             PID=$!
        fi
        
        # Wait with timeout
        disown $PID 2>/dev/null 
        local waited=0
        local running=1
        while [ $running -eq 1 ]; do
            if ! kill -0 $PID 2>/dev/null; then
                running=0
            else
                sleep 1
                waited=$((waited + 1))
                if [ $waited -ge $TIMEOUT_SEC ]; then
                    kill -9 $PID 2>/dev/null
                    echo "TIMEOUT"
                    echo "$TIMESTAMP,$dataset_name,$C_val,$density_type,$support,$algo,${TIMEOUT_SEC},0,0,TIMEOUT" >> "$CSV_FILE"
                    running=0
                    continue 2 
                fi
            fi
        done
        
        END_TIME=$(date +%s%N)
        DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
        DURATION_SEC=$(echo "scale=3; $DURATION_MS / 1000" | bc)
        
        # Parse Output
        PATTERNS=0
        MEMORY=0
        
        if [ "$algo" == "TriBack-Clo" ]; then
            PATTERNS=$(grep "Closed patterns found:" "$LOG_FILE" | awk '{print $4}' | tr -d ',')
            MEMORY=$(grep "Peak memory:" "$LOG_FILE" | awk '{print $3}') 
        else
            # SPMF output check
            if [ "$algo" == "CloFast" ]; then
                 PATTERNS=$(grep "Frequent closed sequences count :" "$LOG_FILE"  | awk '{print $NF}')
            elif [ "$algo" == "ClaSP" ]; then
                 PATTERNS=$(grep "Frequent closed sequences count :" "$LOG_FILE"  | awk '{print $NF}')
            else
                 # BIDE+ sometimes says "Pattern count" or "Frequent sequences count"
                 PATTERNS=$(grep -E "(Pattern count|Frequent sequences count)" "$LOG_FILE" | head -1 | awk '{print $NF}')
            fi
            MEMORY=$(grep "Max memory (mb)" "$LOG_FILE" | awk '{print $5}')
        fi
        
        # Validate
        if [ -z "$PATTERNS" ]; then PATTERNS=0; fi
        if [ -z "$MEMORY" ]; then MEMORY=0; fi
        
        echo "Done! Time: ${DURATION_SEC}s, Mem: ${MEMORY}MB, Pats: $PATTERNS"
        echo "$TIMESTAMP,$dataset_name,$C_val,$density_type,$support,$algo,$DURATION_SEC,$MEMORY,$PATTERNS,SUCCESS" >> "$CSV_FILE"
    done
}

# ---------------------------------------------------------
# EXECUTION (Figure 10)
# ---------------------------------------------------------

echo "=== Dense Series (D10, T20, N5, S6, I4) - Support 40% ==="
# Varying C
for C in 20 30 40 50 60 70 80; do
    fn="D10C${C}T20N5S6I4.txt"
    run_test "$fn" "0.4" "Dense" "$C"
done

echo ""
echo "=== Sparse Series (D20, T2.5, N10, S10, I1.25) - Support 5% ==="
# Varying C
for C in 20 30 40 50 60 70 80; do
    fn="D20C${C}T2.5N10S10I1.25.txt"
    run_test "$fn" "0.05" "Sparse" "$C"
done

echo ""
echo "Benchmark complete. Results: $CSV_FILE"
