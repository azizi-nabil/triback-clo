#!/bin/bash
#
# Generate per-dataset CSV files from benchmark logs
# Computes mean values across run1, run2, run3 for each algorithm/ratio combination
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"
RESULTS_DIR="$SCRIPT_DIR/results"

mkdir -p "$RESULTS_DIR"

# Get unique datasets from log files
datasets=$(ls "$LOGS_DIR"/*.log 2>/dev/null | xargs -n1 basename | sed 's/^[^_]*_//' | sed 's/_[0-9].*$//' | sort -u)

echo "Found datasets: $datasets"
echo ""

# Function to parse a single log file and extract metrics
parse_log() {
    local log_file="$1"
    local algo="$2"
    
    if [ "$algo" = "TriBack-Clo" ]; then
        # TriBack-Clo format
        mining_sec=$(grep -E "Mining completed in|Mining:" "$log_file" 2>/dev/null | head -1 | awk '{print $(NF-1)}')
        patterns=$(grep -i "Closed patterns found" "$log_file" 2>/dev/null | awk -F: '{gsub(/[^0-9]/,"",$2); print $2}')
        wall_sec=$(grep "Wall time:" "$log_file" 2>/dev/null | awk -F'Wall time: ' '{print $2}' | awk '{print $1}')
        maxrss=$(grep "MaxRSS:" "$log_file" 2>/dev/null | awk -F'MaxRSS: ' '{print $2}' | awk '{print $1}')
    else
        # SPMF format (BIDE+, ClaSP, CloSpan)
        mining_ms=$(grep "Total time ~" "$log_file" 2>/dev/null | awk '{print $4}')
        mining_sec=$(awk -v ms="$mining_ms" 'BEGIN {if(ms=="") print ""; else printf "%.3f", ms/1000}')
        patterns=$(grep "Pattern count" "$log_file" 2>/dev/null | awk -F: '{gsub(/[^0-9]/,"",$2); print $2}')
        [ -z "$patterns" ] && patterns=$(grep "sequences count" "$log_file" 2>/dev/null | awk -F: '{gsub(/[^0-9]/,"",$2); print $2}')
        wall_sec=$(grep "Wall time:" "$log_file" 2>/dev/null | awk -F'Wall time: ' '{print $2}' | awk '{print $1}')
        maxrss=$(grep "MaxRSS:" "$log_file" 2>/dev/null | awk -F'MaxRSS: ' '{print $2}' | awk '{print $1}')
    fi
    
    # Return values (space-separated)
    echo "$wall_sec $mining_sec $patterns $maxrss"
}

for dataset in $datasets; do
    csv_file="$RESULTS_DIR/${dataset}_results.csv"
    echo "Generating $csv_file..."
    
    # Header
    echo "algorithm,ratio,minsup_pct,wall_sec_mean,mining_sec_mean,patterns,maxrss_kb_mean,n_runs,status" > "$csv_file"
    
    # Process each algorithm
    for algo in TriBack-Clo BIDE+ ClaSP CloSpan; do
        # Find unique ratios for this dataset/algorithm
        ratios=$(ls "$LOGS_DIR"/${algo}_${dataset}_*_run1_*.log 2>/dev/null | xargs -n1 basename 2>/dev/null | sed "s/${algo}_${dataset}_//" | sed 's/_run.*//' | sort -u)
        
        for ratio in $ratios; do
            # Find all run files (run1, run2, run3) for this combination
            wall_sum=0
            mining_sum=0
            maxrss_sum=0
            n_runs=0
            patterns=""
            status="OK"
            
            for run in run1 run2 run3; do
                log_file=$(ls "$LOGS_DIR"/${algo}_${dataset}_${ratio}_${run}_*.log 2>/dev/null | head -1)
                [ -f "$log_file" ] || continue
                
                # Parse log file
                result=$(parse_log "$log_file" "$algo")
                read wall_sec mining_sec pat maxrss <<< "$result"
                
                # Check for valid numeric values
                if [[ "$wall_sec" =~ ^[0-9.]+$ ]] && [[ "$mining_sec" =~ ^[0-9.]+$ ]]; then
                    wall_sum=$(awk -v a="$wall_sum" -v b="$wall_sec" 'BEGIN {printf "%.3f", a+b}')
                    mining_sum=$(awk -v a="$mining_sum" -v b="$mining_sec" 'BEGIN {printf "%.3f", a+b}')
                    if [[ "$maxrss" =~ ^[0-9]+$ ]]; then
                        maxrss_sum=$((maxrss_sum + maxrss))
                    fi
                    n_runs=$((n_runs + 1))
                    [ -z "$patterns" ] && patterns="$pat"
                else
                    # Check for timeout/error
                    if grep -q "TIMEOUT\|timeout\|Killed" "$log_file" 2>/dev/null; then
                        status="TIMEOUT"
                    elif [ -z "$patterns" ]; then
                        status="ERROR"
                    fi
                fi
            done
            
            # Calculate means
            if [ $n_runs -gt 0 ]; then
                wall_mean=$(awk -v sum="$wall_sum" -v n="$n_runs" 'BEGIN {printf "%.3f", sum/n}')
                mining_mean=$(awk -v sum="$mining_sum" -v n="$n_runs" 'BEGIN {printf "%.3f", sum/n}')
                maxrss_mean=$((maxrss_sum / n_runs))
                status="OK"
            else
                wall_mean="N/A"
                mining_mean="N/A"
                maxrss_mean="N/A"
            fi
            
            # Default patterns
            [ -z "$patterns" ] && patterns="0"
            
            # Calculate minsup percentage
            minsup_pct=$(awk -v r="$ratio" 'BEGIN {printf "%.4f", r * 100}')
            
            echo "$algo,$ratio,$minsup_pct,$wall_mean,$mining_mean,$patterns,$maxrss_mean,$n_runs,$status" >> "$csv_file"
        done
    done
    
    # Sort by ratio (numeric)
    head -1 "$csv_file" > "${csv_file}.tmp"
    tail -n +2 "$csv_file" | sort -t, -k2 -n >> "${csv_file}.tmp"
    mv "${csv_file}.tmp" "$csv_file"
    
    echo "  Created: $csv_file ($(wc -l < "$csv_file") rows)"
done

echo ""
echo "Done! CSV files created in $RESULTS_DIR/"
ls -la "$RESULTS_DIR"/*.csv
