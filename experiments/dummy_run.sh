#!/bin/bash
# dummy_run.sh
mkdir -p results logs_test

MANIFEST="results/configuration_manifest.csv"
echo "dataset,minsup,algorithm,run_type,run_id,expected_output_equivalent_group,log_path" > "$MANIFEST"

# Function to create a dummy log
create_log() {
    local ds=$1 min=$2 algo=$3 type=$4 id=$5 group=$6 path=$7 wall=$8 mem=$9 pats=${10} status=${11}
    echo "dataset:${ds} algorithm:${algo}" > "$path"
    echo "Total time ~ $(echo "$wall * 1000" | bc | cut -d. -f1) ms" >> "$path"
    echo "[RESOURCE] Wall time: ${wall} sec | CPU: 100% | MaxRSS: $(echo "$mem * 1024" | bc | cut -d. -f1) KB" >> "$path"
    echo "Pattern count : ${pats}" >> "$path"
    if [ "$status" != "OK" ]; then
        echo "Status: ${status}" >> "$path"
    fi
    echo "${ds},${min},${algo},${type},${id},${group},${path}" >> "$MANIFEST"
}

# Kosarak 0.1% group (OK)
create_log "Kosarak" "0.1%" "TriBack-Clo" "measured" "1" "Kosarak_0.1_group" "logs_test/K_T_1.log" 541.93 1810 529948 "OK"
create_log "Kosarak" "0.1%" "TriBack-Clo" "measured" "2" "Kosarak_0.1_group" "logs_test/K_T_2.log" 542.41 1815 529948 "OK"
create_log "Kosarak" "0.1%" "TriBack-Clo" "measured" "3" "Kosarak_0.1_group" "logs_test/K_T_3.log" 543.00 1812 529948 "OK"

create_log "Kosarak" "0.1%" "BIDE+" "measured" "1" "Kosarak_0.1_group" "logs_test/K_B_1.log" 6101.3 10880 529948 "OK"
create_log "Kosarak" "0.1%" "BIDE+" "measured" "2" "Kosarak_0.1_group" "logs_test/K_B_2.log" 6105.1 10890 529948 "OK"
create_log "Kosarak" "0.1%" "BIDE+" "measured" "3" "Kosarak_0.1_group" "logs_test/K_B_3.log" 6103.2 10885 529948 "OK"

# D10C80 (Non-equivalent)
create_log "D10C80" "40%" "TriBack-Clo" "measured" "1" "D10C80_group" "logs_test/D_T_1.log" 10.0 500 100 "OK"
create_log "D10C80" "40%" "TriBack-Clo" "measured" "2" "D10C80_group" "logs_test/D_T_2.log" 10.1 505 100 "OK"
create_log "D10C80" "40%" "TriBack-Clo" "measured" "3" "D10C80_group" "logs_test/D_T_3.log" 10.2 502 100 "OK"

create_log "D10C80" "40%" "BIDE+" "measured" "1" "D10C80_group" "logs_test/D_B_1.log" 1.0 100 0 "OK"
create_log "D10C80" "40%" "BIDE+" "measured" "2" "D10C80_group" "logs_test/D_B_2.log" 1.1 105 0 "OK"
create_log "D10C80" "40%" "BIDE+" "measured" "3" "D10C80_group" "logs_test/D_B_3.log" 1.2 102 0 "OK"

# SIGN 1% (One timeout)
create_log "SIGN" "1%" "TriBack-Clo" "measured" "1" "SIGN_1_group" "logs_test/S_T_1.log" 287.5 1620 37265723 "OK"
create_log "SIGN" "1%" "TriBack-Clo" "measured" "2" "SIGN_1_group" "logs_test/S_T_2.log" 288.1 1625 37265723 "OK"
create_log "SIGN" "1%" "TriBack-Clo" "measured" "3" "SIGN_1_group" "logs_test/S_T_3.log" 287.8 1622 37265723 "OK"

create_log "SIGN" "1%" "BIDE+" "measured" "1" "SIGN_1_group" "logs_test/S_B_1.log" 3275.2 9710 37265723 "OK"
create_log "SIGN" "1%" "BIDE+" "measured" "2" "SIGN_1_group" "logs_test/S_B_2.log" 7200.0 9710 0 "TIMEOUT"
create_log "SIGN" "1%" "BIDE+" "measured" "3" "SIGN_1_group" "logs_test/S_B_3.log" 3277.5 9715 37265723 "OK"
