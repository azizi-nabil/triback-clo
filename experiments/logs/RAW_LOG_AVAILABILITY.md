# Raw Log Availability

This file records the public availability of raw experiment logs for the TriBack-Clo reproducibility package.

## Status

- Public raw `.log` files included in this repository: 183
- Availability rows marked `raw-log-public`: 183
- Availability rows marked `derived-record-public-only`: 3826

All raw `.log` files recoverable from the local working tree and git history at release time are included under:

```text
experiments/logs/selected-kosarak/
```

The later supplementary campaigns are represented by complete derived records in:

```text
experiments/results/configuration_manifest.csv
experiments/results/raw_run_extract.csv
experiments/results/run_variation_summary.csv
experiments/results/memory_comparison.csv
experiments/results/*_results.csv
experiments/results/BENCHMARK_RESULTS*.md
```

For those later campaigns, the original raw `.log` files named in `configuration_manifest.csv` and `raw_run_extract.csv` were not present in the local working tree or git history when this public package was prepared. They are therefore marked `derived-record-public-only` in `LOG_AVAILABILITY.csv` rather than silently omitted.

## Machine-readable index

See:

```text
experiments/logs/LOG_AVAILABILITY.csv
```

The `availability` column uses:

- `raw-log-public`: a raw `.log` file is present in this repository.
- `derived-record-public-only`: the run is present through derived CSV/Markdown result artifacts, but the original raw `.log` file was not available for publication from the local archive.

To regenerate fresh raw logs for these rows, rebuild `triback-clo-java/triback-clo.jar`, place SPMF v2.64b at `experiments/spmf.jar`, reconstruct datasets as described in `experiments/datasets/README.md`, and run the corresponding benchmark scripts.
