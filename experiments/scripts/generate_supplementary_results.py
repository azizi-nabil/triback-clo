#!/usr/bin/env python3
"""Generate a standalone supplementary LaTeX file with full benchmark tables."""

from __future__ import annotations

import csv
from pathlib import Path
import re
import sys
from statistics import median


ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(ROOT / "experiments"))

from rebuild_md_files import parse_log  # noqa: E402

OUTPUT = ROOT / "docs" / "els-cas-templates" / "SupplementaryMaterial.tex"
SOURCES = [
    (
        "Single-Itemset Archived Benchmark Tables",
        ROOT / "experiments" / "results" / "BENCHMARK_RESULTS.md",
    ),
    (
        "Multi-Itemset Archived Benchmark Tables",
        ROOT / "experiments" / "results" / "BENCHMARK_RESULTS_ITEMSETS.md",
    ),
]
ABLATION_SUMMARY = (
    ROOT
    / "experiments"
    / "results"
    / "component_ablation_summary_merged.csv"
)

PAPER_TITLE = "TriBack-Clo: Sound Triple-Witness BackScan for Closed Pattern Mining in Itemset-Sequences"
CORRESPONDING_AUTHOR = "Nabil Azizi"
CORRESPONDING_AFFILIATION = "Department of Computer Science, University, Khenchela, Algeria"
CORRESPONDING_EMAIL = "nabil.azizi@example.edu"
SCALABILITY_LOGS = ROOT / "experiments" / "logs_scalability_D"
SI_GRID_LOGS = ROOT / "experiments" / "logs_fig15"


def escape_tex(text: str) -> str:
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    out = []
    for ch in text:
        out.append(replacements.get(ch, ch))
    return "".join(out)


def normalize_dataset_name(text: str) -> str:
    if text == "MSNBC_small":
        return "MSNBC-small"
    return text


def display_algorithm_name(name: str) -> str:
    if "TriBack-Clo" in name:
        return "TriBack-Clo"
    if name == "CloFast":
        return "CloFAST"
    return name


def normalize_cell(text: str) -> str:
    text = text.strip()
    if not text or text == "---":
        text = "N/A"
    text = text.replace("—", "N/A")
    if text == "CloFast":
        text = "CloFAST"
    bold = text.startswith("**") and text.endswith("**") and len(text) >= 4
    if bold:
        text = text[2:-2].strip()
    text = escape_tex(text)
    if bold:
        text = rf"\textbf{{{text}}}"
    return text


def adjust_supplementary_row(header: list[str], row: list[str]) -> list[str]:
    """Patch known SPMF zero-memory artifacts only in supplementary output."""
    adjusted = list(row)
    index = {name: idx for idx, name in enumerate(header)}

    algo = adjusted[index["Algorithm"]].strip() if "Algorithm" in index else ""
    patterns = adjusted[index["Patterns"]].strip() if "Patterns" in index else ""
    internal = adjusted[index["Internal Mem"]].strip() if "Internal Mem" in index else ""
    gap = adjusted[index["Gap"]].strip() if "Gap" in index else ""

    if algo == "BIDE+" and patterns == "0" and internal == "0 MB":
        adjusted[index["Internal Mem"]] = "N/A"
        if "Gap" in index and gap in {"—", "N/A"}:
            adjusted[index["Gap"]] = "N/A"

    return adjusted


def parse_experiment_filename(filename: str) -> dict[str, object] | None:
    stem = filename.removesuffix(".log")
    match = re.match(
        r"^(?P<algorithm>[^_]+)_(?P<dataset>.+?)_(?P<ratio>0\.\d+)_(?P<run>run(?:warmup\d+|\d+))(?:_|$)",
        stem,
    )
    if not match:
        return None

    run_token = match.group("run")
    if not run_token.startswith("run") or "warmup" in run_token:
        return None

    return {
        "algorithm": display_algorithm_name(match.group("algorithm")),
        "dataset": match.group("dataset"),
        "ratio": float(match.group("ratio")),
        "run": run_token.removeprefix("run"),
    }


def collect_median_runs(log_dir: Path) -> dict[tuple[str, float, str], dict[str, object]]:
    collected: dict[tuple[str, float, str], dict[str, tuple[str, tuple]]] = {}

    for logfile in sorted(log_dir.glob("*.log")):
        info = parse_experiment_filename(logfile.name)
        if not info:
            continue

        parsed = parse_log(str(logfile))
        key = (str(info["dataset"]), float(info["ratio"]), str(info["algorithm"]))
        run = str(info["run"])
        collected.setdefault(key, {})
        # Prefer the lexicographically latest timestamp when multiple campaigns
        # retained the same run index for the same configuration.
        prev = collected[key].get(run)
        if prev is None or logfile.name > prev[0]:
            collected[key][run] = (logfile.name, parsed)

    aggregated: dict[tuple[str, float, str], dict[str, object]] = {}
    for key, runs in collected.items():
        parsed_runs = {run: payload[1] for run, payload in runs.items()}
        valid = [
            parsed_runs[run]
            for run in ("1", "2", "3")
            if run in parsed_runs
            and parsed_runs[run][5] == "OK"
            and parsed_runs[run][1] is not None
        ]
        if valid:
            wall_vals = [x[0] for x in valid if x[0] is not None]
            mining_vals = [x[1] for x in valid if x[1] is not None]
            pattern_vals = [x[2] for x in valid if x[2] is not None]
            mem_vals = [x[4] for x in valid if x[4] is not None]
            aggregated[key] = {
                "status": "OK",
                "wall": median(wall_vals) if wall_vals else None,
                "mining": median(mining_vals) if mining_vals else None,
                "patterns": int(median(pattern_vals)) if pattern_vals else None,
                "memory_mb": median(mem_vals) if mem_vals else None,
            }
            continue

        status = "TIMEOUT"
        for run in ("1", "2", "3"):
            if run in parsed_runs and parsed_runs[run][5] != "OK":
                status = parsed_runs[run][5]
        aggregated[key] = {
            "status": status,
            "wall": None,
            "mining": None,
            "patterns": None,
            "memory_mb": None,
        }

    return aggregated


def format_num(value: float | None, digits: int = 3) -> str:
    if value is None:
        return "N/A"
    return f"{value:.{digits}f}"


def format_pattern(value: int | None) -> str:
    if value is None:
        return "N/A"
    return format_int(value)


def format_mem_gb(value_mb: float | None, digits: int = 3) -> str:
    if value_mb is None:
        return "N/A"
    return f"{value_mb / 1024:.{digits}f}"


def make_longtable(
    subsection_title: str,
    intro_lines: list[str],
    header: list[str],
    rows: list[list[str]],
    colspec: str,
) -> str:
    bold_best(header, rows)
    header_tex = " & ".join(escape_tex(cell) for cell in header) + r" \\"
    row_tex = [" & ".join(escape_tex(cell) for cell in row) + r" \\" for row in rows]

    lines = [
        r"\begingroup",
        r"\footnotesize",
        r"\setlength{\tabcolsep}{4pt}",
        r"\renewcommand{\arraystretch}{1.05}",
        *intro_lines,
        r"\setlength{\LTleft}{0pt}",
        r"\setlength{\LTright}{0pt}",
        rf"\begin{{longtable}}{{{colspec}}}",
        rf"\caption{{{subsection_title}. Bold values indicate best performance.}} \\",
        r"\toprule",
        header_tex,
        r"\midrule",
        r"\endfirsthead",
        rf"\caption[]{{{subsection_title} (continued)}} \\",
        r"\toprule",
        header_tex,
        r"\midrule",
        r"\endhead",
        r"\bottomrule",
        r"\endfoot",
        *row_tex,
        r"\end{longtable}",
        r"\endgroup",
        "",
    ]
    return "\n".join(lines)


def make_scalability_sections() -> str:
    data = collect_median_runs(SCALABILITY_LOGS)
    ds_order = [50, 100, 150, 200, 250, 300]
    algos = ["TriBack-Clo", "BIDE+", "ClaSP", "CloSpan"]
    ratio = 0.3

    runtime_rows: list[list[str]] = []
    memory_rows: list[list[str]] = []
    for d in ds_order:
        dataset = f"D{d}C20T20N2.5S6I4"
        pattern_value = None
        runtime_row = [str(d), "N/A"]
        memory_row = [str(d)]
        for algo in algos:
            entry = data.get((dataset, ratio, algo))
            if entry and entry["patterns"] is not None and pattern_value is None:
                pattern_value = entry["patterns"]
            runtime_row.append(format_num(entry["mining"] if entry else None))
            memory_row.append(format_mem_gb(entry["memory_mb"] if entry else None))
        runtime_row[1] = format_pattern(pattern_value)
        runtime_rows.append(runtime_row)
        memory_rows.append(memory_row)

    intro = [
        r"{\noindent\footnotesize These tables report exact medians over three measured runs for each scalability configuration. CloFAST is omitted because the $D$-sweep at minsup 30\% does not yield a complete comparable series beyond the smallest setting. \par}",
        r"\vspace{0.5em}",
        r"\noindent\textbf{Runtime medians.}",
        r"\vspace{0.35em}",
    ]
    runtime = make_longtable(
        "Scalability Sweep (D=50k to 300k, minsup 30\\%) -- Runtime",
        intro,
        ["|D| (k)", "Patterns", "TriBack-Clo", "BIDE+", "ClaSP", "CloSpan"],
        runtime_rows,
        "@{}L{1.20cm}L{1.35cm}L{2.05cm}L{1.75cm}L{1.85cm}L{1.95cm}@{}",
    )

    mem_intro = [
        r"\noindent\textbf{Peak-memory medians (JVM).}",
        r"\vspace{0.35em}",
    ]
    memory = make_longtable(
        "Scalability Sweep (D=50k to 300k, minsup 30\\%) -- Peak Memory",
        mem_intro,
        ["|D| (k)", "TriBack-Clo", "BIDE+", "ClaSP", "CloSpan"],
        memory_rows,
        "@{}L{1.20cm}L{2.10cm}L{1.90cm}L{1.90cm}L{2.00cm}@{}",
    )
    return runtime + memory


def make_si_grid_sections() -> str:
    data = collect_median_runs(SI_GRID_LOGS)
    ratio = 0.3
    scenario_order = [
        "S2I6",
        "S4I6",
        "S6I2",
        "S6I4",
        "S6I6",
        "S6I8",
        "S6I10",
        "S8I6",
        "S10I6",
    ]
    scenario_to_dataset = {
        label: f"D50C20T20N2.5{label}" for label in scenario_order
    }
    algos = ["TriBack-Clo", "BIDE+", "CloFAST", "ClaSP", "CloSpan"]

    runtime_rows: list[list[str]] = []
    memory_rows: list[list[str]] = []
    for label in scenario_order:
        dataset = scenario_to_dataset[label]
        pattern_value = None
        runtime_row = [label, "N/A"]
        memory_row = [label]
        for algo in algos:
            entry = data.get((dataset, ratio, algo))
            if entry and entry["patterns"] is not None and pattern_value is None:
                pattern_value = entry["patterns"]
            runtime_row.append(format_num(entry["mining"] if entry and entry["status"] == "OK" else None))
            memory_row.append(format_mem_gb(entry["memory_mb"] if entry and entry["status"] == "OK" else None))
        runtime_row[1] = format_pattern(pattern_value)
        runtime_rows.append(runtime_row)
        memory_rows.append(memory_row)

    intro = [
        r"{\noindent\footnotesize These tables report exact medians over the three retained measured runs for the archived S/I grid at minsup 30\%. Scenario labels encode maximal-sequence length $S$ and planted itemset size $I$: for example, \texttt{S6I4} denotes $S=6$, $I=4$. \par}",
        r"\vspace{0.5em}",
        r"\noindent\textbf{Runtime medians.}",
        r"\vspace{0.35em}",
    ]
    runtime = make_longtable(
        "S/I Parameter Grid Experiments (Varying Maximal Sequence Length and Planted Itemset Size) -- Runtime",
        intro,
        ["Scenario", "Patterns", "TriBack-Clo", "BIDE+", "CloFAST", "ClaSP", "CloSpan"],
        runtime_rows,
        "@{}L{1.40cm}L{1.35cm}L{1.80cm}L{1.55cm}L{1.65cm}L{1.55cm}L{1.65cm}@{}",
    )

    mem_intro = [
        r"\noindent\textbf{Peak-memory medians (JVM).}",
        r"\vspace{0.35em}",
    ]
    memory = make_longtable(
        "S/I Parameter Grid Experiments (Varying Maximal Sequence Length and Planted Itemset Size) -- Peak Memory",
        mem_intro,
        ["Scenario", "TriBack-Clo", "BIDE+", "CloFAST", "ClaSP", "CloSpan"],
        memory_rows,
        "@{}L{1.40cm}L{1.85cm}L{1.65cm}L{1.75cm}L{1.65cm}L{1.75cm}@{}",
    )
    return runtime + memory


def parse_markdown_tables(path: Path) -> list[dict[str, object]]:
    sections: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if line.startswith("## "):
            dataset = line[3:].strip()
            if dataset.endswith(" Dataset"):
                dataset = dataset[: -len(" Dataset")]
            current = {"dataset": dataset, "header": [], "rows": []}
            sections.append(current)
            i += 1
            continue
        if (
            current is not None
            and line.startswith("|")
            and i + 1 < len(lines)
            and lines[i + 1].startswith("|-")
        ):
            header = [cell.strip() for cell in line.strip().strip("|").split("|")]
            rows: list[list[str]] = []
            i += 2
            while i < len(lines) and lines[i].startswith("|"):
                cells = [cell.strip() for cell in lines[i].strip().strip("|").split("|")]
                if len(cells) == len(header):
                    rows.append(cells)
                i += 1
            current["header"] = header
            current["rows"] = rows
            continue
        i += 1
    return [
        section
        for section in sections
        if section["header"] and section["rows"] and section["dataset"] != "Summary"
    ]


def format_int(value: int) -> str:
    return f"{value:,}"


def format_pct(value: str) -> str:
    return value.rstrip("0").rstrip(".")


def parse_ablation_summary(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def make_ablation_section() -> str:
    header = [
        "Dataset",
        "Variant",
        "Status",
        "Time (s)",
        "Int. Mem (MB)",
        "Patterns",
        "Nodes Visited",
        "Effective Pruned",
        "Nodes Gated",
    ]
    rows_data: list[list[str]] = []

    for values in parse_ablation_summary(ABLATION_SUMMARY):
        dataset = f"{values['dataset']} {format_pct(values['minsup_pct'])}%"
        effective_pruned = values["subtrees_pruned_effective"]
        if not effective_pruned or effective_pruned == "NA":
            effective_pruned_tex = "---"
        else:
            effective_pruned_tex = format_int(int(effective_pruned))
        row = [
            escape_tex(dataset),
            escape_tex(values["variant"]),
            escape_tex(values["status"]),
            escape_tex(f"{float(values['wall_sec_median']):.1f}"),
            escape_tex(f"{float(values['internal_mem_mb_median']):.1f}"),
            escape_tex(format_int(int(values["patterns_median"]))),
            escape_tex(format_int(int(values["nodes_visited_median"]))),
            escape_tex(effective_pruned_tex),
            escape_tex(format_int(int(values["nodes_gated_median"]))),
        ]
        rows_data.append(row)
        
    bold_best(header, rows_data)
    header_tex = " & ".join(escape_tex(cell) for cell in header) + r" \\"
    rows = [" & ".join(row) + r" \\" for row in rows_data]

    return "\n".join(
        [
            r"\section*{Component Ablation Summary}",
            "",
            r"\noindent This section reports the full eight-workload ablation profile underlying the component-contribution discussion in the main paper (Section~8.6).",
            r"The table below reports medians over three measured runs for each workload--variant combination.",
            "",
            r"\noindent \textbf{Interpretation note.}",
            r"\texttt{Int. Mem} is the JVM-internal peak-memory statistic recorded by the ablation runner.",
            r"\texttt{Effective Pruned} reports the implementation-level pruning effect; for \texttt{NoPrune} rows it is shown as \texttt{---} for interpretive clarity because the raw temporal-witness counter is still incremented before the no-prune guard.",
            "",
            r"\begingroup",
            r"\footnotesize",
            r"\setlength{\tabcolsep}{4pt}",
            r"\renewcommand{\arraystretch}{1.05}",
            r"\setlength{\LTleft}{0pt}",
            r"\setlength{\LTright}{0pt}",
            r"\begin{longtable}{@{}L{2.20cm}L{1.40cm}L{1.55cm}L{1.25cm}L{1.70cm}L{1.80cm}L{2.05cm}L{2.05cm}L{1.70cm}@{}}",
            r"\caption{Component ablation full profile. Bold values indicate best performance in Time, Nodes, and Mem.} \\",
            r"\toprule",
            header_tex,
            r"\midrule",
            r"\endfirsthead",
            r"\caption[]{Component ablation profile (continued)} \\",
            r"\toprule",
            header_tex,
            r"\midrule",
            r"\endhead",
            r"\bottomrule",
            r"\endfoot",
            *rows,
            r"\end{longtable}",
            r"\endgroup",
            "",
        ]
    )



def parse_metric(s: str) -> float | None:
    import re
    s = s.replace(r"\,", "").replace(",", "").replace(r"\textbf{", "").replace("}", "")
    m = re.search(r"^([0-9.]+)\s*(MB|GB|M|k|x)?$", s, re.IGNORECASE)
    if not m:
        return None
    val = float(m.group(1))
    unit = (m.group(2) or "").upper()
    if unit == "GB":
        val *= 1024
    if unit == "M":
        val *= 1000000
    if unit == "K":
        val *= 1000
    return val

def bold_best(header: list[str], rows: list[list[str]]) -> None:
    cols_to_check = []
    for i, h in enumerate(header):
        hl = h.lower()
        if any(x in hl for x in ["mining", "wall", "mem", "time", "nodes", "pruned"]):
            cols_to_check.append(i)
            
    # Group rows by the first column (e.g. Support % or Dataset) to bold the best *within context*
    from collections import defaultdict
    groups = defaultdict(list)
    for row in rows:
        groups[row[0]].append(row)
            
    for c in cols_to_check:
        hl = header[c].lower()
        # For most metrics, lower is better. For gated/pruned, higher is better.
        higher_is_better = ("gated" in hl or "pruned" in hl)
        
        for group_rows in groups.values():
            best_val = float('-inf') if higher_is_better else float('inf')
            
            for row in group_rows:
                if any(x in str(cell) for cell in row for x in ["TIMEOUT", "OOM", "ERROR"]) or any(x in row[c] for x in ["N/A", "---", "—"]):
                    continue
                val = parse_metric(row[c])
                if val is None or val == 0: # Skip 0 as trivial/neutral
                    continue
                    
                if higher_is_better:
                    if val > best_val:
                        best_val = val
                else:
                    if val < best_val:
                        best_val = val
                    
            if best_val not in [float('inf'), float('-inf')]:
                for row in group_rows:
                    if any(x in str(cell) for cell in row for x in ["TIMEOUT", "OOM", "ERROR"]) or any(x in row[c] for x in ["N/A", "---", "—"]):
                        continue
                    val = parse_metric(row[c])
                    if val is not None and abs(val - best_val) <= 1e-6 * max(1.0, abs(best_val)):
                        if r"\textbf{" not in row[c]:
                            row[c] = f"\\textbf{{{row[c]}}}"

def make_table(section: dict[str, object]) -> str:
    dataset = escape_tex(normalize_dataset_name(str(section["dataset"])))
    header = [str(cell) for cell in section["header"]]
    rows = []
    for raw_row in section["rows"]:
        adjusted = adjust_supplementary_row(header, [str(cell) for cell in raw_row])
        rows.append([normalize_cell(cell) for cell in adjusted])
    bold_best(header, rows)
    header_tex = " & ".join(escape_tex(cell) for cell in header) + r" \\"
    row_tex = [" & ".join(row) + r" \\" for row in rows]

    return "\n".join(
        [
            r"\begingroup",
            r"\footnotesize",
            r"\setlength{\tabcolsep}{4pt}",
            r"\renewcommand{\arraystretch}{1.05}",
            r"\setlength{\LTleft}{0pt}",
            r"\setlength{\LTright}{0pt}",
            r"\begin{longtable}{@{}L{1.50cm}L{2.80cm}L{1.60cm}L{1.60cm}L{2.00cm}L{2.10cm}L{2.10cm}L{1.20cm}L{1.50cm}@{}}",
            rf"\caption{{Performance on the dataset: \textbf{{{dataset}}}. Bold values indicate the best execution in the respective metric.}} \\",
            r"\toprule",
            header_tex,
            r"\midrule",
            r"\endfirsthead",
            rf"\caption[]{{{dataset} (continued)}} \\",
            r"\toprule",
            header_tex,
            r"\midrule",
            r"\endhead",
            r"\bottomrule",
            r"\endfoot",
            *row_tex,
            r"\end{longtable}",
            r"\endgroup",
            "",
        ]
    )


def build_document() -> str:
    parts = [
        r"\documentclass[10pt]{article}",
        r"\usepackage[a4paper,margin=1.8cm]{geometry}",
        r"\usepackage[T1]{fontenc}",
        r"\usepackage[utf8]{inputenc}",
        r"\usepackage{booktabs}",
        r"\usepackage{longtable}",
        r"\usepackage{array}",
        r"\usepackage{pdflscape}",
        r"\usepackage{hyperref}",
        r"\usepackage{xurl}",
        r"\usepackage{caption}",
        r"\captionsetup[longtable]{labelfont=bf,labelsep=space}",
        r"\newcolumntype{L}[1]{>{\raggedright\arraybackslash}p{#1}}",
        r"\setcounter{table}{0}",
        r"\renewcommand{\thetable}{S\arabic{table}}",
        r"\makeatletter \renewcommand\l@table{\@dottedtocline{1}{1.5em}{2.3em}} \makeatother",
        rf"\title{{Supplementary Material\\Full Benchmark Tables and Ablation Profile for\\{escape_tex(PAPER_TITLE)}}}",
        rf"\author{{{escape_tex(CORRESPONDING_AUTHOR)}}}",
        r"\date{}",
        r"\begin{document}",
        r"\maketitle",
        r"\tableofcontents",
        r"\vspace{1em}",
        r"\hrule",
        r"\vspace{1em}",
        rf"\noindent \textbf{{Corresponding author.}} {escape_tex(CORRESPONDING_AUTHOR)}, {escape_tex(CORRESPONDING_AFFILIATION)}. E-mail: \path{{{CORRESPONDING_EMAIL}}}.",
        "",
        r"\noindent This supplementary document provides the complete archived benchmark tables and component-ablation summaries that underlie the summary tables and figures in the main paper. All values are exact medians over three measured runs per configuration, preceded by one warm-up run. The 7200\,s per-run timeout cutoff was applied uniformly across all algorithms.",
        "",
        r"\noindent \textbf{Metrics terminology.} \textbf{Mining (s)} refers to the strict internal algorithm elapsed time, while \textbf{Wall (s)} represents the total external process execution length. \textbf{Internal Mem} measures the JVM peak application footprint directly, while \textbf{External Mem} captures the peak Resident Set Size (RSS) recorded by the host OS. Consequently, the \textbf{Gap} column explicitly states the external-to-internal memory ratio ($\mathrm{External} / \mathrm{Internal}$), quantifying the unmanaged underlying JVM runtime overhead specific to each algorithm's garbage collection behavior and data structure allocation density.",
        "",
        r"\noindent \textbf{Status codes.} \texttt{OK} denotes a completed run. \texttt{TIMEOUT} denotes that the run exceeded the 7200\,s cutoff. \texttt{OOM} denotes an out-of-memory failure. Memory values reproduce the archived units (\texttt{MB} or \texttt{GB}) without normalization.",
        "",
        r"\noindent \textbf{Measurement note.} In a small number of BIDE+ zero-pattern runs, the SPMF internal memory logger reports \texttt{0.0 MB} despite a nonzero external RSS. These entries are rendered as \texttt{N/A} in the \textbf{Internal Mem} and \textbf{Gap} columns because they reflect an instrumentation artifact rather than true zero memory usage.",
        "",
        r"\clearpage",
        r"\begin{landscape}",
    ]

    for title, source in SOURCES:
        parts.append(rf"\section*{{{escape_tex(title)}}}")
        if title == "Multi-Itemset Archived Benchmark Tables":
            parts.append(
                r"\noindent These tables follow the manuscript naming convention and report the Java implementation used in the itemset benchmark campaigns as \textbf{TriBack-Clo}. Pattern-count mismatches that appear in these archived tables are reported as benchmark facts; the main paper's discrepancy discussion (Table~4) focuses on the subset of cases analyzed there."
            )
        parts.append("")
        for section in parse_markdown_tables(source):
            parts.append(make_table(section))

    parts.append(make_scalability_sections())
    parts.append(make_si_grid_sections())
    parts.append(make_ablation_section())
    parts.append(r"\end{landscape}")
    parts.append(r"\end{document}")
    return "\n".join(parts)


def main() -> None:
    OUTPUT.write_text(build_document(), encoding="utf-8")
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
