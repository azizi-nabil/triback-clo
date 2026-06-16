# TriBack-Clo

Reproducibility repository for the Information Sciences article:

Nabil Azizi, Makhlouf Ledmi, Abdeldjalil Ledmi, Mohammed El Habib Souidi, Mohamed Boussalem, and Aboubekeur Hamdi-Cherif, "TriBack-clo: Sound triple-witness BackScan for closed pattern mining in itemset-sequences", Information Sciences, 2026, Article 123788. DOI: https://doi.org/10.1016/j.ins.2026.123788

## Purpose

TriBack-Clo is an exact closed sequential pattern miner for itemset-sequences. The paper introduces a triple-witness BackScan boundary that separates subtree-safe temporal witnesses from intra-itemset witnesses that are safe only for current-node gating, then validates the implementation against SPMF baselines and independently audited pattern counts.

This repository is the public reproducibility package for the published article. It contains the SPMF-compatible Java implementation used in the experiments, benchmark and post-processing scripts, archived result artifacts, selected raw logs, dataset reconstruction notes, and citation metadata.

The earlier Scala development/reference implementation is not included in this public release because the paper experiments were performed with the Java JAR under the SPMF-compatible benchmark protocol.

## Repository Contents

| Path | Purpose |
|---|---|
| `triback-clo-java/` | Java TriBack-Clo implementation and build script |
| `experiments/` | Benchmark, ablation, parsing, plotting, and result-generation scripts |
| `experiments/results/` | Archived CSV/Markdown result artifacts used for paper reporting |
| `experiments/datasets/` | Small bundled examples and dataset reconstruction notes |
| `experiments/SPMF_BASELINE.md` | SPMF v2.64b baseline commands, JVM policy, and caveats |
| `experiments/logs/` | Selected raw logs, raw-log availability index, and regeneration notes |
| `docs/` | Technical notes, worked examples, and historical verification material |
| `REPRODUCIBILITY.md` | Scope of the public reproducibility package |
| `CITATION.cff` | Citation metadata for the software and associated article |
| `LICENSE` | MIT license for the TriBack-Clo repository code |

## What Is Included And What Is External

Included:

- Java source code for TriBack-Clo.
- Build script for `triback-clo-java/triback-clo.jar`.
- Paper benchmark and ablation scripts.
- Post-processing scripts for logs, manifests, and supplementary tables.
- Archived result tables and run-level CSV artifacts.
- Selected raw Kosarak benchmark logs and a machine-readable raw-log availability index.
- Small example datasets for smoke testing.
- Synthetic-data generation scripts and generator parameterization.

External by design:

- Large real datasets: download from the SPMF dataset repository and place under `experiments/datasets/`.
- SPMF v2.64b: place the jar at `experiments/spmf.jar`.
- IBMGenerator: obtain it from https://github.com/zakimjz/IBMGenerator, build it with `make`, and place the binary at `experiments/IBMGenerator/gen` or set `IBM_GENERATOR`.
- Full historical raw-log directories: selected raw logs are public; broader campaigns are represented through derived CSV/Markdown artifacts and `experiments/logs/LOG_AVAILABILITY.csv`.

## Requirements

- Java 21 or newer.
- Bash.
- Python 3 for post-processing scripts.
- `spmf.jar` v2.64b for SPMF baselines and Java compilation against SPMF classes.
- IBMGenerator only for regenerating the multi-itemset synthetic datasets.

Place SPMF v2.64b as:

```text
experiments/spmf.jar
```

See `experiments/SPMF_BASELINE.md` for baseline commands and JVM policy.

## Build

From the repository root:

```bash
cd triback-clo-java
bash build.sh
cd ..
```

This creates:

```text
triback-clo-java/triback-clo.jar
```

## Run A Small Example

```bash
java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar \
  ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  experiments/datasets/test_multi.txt /tmp/triback-output.txt 2
```

Use `/dev/null` as the output path for count-only benchmark runs:

```bash
java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar \
  ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  experiments/datasets/test_multi.txt /dev/null 2
```

## Reproduce Experiments

Start with:

```text
experiments/README.md
experiments/datasets/README.md
experiments/SPMF_BASELINE.md
experiments/logs/README.md
REPRODUCIBILITY.md
```

Typical flow:

1. Build `triback-clo-java/triback-clo.jar`.
2. Place SPMF v2.64b at `experiments/spmf.jar`.
3. Download real single-itemset datasets from SPMF using the expected filenames.
4. For synthetic multi-itemset experiments, build IBMGenerator externally and place `gen` at `experiments/IBMGenerator/gen`.
5. Run the benchmark script for the desired campaign.
6. Parse logs and regenerate tables with the scripts under `experiments/` and `experiments/scripts/`.

## Citation

If you use this code or reproduce the experiments, cite the associated article. Citation metadata is available in `CITATION.cff`.
