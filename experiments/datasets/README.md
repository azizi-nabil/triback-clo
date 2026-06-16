# Dataset Reconstruction Notes

Large benchmark datasets are intentionally not committed. This directory contains small examples, IBMGenerator configuration files for multi-itemset synthetic datasets, and instructions for reconstructing the datasets expected by the benchmark scripts.

## Single-Itemset Real Datasets

Download the public single-itemset real datasets from the SPMF dataset repository and place them under `experiments/datasets/` with the filenames expected by the scripts:

| Paper family | Expected filename | Source / note |
|---|---|---|
| Kosarak | `kosarak_sequences.txt` | SPMF dataset repository |
| Kosarak25k | `kosarak25k.txt` | First 25,000 sequences sampled from `kosarak_sequences.txt` for the low-support stress subset |
| BMS2 | `BMS2.txt` | SPMF dataset repository, BMSWebView2 sequence file |
| FIFA | `FIFA.txt` | SPMF dataset repository |
| BIKE | `BIKE.txt` | SPMF dataset repository |
| SIGN | `SIGN.txt` | SPMF dataset repository |
| MSNBC | `MSNBC_SPMF.txt` | SPMF-compatible MSNBC sequence file |
| MSNBC-small | `MSNBC.txt` | Filtered/smaller MSNBC file used by archived benchmark scripts |

The exact script filename expectations are encoded in:

```text
experiments/run_benchmark.sh
experiments/run_benchmark_clofast_single.sh
experiments/run_benchmark_itemsets.sh
```

## Creating Kosarak25k

The benchmark scripts expect `kosarak25k.txt` as a small low-support stress subset. Recreate it from the full Kosarak file with:

```bash
cd experiments
head -n 25000 datasets/kosarak_sequences.txt > datasets/kosarak25k.txt
```

## Multi-Itemset Synthetic Families

IBMGenerator is used only for the multi-itemset synthetic benchmark families. The single-itemset real datasets above are downloaded from SPMF. The public release includes:

- `ibm_corr.ntpc` — generator configuration/reference file retained from the benchmark setup
- `../generate_clofast_datasets.sh` — D5/D10/D20/D50 synthetic families
- `../generate_fig15_datasets.sh` — S/I parameter grid
- `../generate_scalability_datasets.sh` — D-scaling series
- `generate_clofast_datasets.sh` — helper retained for smaller synthetic examples

The IBM Quest generator binary is not redistributed. Place it at:

```text
experiments/IBMGenerator/gen
```

or set:

```bash
export IBM_GENERATOR=/path/to/IBMGenerator/gen
```

Then run from the repository root:

```bash
cd experiments
bash generate_clofast_datasets.sh
bash generate_fig15_datasets.sh
bash generate_scalability_datasets.sh
```

Generated datasets are written to:

```text
experiments/datasets/synthetic/clofast_paper/
```

The generation scripts convert IBM `.data` files into the SPMF itemset-sequence format consumed by TriBack-Clo and the SPMF baselines for the multi-itemset experiments.

## Small Bundled Examples

The following small examples are committed and can be used without external downloads:

```text
experiments/datasets/test_multi.txt
experiments/datasets/example_walkthrough.txt
experiments/datasets/execution_example_test.txt
```
