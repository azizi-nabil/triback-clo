# Raw Log Artifacts

The paper states that complete raw logs were used to derive all reported tables and figures. The public repository includes the following log-derived artifacts:

- `experiments/results/configuration_manifest.csv` — run manifest with dataset, support, algorithm, run type, run id, output-equivalence group, and original log path
- `experiments/results/raw_run_extract.csv` — run-level extracted measurements from archived logs
- `experiments/results/run_variation_summary.csv` — retained run-to-run variation summary
- `experiments/results/memory_comparison.csv` — memory comparison extracted from the archived runs
- `experiments/results/*_results.csv` and `experiments/results/BENCHMARK_RESULTS*.md` — per-dataset and aggregated result tables

The full raw log directories from the original campaigns are large and are not committed here. The scripts regenerate logs under directories such as:

```text
experiments/logs/
experiments/logs_itemsets/
experiments/logs_ablation/
experiments/logs_fig15/
experiments/logs_scalability_D/
```

To regenerate representative raw logs, first build `triback-clo-java/triback-clo.jar`, place SPMF v2.64b at `experiments/spmf.jar`, reconstruct the datasets as described in `experiments/datasets/README.md`, and run one of the benchmark scripts, for example:

```bash
cd experiments
bash run_benchmark.sh SIGN quick
bash run_component_contribution_analysis.sh --profile paper --mode quick
```

The generated `.log` files can then be parsed with:

```bash
python parse_logs.py
python reconstruct_manifest.py
python scripts/generate_supplementary_results.py
```
