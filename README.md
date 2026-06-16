# TriBack-Clo

Reproducibility repository for:

Nabil Azizi, Makhlouf Ledmi, Abdeldjalil Ledmi, Mohammed El Habib Souidi, Mohamed Boussalem, and Aboubekeur Hamdi-Cherif, "TriBack-clo: Sound triple-witness BackScan for closed pattern mining in itemset-sequences", Information Sciences, 2026, Article 123788. DOI: https://doi.org/10.1016/j.ins.2026.123788

## Scope

This repository contains the SPMF-compatible Java implementation used for the experiments reported in the paper, together with benchmark scripts, post-processing scripts, selected result tables, and small example datasets.

The earlier Scala development/reference implementation is not included in this public release because the paper experiments were performed with the Java JAR under the SPMF-compatible benchmark protocol.

## Contents

- `triback-clo-java/` — Java TriBack-Clo implementation and build script
- `experiments/` — benchmark, ablation, parsing, plotting, and result-generation scripts
- `experiments/results/` — selected archived result tables used for paper reporting
- `experiments/datasets/` — small example inputs and dataset reconstruction notes
- `experiments/SPMF_BASELINE.md` — exact SPMF baseline configuration used by the scripts
- `experiments/logs/` — selected raw logs, artifact notes, and regeneration instructions
- `docs/` — technical notes and verification material
- `CITATION.cff` — citation metadata for the published article

Large benchmark datasets are not committed. A selected raw-log bundle is included under `experiments/logs/selected-kosarak/`, and log-derived CSV/MD artifacts are included under `experiments/results/`. Public real datasets should be downloaded from the SPMF dataset repository. Synthetic datasets can be regenerated from the provided scripts/configurations; see `experiments/datasets/README.md` and `experiments/logs/README.md`.

## Requirements

- Java 21 or newer
- Bash
- Python 3 for experiment post-processing scripts
- `spmf.jar` for benchmark baselines and Java compilation against SPMF classes

Place SPMF v2.64b as:

    experiments/spmf.jar

See `experiments/SPMF_BASELINE.md` for baseline commands and JVM policy.

## Build

Run:

    cd triback-clo-java
    bash build.sh

This creates:

    triback-clo-java/triback-clo.jar

## Run A Small Example

From the repository root:

    java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar \
      ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
      experiments/datasets/test_multi.txt /tmp/triback-output.txt 2

Use `/dev/null` as the output path for count-only benchmark runs:

    java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar \
      ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
      experiments/datasets/test_multi.txt /dev/null 2

## Experiments

The paper benchmark scripts use the Java JAR in `triback-clo-java/triback-clo.jar` and SPMF in `experiments/spmf.jar`.

See:

    experiments/README.md

## Citation

See `CITATION.cff`.
