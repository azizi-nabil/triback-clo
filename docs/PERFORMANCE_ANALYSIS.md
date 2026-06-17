# TriBack-Clo Performance Interpretation

This note summarizes the performance interpretation of the accepted Information Sciences paper. It replaces older exploratory V1/V2 notes with the final paper-aligned view.

## What The Performance Results Show

TriBack-Clo is strongest in dense, low-support, or prune-dominant regimes where candidate-free temporal pruning and compact projection state reduce live work and memory pressure. The paper reports its strongest speed and memory gains at the difficult operating points where competing implementations time out, exhaust memory, or retain much larger working structures.

The performance contribution is workload-sensitive rather than uniform:

- **Prune-dominant workloads** benefit most from Stage 1 temporal BackScan pruning.
- **Gate-heavy multi-itemset workloads** benefit from Stage 2 local/internal node gating, which avoids unnecessary exact envelope checks without pruning descendants.
- **Confirmation workloads** may show only small changes from pruning or gating; these are useful because they delimit where each component matters.
- **Low-density or high-support workloads** can leave baseline methods competitive or faster, because the search tree is already small and exact envelope checks are less amortized.

## How To Read The Memory Results

The memory improvements combine several implementation and theory choices:

- compact 4-tuple projection state;
- allocation-free stamp-array intersections;
- lazy envelope verification;
- temporal subtree pruning before child expansion;
- Java/SPMF-compatible benchmark execution.

The paper therefore treats memory savings as an empirical property of the full TriBack-Clo design. It does not claim that the witness theory alone explains every measured memory difference; the memory result should not be read as a pure theorem-only effect.

## Component Ablation Interpretation

The final component analysis separates three questions:

- `--no-prune`: how much Stage 1 temporal subtree pruning matters;
- `--no-gate`: how much Stage 2 local/internal node gating matters once forward screening remains active;
- `--eager-verify`: how many exact-envelope calls are avoided by lazy placement.

Rows that end in `TIMEOUT` are efficiency failures, not evidence of output disagreement. On workloads where compared variants complete, reported pattern counts match across variants.

## Where To Find Exact Numbers

Use the archived result artifacts rather than this narrative note for exact values:

```text
experiments/results/BENCHMARK_RESULTS.md
experiments/results/BENCHMARK_RESULTS_DUAL_MEM.md
experiments/results/BENCHMARK_RESULTS_ITEMSETS.md
experiments/results/run_variation_summary.csv
experiments/results/memory_comparison.csv
```

The Supplementary Material in the accepted paper is the authoritative formatted source for complete tables.

## Scope Boundary

Performance comparisons use public SPMF v2.64b implementations and therefore reflect both algorithmic choices and implementation-level data structures. The paper's central claim is the sound prune/gate boundary for itemset-sequences, validated by exact counts and reproducible benchmark artifacts; speedups are reported as empirical outcomes under that implementation protocol.
