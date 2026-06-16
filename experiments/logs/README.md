# Raw Log Artifacts

The paper's reported tables were derived from archived benchmark logs and post-processing summaries. The public repository exposes the audit trail in two reproducibility layers:

1. Selected raw logs that can be inspected directly.
2. Log-derived CSV/Markdown artifacts for the broader benchmark campaign.

## Included raw logs

`experiments/logs/selected-kosarak/` contains 183 historical Kosarak benchmark logs recovered from the pre-rename benchmark campaign. The bundle includes TriBack-Clo and SPMF baseline runs for BIDE+, ClaSP, CloSpan, and CloFast across several support levels, with warmup and measured runs where available.

The file list is recorded in:

```text
experiments/logs/selected-kosarak/MANIFEST.txt
```

Raw-log availability for all run paths recorded in the public result manifests is indexed in:

```text
experiments/logs/LOG_AVAILABILITY.csv
experiments/logs/RAW_LOG_AVAILABILITY.md
```

These logs are all raw `.log` files recoverable from the local working tree and git history at public-release time. Later supplementary campaigns are represented by complete derived CSV/Markdown result artifacts when the original raw `.log` files were not available in the local archive. The repository therefore documents raw-log coverage explicitly rather than implying that every historical raw log is public.

## Included log-derived artifacts

The broader paper results are represented by the following derived artifacts:

- `experiments/results/configuration_manifest.csv` — run manifest with dataset, support, algorithm, run type, run id, output-equivalence group, and original log path
- `experiments/results/raw_run_extract.csv` — run-level extracted measurements from archived logs
- `experiments/results/run_variation_summary.csv` — retained run-to-run variation summary
- `experiments/results/memory_comparison.csv` — memory comparison extracted from archived runs
- `experiments/results/*_results.csv` and `experiments/results/BENCHMARK_RESULTS*.md` — per-dataset and aggregated result tables

## Regenerating logs

Full regenerated raw-log directories are created by the benchmark scripts under directories such as:

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
