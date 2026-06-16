# TriBack-Clo

Reproducibility repository for:

Nabil Azizi et al., "TriBack-clo: Sound triple-witness BackScan for closed pattern mining in itemset-sequences", Information Sciences, 2026, Article 123788. DOI: https://doi.org/10.1016/j.ins.2026.123788

## Contents

- TriBack-Clo Scala implementation
- SPMF-compatible Java implementation
- Benchmark and post-processing scripts
- Selected result tables
- Small example datasets

Large benchmark datasets are not committed. Public real datasets should be downloaded from the SPMF dataset repository, and synthetic datasets can be regenerated from the provided scripts/configurations.

## Build

Run:

    sbt assembly

This creates:

    target/scala-2.13/triback-clo.jar

## Run

Run:

    java -cp target/scala-2.13/triback-clo.jar tribackclo.TriBackClo_Main --input experiments/datasets/test_multi.txt --minsup 2

## Experiments

See experiments/README.md.

## Citation

See CITATION.cff.
