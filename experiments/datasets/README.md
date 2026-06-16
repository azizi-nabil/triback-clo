# Dataset Reconstruction Notes

Large benchmark datasets are intentionally not committed. This directory contains only small examples and generator configuration files.

## Real Datasets

Download the public real datasets from the SPMF dataset repository and place them under `experiments/datasets/` with the filenames expected by the scripts:

| Paper family | Expected filename | Source / note |
|---|---|---|
| Kosarak | `kosarak_sequences.txt` | SPMF dataset repository |
| Kosarak25k | `kosarak25k.txt` | First 25,000 sequences sampled from `kosarak_sequences.txt` for the low-support stress subset |
| BMS2 | `BMS2.txt` | SPMF dataset repository, BMSWebView2 sequence file |
| FIFA | `FIFA.txt` | SPMF dataset repository |
| BIKE | `BIKE.txt` | SPMF dataset repository |
| SIGN | `SIGN.txt` | SPMF dataset repository |
| MSNBC | `MSNBC_SPMF.txt` | SPMF-compatible MSNBC sequence file |
| MSNBC-small | `MSNBC.txt` | Filtered/smaller MSNBC file used by the archived benchmark scripts |

The exact script filename expectations are encoded in `experiments/run_benchmark.sh` and `experiments/run_benchmark_clofast_single.sh`.

## Synthetic Itemset-Sequence Families

The paper synthetic families use IBM-style sequence generator parameters. The public release includes:

- `ibm_corr.ntpc` — generator configuration/reference file retained from the benchmark setup
- `../generate_clofast_datasets.sh` — D5/D10/D20/D50 synthetic families
- `../generate_fig15_datasets.sh` — S/I parameter grid
- `../generate_scalability_datasets.sh` — D-scaling series
- `generate_clofast_datasets.sh` — SPMF generator helper for smaller synthetic examples

The IBM Quest generator binary is not redistributed. Place it at:

```text
experiments/IBMGenerator/gen
```

or set:

```bash
export IBM_GENERATOR=/path/to/IBMGenerator/gen
```

Then run, for example:

```bash
cd experiments
bash generate_clofast_datasets.sh
bash generate_fig15_datasets.sh
bash generate_scalability_datasets.sh
```

Generated datasets are written to `experiments/datasets/synthetic/clofast_paper/`.
