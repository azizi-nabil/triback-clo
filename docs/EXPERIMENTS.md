# TriBack-Clo Experiment Notes

This note summarizes the experiment scope of the accepted Information Sciences paper and points to the public reproducibility artifacts. Older exploratory notes about APV switching, PCloFAST comparisons, and incomplete closure checks have been superseded by the final Java/SPMF benchmark protocol.

## Final Experiment Scope

The accepted paper evaluates TriBack-Clo as an exact closed sequential pattern miner for itemset-sequences under canonical S/I growth. The experiments keep correctness and performance claims separate:

- **Correctness audits** compare pattern counts and inspect discrepancy cases on itemset-sequence datasets.
- **Runtime and memory sweeps** compare TriBack-Clo against SPMF v2.64b baselines: BIDE+, ClaSP, CloSpan, and CloFAST.
- **Synthetic multi-itemset families** test dense itemset-sequence regimes generated with IBMGenerator-style parameters.
- **Scalability and ablation studies** isolate support threshold, density, sequence-count, pruning, node-gating, and lazy-verification effects.

The public reproduction path is Java-first and SPMF-compatible. Build and run commands are documented in the top-level `README.md`, `REPRODUCIBILITY.md`, and `experiments/README.md`.

## Artifact Locations

Use these files for the final, paper-aligned data trail:

```text
experiments/results/BENCHMARK_RESULTS.md
experiments/results/BENCHMARK_RESULTS_DUAL_MEM.md
experiments/results/BENCHMARK_RESULTS_ITEMSETS.md
experiments/results/*.csv
experiments/logs/LOG_AVAILABILITY.csv
experiments/logs/RAW_LOG_AVAILABILITY.md
```

The selected raw logs under `experiments/logs/selected-kosarak/` are included for direct inspection. Broader historical campaigns are represented through derived CSV/Markdown artifacts and the log-availability manifest.

## Dataset Sources

- Real single-itemset datasets are public SPMF datasets and are not committed because of size and source ownership.
- Synthetic multi-itemset datasets are regenerated with the scripts in `experiments/` using an external IBMGenerator binary.
- Small examples under `experiments/datasets/` support smoke testing and documentation examples.

See `experiments/datasets/README.md` for filenames and reconstruction commands.

## Main Scientific Reading Of The Experiments

The final results support the paper's theory-driven interpretation:

1. Temporal BackScan pruning is decisive in prune-dominant regimes and can prevent timeouts or reduce DFS traversal substantially.
2. Local/internal witnesses are current-node gates, not subtree-pruning rules; their benefit is workload-dependent and strongest in multi-itemset regimes with substantial gating activity.
3. Lazy envelope verification avoids exact checks for temporally pruned, forward-nonclosed, or node-gated nodes while preserving exact output.
4. Memory stability comes from the compact projection state, reusable stamp arrays, and Java implementation choices; it should be interpreted as a property of the full TriBack-Clo design, not as a pure theorem-only effect.
5. Baseline discrepancies involving the audited SPMF BIDE+ implementation are correctness findings for that implementation/version, not a claim about every possible BIDE-family implementation.

## Current Limitations

The accepted paper is intentionally scoped to exact, unconstrained closed mining under canonical PrefixSpan-style S/I growth. Gap constraints, streaming/incremental updates, approximate support, top-k mining, and representation-driven integrations require separate correctness arguments.
