# TriBack-Clo Experiments

This folder contains the benchmark scripts, post-processing scripts, archived result artifacts, selected raw logs, and dataset reconstruction notes used for the TriBack-Clo paper.

The public release is Java-first: all paper experiment commands use `triback-clo-java/triback-clo.jar` and the SPMF-compatible entry point. For the package-level scope statement, see `../REPRODUCIBILITY.md`.

## Quick Start

From the repository root:

```bash
# 1. Build TriBack-Clo
cd triback-clo-java
bash build.sh
cd ..

# 2. Add SPMF v2.64b for baselines and compilation support
cp /path/to/spmf.jar experiments/spmf.jar

# 3. Run a small bundled example
java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar \
  ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  experiments/datasets/test_multi.txt /tmp/triback-output.txt 2
```

For full benchmark reproduction, first reconstruct the datasets described in `experiments/datasets/README.md`. Full campaigns can be long-running; use the `quick` modes first to validate the local setup.

## Reproducibility Map

| Purpose | Main script / artifact | Output location |
|---|---|---|
| Real-dataset benchmark sweep | `bash run_benchmark.sh DATASET [quick]` | `results/benchmark_*.csv`, `logs/` |
| Complete real-dataset sweep | `bash run_benchmark.sh all` | `results/benchmark_*.csv`, `logs/` |
| Missing/continuation runs | `bash run_missing_benchmarks.sh` | `results/`, `logs/` |
| Multi-itemset synthetic benchmark | `bash run_benchmark_itemsets.sh` | `results/benchmark_itemsets_*.csv`, `logs_itemsets/` |
| Continue multi-itemset runs | `bash run_benchmark_itemsets_continue.sh` | `results/benchmark_itemsets_continue_*.csv`, `logs_itemsets/` |
| Component ablation | `bash run_component_contribution_analysis.sh --profile paper` | `results/component_ablation_*.csv`, `logs_ablation/` |
| Journal-strength ablation | `bash run_component_contribution_analysis.sh --profile journal --skip-existing` | `results/component_ablation_*.csv`, `logs_ablation/` |
| Eager-verification ablation | `bash run_eager_verification_ablation.sh` | `results/eager_verification_ablation_*.csv`, `logs_eager_verify/` |
| S/I parameter grid | `bash generate_fig15_datasets.sh` then `bash run_benchmark_fig15.sh` | `logs_fig15/`, supplementary tables |
| D-scaling series | `bash generate_scalability_datasets.sh` then `bash run_benchmark_scalability_D.sh` | `logs_scalability_D/`, supplementary tables |
| Supplementary table generation | `python scripts/generate_supplementary_results.py` | generated supplementary tables/figures |
| Log parsing / manifest reconstruction | `python parse_logs.py`, `python reconstruct_manifest.py` | `results/*.csv` |

Use `--help` on scripts that support it, especially `run_component_contribution_analysis.sh`.

## Required Inputs

- `triback-clo-java/triback-clo.jar`: built with `cd triback-clo-java && bash build.sh`
- `experiments/spmf.jar`: user-provided SPMF v2.64b jar
- single-itemset real datasets from the SPMF dataset repository, placed under `experiments/datasets/`
- IBMGenerator only for the multi-itemset synthetic families; obtain it from `https://github.com/zakimjz/IBMGenerator`, build `gen`, and place it at `experiments/IBMGenerator/gen` or expose it through `IBM_GENERATOR`

For exact baseline policy and JVM settings, see `experiments/SPMF_BASELINE.md`.

## Folder Structure

```text
experiments/
├── datasets/           # Small examples plus user-reconstructed benchmark datasets
│   ├── test_multi.txt
│   ├── example_walkthrough.txt
│   ├── kosarak_sequences.txt      # user-provided, not committed
│   ├── kosarak25k.txt             # derived from Kosarak, not committed
│   ├── BMS2.txt                   # user-provided, not committed
│   ├── FIFA.txt                   # user-provided, not committed
│   ├── BIKE.txt                   # user-provided, not committed
│   ├── SIGN.txt                   # user-provided, not committed
│   ├── MSNBC_SPMF.txt             # user-provided, not committed
│   └── synthetic/clofast_paper/   # generated synthetic datasets
├── logs/               # Selected raw logs and generated runtime logs
├── logs_itemsets/      # Generated multi-itemset logs
├── logs_ablation/      # Generated ablation logs
├── logs_fig15/         # Generated S/I-grid logs
├── logs_scalability_D/ # Generated D-scaling logs
├── results/            # Archived and regenerated CSV/Markdown result artifacts
├── scripts/            # Supplementary table/plot generation scripts
├── spmf.jar            # User-provided SPMF v2.64b jar
└── README.md
```

## Single-Itemset Real Dataset Downloads

Download the single-itemset real benchmark datasets from the SPMF dataset repository and place them under `experiments/datasets/` using the names in `datasets/README.md`.

The main expected filenames are:

```text
kosarak_sequences.txt
kosarak25k.txt
BMS2.txt
FIFA.txt
BIKE.txt
SIGN.txt
MSNBC_SPMF.txt
MSNBC.txt
```

Large real single-itemset datasets are intentionally not committed to GitHub.

## Multi-Itemset Synthetic Data With IBMGenerator

IBMGenerator is used only for the multi-itemset synthetic families. The single-itemset real datasets above are downloaded from SPMF, not generated. The IBM Quest generator binary is not redistributed in this repository; obtain it from the external IBMGenerator repository: `https://github.com/zakimjz/IBMGenerator`.

Place the binary at:

```text
experiments/IBMGenerator/gen
```

or set:

```bash
export IBM_GENERATOR=/path/to/IBMGenerator/gen
```

Then run from `experiments/`:

```bash
bash generate_clofast_datasets.sh
bash generate_fig15_datasets.sh
bash generate_scalability_datasets.sh
```

Generated files are written under:

```text
experiments/datasets/synthetic/clofast_paper/
```

## Manual Runs

```bash
# TriBack-Clo
java -Xms16g -Xmx80g -cp ../triback-clo-java/triback-clo.jar:spmf.jar \
  ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  datasets/FIFA.txt /dev/null 10%

# SPMF BIDE+
java -Xms16g -Xmx80g -jar spmf.jar run BIDE+ datasets/FIFA.txt output.txt 10%

# SPMF ClaSP
java -Xms16g -Xmx80g -jar spmf.jar run ClaSP datasets/FIFA.txt output.txt 10%

# SPMF CloSpan
java -Xms16g -Xmx80g -jar spmf.jar run CloSpan datasets/FIFA.txt output.txt 10%
```

Use `/dev/null` for count-only timing runs.

## Results And Logs

Most paper-ready shell runners save CSV files under `results/` and raw logs under `logs*` directories. The public repository includes:

- archived CSV/Markdown result artifacts under `results/`
- selected historical raw Kosarak logs under `logs/selected-kosarak/`
- a machine-readable raw-log availability index in `logs/LOG_AVAILABILITY.csv`
- an explanation of raw-log coverage in `logs/RAW_LOG_AVAILABILITY.md`

See `experiments/logs/README.md` for details.

## Visualization And Supplementary Results

```bash
python scripts/plot_results.py
python scripts/generate_supplementary_results.py
```

The plotting scripts consume the CSV artifacts in `results/` and regenerated log folders when present.
