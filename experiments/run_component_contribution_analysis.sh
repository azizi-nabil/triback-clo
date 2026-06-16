#!/bin/bash
#
# TriBack-Clo Component Contribution Analysis Runner
# ==================================================
#
# Reproduces and extends the ablation study for the manuscript section
# "Component Contribution Analysis".
#
# Features:
# - Warmup run + 3 measured runs by default
# - Full / quick modes
# - Paper / extended / journal / full workload profiles
# - Optional reuse of existing benchmark / ablation logs
# - Raw per-run CSV + aggregated summary CSV
# - Archived logs grouped under experiments/logs_ablation/<timestamp>/
#
# Usage:
#   ./run_component_contribution_analysis.sh
#   ./run_component_contribution_analysis.sh --profile paper
#   ./run_component_contribution_analysis.sh --profile journal --skip-existing
#   ./run_component_contribution_analysis.sh --profile extended --mode full
#   ./run_component_contribution_analysis.sh --profile full --mode quick
#   ./run_component_contribution_analysis.sh --profile full --skip-existing
#   ./run_component_contribution_analysis.sh --list

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TRIBACK_CLASSPATH="$PROJECT_DIR/triback-clo-java/triback-clo.jar:$SCRIPT_DIR/spmf.jar"
RESULTS_DIR="$SCRIPT_DIR/results"
LOGS_ROOT="$SCRIPT_DIR/logs_ablation"
SINGLE_DATASETS_DIR="$SCRIPT_DIR/datasets"
MULTI_DATASETS_DIR="$SCRIPT_DIR/datasets/synthetic/clofast_paper"

JVM_HEAP_START="16g"
JVM_HEAP_MAX="90g"
TIMEOUT_SEC=7200
WARMUP_RUNS=1
MEASURED_RUNS=3

PROFILE="journal"
MODE="full"
LIST_ONLY=0
SKIP_EXISTING=0
VARIANTS_FILTER=""

detect_time_binary() {
    local candidate

    for candidate in /usr/bin/time /bin/time "$(command -v gtime 2>/dev/null || true)"; do
        [ -n "$candidate" ] || continue
        [ -x "$candidate" ] || continue
        echo "$candidate"
        return 0
    done

    return 1
}

TIME_BIN="$(detect_time_binary || true)"

usage() {
    cat <<'EOF'
Usage: ./run_component_contribution_analysis.sh [options]

Options:
  --profile paper|extended|journal|full
      paper:    exact workloads used in the current manuscript section
      extended: paper profile + one stronger single-itemset and one stronger multi-itemset point
      journal:  recommended journal-strength core study with pruning-heavy and gating-heavy cases
      full:     journal profile + broader confirmation cases across single- and multi-itemset regimes

  --mode quick|full
      quick: no warmup, 1 measured run
      full:  1 warmup + 3 measured runs

  --skip-existing
      reuse matching existing logs when available instead of rerunning them

  --variants Full|NoPrune|NoGate[,Full|NoPrune|NoGate...]
      run only the selected variant subset for each case

  --list
      print the selected workload cases and exit

  --help
      show this help and exit
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=1
            shift
            ;;
        --skip-existing)
            SKIP_EXISTING=1
            shift
            ;;
        --variants)
            VARIANTS_FILTER="$2"
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

case "$PROFILE" in
    paper|extended|journal|full) ;;
    *)
        echo "[ERROR] Invalid profile: $PROFILE" >&2
        usage
        exit 1
        ;;
esac

case "$MODE" in
    quick)
        WARMUP_RUNS=0
        MEASURED_RUNS=1
        ;;
    full) ;;
    *)
        echo "[ERROR] Invalid mode: $MODE" >&2
        usage
        exit 1
        ;;
esac

if [ -n "$VARIANTS_FILTER" ]; then
    OLD_IFS="$IFS"
    IFS=',' read -r -a _variant_filter_list <<< "$VARIANTS_FILTER"
    IFS="$OLD_IFS"
    for _variant in "${_variant_filter_list[@]}"; do
        case "$_variant" in
            Full|NoPrune|NoGate) ;;
            *)
                echo "[ERROR] Invalid variant in --variants: $_variant" >&2
                usage
                exit 1
                ;;
        esac
    done
fi

timestamp_now() {
    date +%Y%m%d_%H%M%S
}

TIMESTAMP="$(timestamp_now)"
LOGS_DIR="$LOGS_ROOT/$TIMESTAMP"
RAW_CSV="$RESULTS_DIR/component_ablation_runs_${TIMESTAMP}.csv"
SUMMARY_CSV="$RESULTS_DIR/component_ablation_summary_${TIMESTAMP}.csv"

declare -a CASE_SPECS

add_case() {
    CASE_SPECS+=("$1|$2|$3|$4|$5")
}

build_cases() {
    CASE_SPECS=()

    if [ "$PROFILE" = "paper" ] || [ "$PROFILE" = "extended" ]; then
        # Current manuscript cases kept for exact reproducibility.
        add_case "single_dense" "SIGN" "$SINGLE_DATASETS_DIR/SIGN.txt" "0.01" "Full,NoPrune"
        add_case "multi_sparse" "D20C50" "$MULTI_DATASETS_DIR/D20C50T2.5N10S10I1.25.txt" "0.005" "Full,NoPrune,NoGate"
    fi

    if [ "$PROFILE" = "extended" ]; then
        # Minimal uplift over the current manuscript cases.
        add_case "single_prune_stress" "Kosarak25k" "$SINGLE_DATASETS_DIR/kosarak25k.txt" "0.0005" "Full,NoPrune"
        add_case "multi_mixed" "D20C20" "$MULTI_DATASETS_DIR/D20C20T2.5N10S10I1.25.txt" "0.001" "Full,NoPrune,NoGate"
    fi

    if [ "$PROFILE" = "journal" ] || [ "$PROFILE" = "full" ]; then
        # Core journal-strength cases:
        # - SIGN isolates strong Stage-1 pruning in single-itemset mining.
        # - Kosarak25k provides a second low-support prune-dominated single-itemset regime.
        # - D20C20 shows both pruning and gating at scale.
        # - D5N1 isolates a gating-heavy multi-itemset regime.
        add_case "single_dense" "SIGN" "$SINGLE_DATASETS_DIR/SIGN.txt" "0.01" "Full,NoPrune"
        add_case "single_prune_stress" "Kosarak25k" "$SINGLE_DATASETS_DIR/kosarak25k.txt" "0.0005" "Full,NoPrune"
        add_case "multi_mixed" "D20C20" "$MULTI_DATASETS_DIR/D20C20T2.5N10S10I1.25.txt" "0.001" "Full,NoPrune,NoGate"
        add_case "multi_gate_heavy" "D5N1" "$MULTI_DATASETS_DIR/D5C10T10N1S6I4.txt" "0.004" "Full,NoPrune,NoGate"
    fi

    if [ "$PROFILE" = "full" ]; then
        # Broader confirmation cases for stronger cross-regime conclusions.
        add_case "single_prune_sparse" "BMS2" "$SINGLE_DATASETS_DIR/BMS2.txt" "0.00005" "Full,NoPrune"
        add_case "multi_mixed_heavy" "D20C30" "$MULTI_DATASETS_DIR/D20C30T2.5N10S10I1.25.txt" "0.001" "Full,NoPrune,NoGate"
        add_case "multi_gate_family" "D20C60" "$MULTI_DATASETS_DIR/D20C60T2.5N10S10I1.25.txt" "0.005" "Full,NoPrune,NoGate"
        add_case "multi_gate_confirmation" "D5N1.6" "$MULTI_DATASETS_DIR/D5C10T10N1.6S6I4.txt" "0.006" "Full,NoPrune,NoGate"
    fi
}

variant_flag() {
    case "$1" in
        Full) echo "" ;;
        NoPrune) echo "--no-prune" ;;
        NoGate) echo "--no-gate" ;;
        *)
            echo "[ERROR] Unknown variant: $1" >&2
            exit 1
            ;;
    esac
}

variant_selected() {
    local variant="$1"
    local selected

    if [ -z "$VARIANTS_FILTER" ]; then
        return 0
    fi

    OLD_IFS="$IFS"
    IFS=',' read -r -a _variant_filter_list <<< "$VARIANTS_FILTER"
    IFS="$OLD_IFS"

    for selected in "${_variant_filter_list[@]}"; do
        if [ "$selected" = "$variant" ]; then
            return 0
        fi
    done

    return 1
}

filter_variants_for_display() {
    local variants="$1"
    local variant
    local output=""
    local OLD_IFS="$IFS"
    local -a _variant_list

    IFS=',' read -r -a _variant_list <<< "$variants"
    IFS="$OLD_IFS"

    for variant in "${_variant_list[@]}"; do
        if variant_selected "$variant"; then
            if [ -n "$output" ]; then
                output="${output},${variant}"
            else
                output="$variant"
            fi
        fi
    done

    if [ -z "$output" ]; then
        output="(none)"
    fi

    echo "$output"
}

ratio_to_pct() {
    awk -v r="$1" 'BEGIN {printf "%.6f", r * 100}'
}

ratio_to_abs() {
    local dataset_file="$1"
    local ratio="$2"
    local seq_count
    seq_count=$(wc -l < "$dataset_file")
    awk -v n="$seq_count" -v r="$ratio" 'BEGIN {x=n*r; i=int(x); print (x>i)?i+1:i}'
}

csv_escape() {
    local value="$1"
    value="${value//\"/\"\"}"
    printf '"%s"' "$value"
}

parse_log_field() {
    local log_file="$1"
    local key="$2"
    awk -F: -v key="$key" '
        $0 ~ key {
            val=$2
            gsub(/^[[:space:]]+/, "", val)
            gsub(/[[:space:]]+$/, "", val)
            print val
            exit
        }
    ' "$log_file"
}

parse_log_ms_to_sec() {
    local log_file="$1"
    awk '
        /Total time ~/ {
            for (i = 1; i <= NF; i++) {
                if ($i == "~") {
                    gsub(/[^0-9]/, "", $(i+1))
                    printf "%.3f", $(i+1) / 1000
                    exit
                }
            }
        }
    ' "$log_file"
}

parse_resource_triplet() {
    local log_file="$1"
    awk -F'Wall time: | sec \\| CPU: |% \\| MaxRSS: | KB' '
        /\[RESOURCE\] Wall time:/ {
            print $2 "|" $3 "|" $4
            exit
        }
    ' "$log_file"
}

extract_log_metrics() {
    local log_file="$1"
    local wall_sec cpu_pct maxrss_kb mining_sec patterns nodes_visited subtrees_pruned nodes_gated internal_mem_mb status resource

    resource="$(parse_resource_triplet "$log_file")"
    if [ -n "$resource" ]; then
        IFS='|' read -r wall_sec cpu_pct maxrss_kb <<< "$resource"
    else
        wall_sec=""
        cpu_pct="0"
        maxrss_kb="0"
    fi

    mining_sec="$(parse_log_ms_to_sec "$log_file")"
    patterns="$(parse_log_field "$log_file" "Pattern count")"
    nodes_visited="$(parse_log_field "$log_file" "Nodes visited")"
    subtrees_pruned="$(parse_log_field "$log_file" "Subtrees pruned")"
    nodes_gated="$(parse_log_field "$log_file" "Nodes gated")"
    internal_mem_mb="$(parse_log_field "$log_file" "Max memory")"

    [ -z "$wall_sec" ] && wall_sec="$mining_sec"
    [ -z "$wall_sec" ] && wall_sec="0"
    [ -z "$mining_sec" ] && mining_sec="$wall_sec"
    [ -z "$patterns" ] && patterns="0"
    [ -z "$nodes_visited" ] && nodes_visited="0"
    [ -z "$subtrees_pruned" ] && subtrees_pruned="0"
    [ -z "$nodes_gated" ] && nodes_gated="0"
    [ -z "$internal_mem_mb" ] && internal_mem_mb="0"

    if [ "$patterns" != "0" ] || [ "$nodes_visited" != "0" ]; then
        status="OK"
    elif grep -qi "OutOfMemoryError" "$log_file"; then
        status="OOM"
    elif grep -qi "timeout" "$log_file" || awk -v limit="$TIMEOUT_SEC" -v wall="$wall_sec" 'BEGIN {exit !(wall+0 >= limit)}'; then
        status="TIMEOUT"
    else
        status="ERROR"
    fi

    echo "$wall_sec|$mining_sec|$cpu_pct|$maxrss_kb|$internal_mem_mb|$patterns|$nodes_visited|$subtrees_pruned|$nodes_gated|$status"
}

append_resource_footer() {
    local log_file="$1"
    local wall_sec="$2"
    local cpu_pct="$3"
    local maxrss_kb="$4"

    {
        echo
        echo "============================================================"
        echo "[RESOURCE] Wall time: ${wall_sec} sec | CPU: ${cpu_pct}% | MaxRSS: ${maxrss_kb} KB"
        echo "============================================================"
    } >> "$log_file"
}

find_existing_logs() {
    local family="$1"
    local dataset="$2"
    local ratio="$3"
    local variant="$4"
    local variant_lower latest_ts prefix base_dir file status
    local found_valid=0
    local -a matches

    matches=()

    while IFS= read -r file; do
        matches+=("$file")
    done < <(find "$LOGS_ROOT" -mindepth 2 -type f \( -name "${dataset}_${variant}_${ratio}_run*.log" -o -name "${dataset}_${variant}_${ratio}_warmup*.log" \) 2>/dev/null | sort)

    if [ "${#matches[@]}" -gt 0 ]; then
        for file in "${matches[@]}"; do
            status="$(extract_log_metrics "$file" | awk -F'|' '{print $10}')"
            [ "$status" = "ERROR" ] && continue
            if [[ "$file" =~ warmup([0-9]+)\.log$ ]]; then
                echo "warmup|${BASH_REMATCH[1]}|$file|logs_ablation_batch"
                found_valid=1
            elif [[ "$file" =~ run([0-9]+)\.log$ ]]; then
                echo "measured|${BASH_REMATCH[1]}|$file|logs_ablation_batch"
                found_valid=1
            fi
        done
        if [ "$found_valid" -eq 1 ]; then
            return 0
        fi
    fi

    variant_lower="$(echo "$variant" | tr '[:upper:]' '[:lower:]')"
    matches=()
    while IFS= read -r file; do
        matches+=("$file")
    done < <(find "$LOGS_ROOT" -maxdepth 1 -type f -name "TriBack-Clo_${dataset}_${ratio}_${variant_lower}_*.log" 2>/dev/null | sort)

    if [ "${#matches[@]}" -gt 0 ]; then
        local idx=1
        for file in "${matches[@]}"; do
            status="$(extract_log_metrics "$file" | awk -F'|' '{print $10}')"
            [ "$status" = "ERROR" ] && continue
            echo "measured|$idx|$file|logs_ablation_archive"
            found_valid=1
            idx=$((idx + 1))
        done
        if [ "$found_valid" -eq 1 ]; then
            return 0
        fi
    fi

    if [ "$variant" != "Full" ]; then
        return 1
    fi

    if [[ "$family" == single_* ]]; then
        prefix="TriBack-Clo"
        base_dir="$SCRIPT_DIR/logs"
    else
        prefix="TriBack-Clo-Java"
        base_dir="$SCRIPT_DIR/logs_itemsets"
    fi

    latest_ts="$(
        find "$base_dir" -type f -name "${prefix}_${dataset}_${ratio}_run1_*.log" 2>/dev/null \
            | sed -E 's/.*_run1_([0-9]{8}_[0-9]{6})\.log/\1/' \
            | sort \
            | tail -1
    )"

    if [ -n "$latest_ts" ]; then
        while IFS= read -r file; do
            matches+=("$file")
        done < <(find "$base_dir" -type f \( -name "${prefix}_${dataset}_${ratio}_run*_${latest_ts}.log" -o -name "${prefix}_${dataset}_${ratio}_runwarmup*_${latest_ts}.log" \) 2>/dev/null | sort)

        for file in "${matches[@]}"; do
            status="$(extract_log_metrics "$file" | awk -F'|' '{print $10}')"
            [ "$status" = "ERROR" ] && continue
            if [[ "$file" =~ runwarmup([0-9]+)_${latest_ts}\.log$ ]]; then
                echo "warmup|${BASH_REMATCH[1]}|$file|benchmark_logs"
                found_valid=1
            elif [[ "$file" =~ run([0-9]+)_${latest_ts}\.log$ ]]; then
                echo "measured|${BASH_REMATCH[1]}|$file|benchmark_logs"
                found_valid=1
            fi
        done
        if [ "$found_valid" -eq 1 ]; then
            return 0
        fi
    fi

    return 1
}

run_once() {
    local dataset_label="$1"
    local dataset_file="$2"
    local ratio="$3"
    local variant="$4"
    local run_id="$5"
    local log_file="$6"

    local minsup_pct minsup_abs time_file exit_code flag start_ts end_ts
    local wall_sec cpu_pct maxrss_kb mining_sec patterns nodes_visited subtrees_pruned nodes_gated internal_mem_mb status

    minsup_pct="$(ratio_to_pct "$ratio")"
    minsup_abs="$(ratio_to_abs "$dataset_file" "$ratio")"
    time_file="$(mktemp)"
    flag="$(variant_flag "$variant")"

    wall_sec="0"
    cpu_pct="0"
    maxrss_kb="0"

    if [ -n "$TIME_BIN" ]; then
        (
            "$TIME_BIN" -f "%e %P %M" -o "$time_file" \
                timeout --signal=TERM --kill-after=10s "$TIMEOUT_SEC" \
                java -Xms"$JVM_HEAP_START" -Xmx"$JVM_HEAP_MAX" -cp "$TRIBACK_CLASSPATH" \
                ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
                "$dataset_file" "/dev/null" "$minsup_abs" $flag
        ) > "$log_file" 2>&1
        exit_code=$?
    else
        start_ts="$(date +%s.%N)"
        (
            timeout --signal=TERM --kill-after=10s "$TIMEOUT_SEC" \
                java -Xms"$JVM_HEAP_START" -Xmx"$JVM_HEAP_MAX" -cp "$TRIBACK_CLASSPATH" \
                ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
                "$dataset_file" "/dev/null" "$minsup_abs" $flag
        ) > "$log_file" 2>&1
        exit_code=$?
        end_ts="$(date +%s.%N)"
        wall_sec="$(awk -v start="$start_ts" -v end="$end_ts" 'BEGIN {printf "%.3f", end - start}')"
    fi

    if [ -f "$time_file" ] && [ -s "$time_file" ]; then
        wall_sec=$(awk '{print $1}' "$time_file")
        cpu_pct=$(awk '{print $2}' "$time_file" | tr -d '%')
        maxrss_kb=$(awk '{print $3}' "$time_file")
    fi
    rm -f "$time_file"

    if [ "${exit_code:-0}" -eq 124 ] || [ "${exit_code:-0}" -eq 125 ] || [ "${exit_code:-0}" -eq 137 ] || [ "${exit_code:-0}" -eq 143 ]; then
        status="TIMEOUT"
        wall_sec="$TIMEOUT_SEC"
    elif [ "$exit_code" -ne 0 ]; then
        status="ERROR"
    else
        status="OK"
    fi

    mining_sec="$(parse_log_ms_to_sec "$log_file")"
    patterns="$(parse_log_field "$log_file" "Pattern count")"
    nodes_visited="$(parse_log_field "$log_file" "Nodes visited")"
    subtrees_pruned="$(parse_log_field "$log_file" "Subtrees pruned")"
    nodes_gated="$(parse_log_field "$log_file" "Nodes gated")"
    internal_mem_mb="$(parse_log_field "$log_file" "Max memory")"

    [ -z "$mining_sec" ] && mining_sec="$wall_sec"
    [ -z "$patterns" ] && patterns="0"
    [ -z "$nodes_visited" ] && nodes_visited="0"
    [ -z "$subtrees_pruned" ] && subtrees_pruned="0"
    [ -z "$nodes_gated" ] && nodes_gated="0"
    [ -z "$internal_mem_mb" ] && internal_mem_mb="0"

    append_resource_footer "$log_file" "$wall_sec" "$cpu_pct" "$maxrss_kb"

    echo "$wall_sec|$mining_sec|$cpu_pct|$maxrss_kb|$internal_mem_mb|$patterns|$nodes_visited|$subtrees_pruned|$nodes_gated|$status"
}

get_median() {
    if [ $# -eq 0 ]; then
        echo "0"
        return
    fi

    printf "%s\n" "$@" | LC_ALL=C sort -n | awk '
        {a[NR]=$1}
        END{
            if (NR == 0) { print 0; exit }
            if (NR % 2 == 1) {
                print a[(NR+1)/2]
            } else {
                print (a[NR/2] + a[NR/2+1]) / 2
            }
        }'
}

get_status_summary() {
    local final="OK"
    local s
    for s in "$@"; do
        if [ "$s" != "OK" ]; then
            final="$s"
        fi
    done
    echo "$final"
}

init_outputs() {
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    echo "timestamp,profile,mode,case_family,dataset,ratio,minsup_pct,minsup_abs,variant,run_type,run_id,wall_sec,mining_sec,cpu_pct,maxrss_kb,internal_mem_mb,patterns,nodes_visited,subtrees_pruned_raw,nodes_gated,status,log_file" > "$RAW_CSV"
    echo "timestamp,profile,mode,case_family,dataset,ratio,minsup_pct,minsup_abs,variant,warmup_runs,measured_runs,wall_sec_median,mining_sec_median,maxrss_kb_median,internal_mem_mb_median,patterns_median,nodes_visited_median,subtrees_pruned_raw_median,subtrees_pruned_effective,nodes_gated_median,status,notes" > "$SUMMARY_CSV"
}

print_cases() {
    local spec family dataset dataset_file ratio variants minsup_pct minsup_abs
    build_cases
    echo "Profile: $PROFILE"
    echo "Mode: $MODE"
    echo "Skip existing: $SKIP_EXISTING"
    if [ -n "$VARIANTS_FILTER" ]; then
        echo "Variants filter: $VARIANTS_FILTER"
    fi
    echo
    for spec in "${CASE_SPECS[@]}"; do
        IFS='|' read -r family dataset dataset_file ratio variants <<< "$spec"
        minsup_pct="$(ratio_to_pct "$ratio")"
        if [ -f "$dataset_file" ]; then
            minsup_abs="$(ratio_to_abs "$dataset_file" "$ratio")"
        else
            minsup_abs="missing-dataset"
        fi
        echo "- $family | $dataset | ratio=$ratio | minsup=${minsup_pct}% | abs=$minsup_abs | variants=$(filter_variants_for_display "$variants")"
    done
}

run_profile() {
    local spec family dataset dataset_file ratio variants minsup_pct minsup_abs
    local variant run_type run_id log_file result
    local wall mining cpu rss internal_mem patterns nodes_visited subtrees_pruned nodes_gated status
    local source_label existing_note effective_pruned notes
    local existing_warmups existing_measured
    local -a wall_vals mining_vals rss_vals internal_vals patterns_vals nodes_vals pruned_vals gated_vals statuses
    local -a variant_list existing_entries
    local med_wall med_mining med_rss med_internal med_patterns med_nodes med_pruned med_gated final_status

    build_cases
    init_outputs

    echo "=============================================="
    echo "COMPONENT CONTRIBUTION ANALYSIS"
    echo "Profile: $PROFILE"
    echo "Mode: $MODE"
        echo "Skip existing: $SKIP_EXISTING"
    if [ -n "$VARIANTS_FILTER" ]; then
        echo "Variants filter: $VARIANTS_FILTER"
    fi
        echo "Warmup runs: $WARMUP_RUNS"
    echo "Measured runs: $MEASURED_RUNS"
    echo "Timestamp: $TIMESTAMP"
    echo "Logs: $LOGS_DIR"
    echo "Raw CSV: $RAW_CSV"
    echo "Summary CSV: $SUMMARY_CSV"
    if [ -n "$TIME_BIN" ]; then
        echo "External RSS tool: $TIME_BIN"
    else
        echo "External RSS tool: unavailable (MaxRSS disabled, internal JVM peak memory only)"
    fi
    echo "=============================================="

    for spec in "${CASE_SPECS[@]}"; do
        IFS='|' read -r family dataset dataset_file ratio variants <<< "$spec"

        if [ ! -f "$dataset_file" ]; then
            echo "[SKIP] Missing dataset: $dataset_file"
            continue
        fi

        minsup_pct="$(ratio_to_pct "$ratio")"
        minsup_abs="$(ratio_to_abs "$dataset_file" "$ratio")"

        echo
        echo "=============================================="
        echo "CASE: $dataset (${family}, minsup=${minsup_pct}% / ${minsup_abs})"
        echo "=============================================="

        IFS=',' read -r -a variant_list <<< "$variants"
        for variant in "${variant_list[@]}"; do
            if ! variant_selected "$variant"; then
                continue
            fi

            wall_vals=()
            mining_vals=()
            rss_vals=()
            internal_vals=()
            patterns_vals=()
            nodes_vals=()
            pruned_vals=()
            gated_vals=()
            statuses=()
            existing_warmups=0
            existing_measured=0
            source_label=""
            existing_note=""

            if [ "$SKIP_EXISTING" -eq 1 ]; then
                mapfile -t existing_entries < <(find_existing_logs "$family" "$dataset" "$ratio" "$variant")
            else
                existing_entries=()
            fi

            if [ "${#existing_entries[@]}" -gt 0 ]; then
                echo -n "  $variant: using existing logs... "

                for result in "${existing_entries[@]}"; do
                    IFS='|' read -r run_type run_id log_file source_label <<< "$result"
                    result="$(extract_log_metrics "$log_file")"
                    IFS='|' read -r wall mining cpu rss internal_mem patterns nodes_visited subtrees_pruned nodes_gated status <<< "$result"

                    echo "$TIMESTAMP,$PROFILE,$MODE,$family,$dataset,$ratio,$minsup_pct,$minsup_abs,$variant,$run_type,$run_id,$wall,$mining,$cpu,$rss,$internal_mem,$patterns,$nodes_visited,$subtrees_pruned,$nodes_gated,$status,$(csv_escape "${log_file#$PROJECT_DIR/}")" >> "$RAW_CSV"

                    if [ "$run_type" = "warmup" ]; then
                        existing_warmups=$((existing_warmups + 1))
                        continue
                    fi

                    existing_measured=$((existing_measured + 1))
                    wall_vals+=("$wall")
                    mining_vals+=("$mining")
                    rss_vals+=("$rss")
                    internal_vals+=("$internal_mem")
                    patterns_vals+=("$patterns")
                    nodes_vals+=("$nodes_visited")
                    pruned_vals+=("$subtrees_pruned")
                    gated_vals+=("$nodes_gated")
                    statuses+=("$status")
                done

                if [ "$existing_measured" -gt 0 ]; then
                    med_wall="$(get_median "${wall_vals[@]}")"
                    med_mining="$(get_median "${mining_vals[@]}")"
                    med_rss="$(get_median "${rss_vals[@]}")"
                    med_internal="$(get_median "${internal_vals[@]}")"
                    med_patterns="$(get_median "${patterns_vals[@]}")"
                    med_nodes="$(get_median "${nodes_vals[@]}")"
                    med_pruned="$(get_median "${pruned_vals[@]}")"
                    med_gated="$(get_median "${gated_vals[@]}")"
                    final_status="$(get_status_summary "${statuses[@]}")"

                    if [ "$variant" = "NoPrune" ]; then
                        effective_pruned="NA"
                        notes="Used existing logs from ${source_label}; raw pruned counter records temporal-witness detections before the no-prune guard."
                    else
                        effective_pruned="$med_pruned"
                        notes="Used existing logs from ${source_label}."
                    fi

                    if [ "$existing_measured" -ne "$MEASURED_RUNS" ] || [ "$existing_warmups" -ne "$WARMUP_RUNS" ]; then
                        notes="${notes} Summary derived from ${existing_measured} measured run(s) and ${existing_warmups} warmup run(s)."
                    fi

                    echo "$TIMESTAMP,$PROFILE,$MODE,$family,$dataset,$ratio,$minsup_pct,$minsup_abs,$variant,$existing_warmups,$existing_measured,$med_wall,$med_mining,$med_rss,$med_internal,$med_patterns,$med_nodes,$med_pruned,$effective_pruned,$med_gated,$final_status,$(csv_escape "$notes")" >> "$SUMMARY_CSV"

                    if [ "$med_rss" != "0" ] && [ "$med_rss" != "0.0" ]; then
                        printf "done (source=%s, status=%s, wall=%ss, mining=%ss, internal_mem=%sMB, maxrss=%sKB, nodes=%s, pruned=%s, gated=%s)\n" \
                            "$source_label" "$final_status" "$med_wall" "$med_mining" "$med_internal" "$med_rss" "$med_nodes" "$med_pruned" "$med_gated"
                    else
                        printf "done (source=%s, status=%s, wall=%ss, mining=%ss, internal_mem=%sMB, nodes=%s, pruned=%s, gated=%s)\n" \
                            "$source_label" "$final_status" "$med_wall" "$med_mining" "$med_internal" "$med_nodes" "$med_pruned" "$med_gated"
                    fi
                    continue
                fi
            fi

            echo -n "  $variant: "

            for run_id in $(seq 1 "$WARMUP_RUNS"); do
                echo -n "warmup${run_id}... "
                log_file="$LOGS_DIR/${dataset}_${variant}_${ratio}_warmup${run_id}.log"
                result="$(run_once "$dataset" "$dataset_file" "$ratio" "$variant" "$run_id" "$log_file")"
                IFS='|' read -r wall mining cpu rss internal_mem patterns nodes_visited subtrees_pruned nodes_gated status <<< "$result"
                echo "$TIMESTAMP,$PROFILE,$MODE,$family,$dataset,$ratio,$minsup_pct,$minsup_abs,$variant,warmup,$run_id,$wall,$mining,$cpu,$rss,$internal_mem,$patterns,$nodes_visited,$subtrees_pruned,$nodes_gated,$status,$(csv_escape "${log_file#$PROJECT_DIR/}")" >> "$RAW_CSV"
            done

            for run_id in $(seq 1 "$MEASURED_RUNS"); do
                echo -n "run${run_id}... "
                log_file="$LOGS_DIR/${dataset}_${variant}_${ratio}_run${run_id}.log"
                result="$(run_once "$dataset" "$dataset_file" "$ratio" "$variant" "$run_id" "$log_file")"
                IFS='|' read -r wall mining cpu rss internal_mem patterns nodes_visited subtrees_pruned nodes_gated status <<< "$result"

                wall_vals+=("$wall")
                mining_vals+=("$mining")
                rss_vals+=("$rss")
                internal_vals+=("$internal_mem")
                patterns_vals+=("$patterns")
                nodes_vals+=("$nodes_visited")
                pruned_vals+=("$subtrees_pruned")
                gated_vals+=("$nodes_gated")
                statuses+=("$status")

                echo "$TIMESTAMP,$PROFILE,$MODE,$family,$dataset,$ratio,$minsup_pct,$minsup_abs,$variant,measured,$run_id,$wall,$mining,$cpu,$rss,$internal_mem,$patterns,$nodes_visited,$subtrees_pruned,$nodes_gated,$status,$(csv_escape "${log_file#$PROJECT_DIR/}")" >> "$RAW_CSV"
            done

            med_wall="$(get_median "${wall_vals[@]}")"
            med_mining="$(get_median "${mining_vals[@]}")"
            med_rss="$(get_median "${rss_vals[@]}")"
            med_internal="$(get_median "${internal_vals[@]}")"
            med_patterns="$(get_median "${patterns_vals[@]}")"
            med_nodes="$(get_median "${nodes_vals[@]}")"
            med_pruned="$(get_median "${pruned_vals[@]}")"
            med_gated="$(get_median "${gated_vals[@]}")"
            final_status="$(get_status_summary "${statuses[@]}")"

            if [ "$variant" = "NoPrune" ]; then
                effective_pruned="NA"
                notes="Raw pruned counter records temporal-witness detections before the no-prune guard."
            else
                effective_pruned="$med_pruned"
                notes=""
            fi

            echo "$TIMESTAMP,$PROFILE,$MODE,$family,$dataset,$ratio,$minsup_pct,$minsup_abs,$variant,$WARMUP_RUNS,$MEASURED_RUNS,$med_wall,$med_mining,$med_rss,$med_internal,$med_patterns,$med_nodes,$med_pruned,$effective_pruned,$med_gated,$final_status,$(csv_escape "$notes")" >> "$SUMMARY_CSV"

            if [ "$med_rss" != "0" ] && [ "$med_rss" != "0.0" ]; then
                printf "done (status=%s, wall=%ss, mining=%ss, internal_mem=%sMB, maxrss=%sKB, nodes=%s, pruned=%s, gated=%s)\n" \
                    "$final_status" "$med_wall" "$med_mining" "$med_internal" "$med_rss" "$med_nodes" "$med_pruned" "$med_gated"
            else
                printf "done (status=%s, wall=%ss, mining=%ss, internal_mem=%sMB, nodes=%s, pruned=%s, gated=%s)\n" \
                    "$final_status" "$med_wall" "$med_mining" "$med_internal" "$med_nodes" "$med_pruned" "$med_gated"
            fi
        done
    done

    echo
    echo "=============================================="
    echo "COMPONENT ANALYSIS COMPLETE"
    echo "Logs saved to: $LOGS_DIR"
    echo "Raw CSV: $RAW_CSV"
    echo "Summary CSV: $SUMMARY_CSV"
    echo "=============================================="
}

build_cases

if [ "$LIST_ONLY" -eq 1 ]; then
    print_cases
    exit 0
fi

run_profile
