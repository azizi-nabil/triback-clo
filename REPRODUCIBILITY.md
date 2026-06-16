# Reproducibility Scope

This document explains what the public TriBack-Clo repository supports for the published Information Sciences article.

## Article

Nabil Azizi, Makhlouf Ledmi, Abdeldjalil Ledmi, Mohammed El Habib Souidi, Mohamed Boussalem, and Aboubekeur Hamdi-Cherif, "TriBack-clo: Sound triple-witness BackScan for closed pattern mining in itemset-sequences", Information Sciences, 2026, Article 123788. DOI: https://doi.org/10.1016/j.ins.2026.123788

## Public Claim Supported By This Repository

The repository supports independent inspection and rerun of the experimental workflow used in the paper:

- Java implementation used for the paper experiments.
- SPMF-compatible entry point.
- SPMF baseline command policy.
- Benchmark scripts for real and synthetic datasets.
- Synthetic dataset generation scripts and IBMGenerator parameterization.
- Post-processing scripts for logs, manifests, result tables, and supplementary summaries.
- Archived CSV/Markdown result artifacts.
- Selected raw logs and a raw-log availability manifest.
- Dataset reconstruction instructions.

## Reproduction Levels

### 1. Smoke Test

Use the bundled small examples to confirm the Java build and command-line entry point:

```bash
cd triback-clo-java
bash build.sh
cd ..
java -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar \
  ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  experiments/datasets/test_multi.txt /tmp/triback-output.txt 2
```

### 2. Result-Artifact Audit

Inspect the archived CSV/Markdown artifacts under:

```text
experiments/results/
experiments/logs/LOG_AVAILABILITY.csv
experiments/logs/RAW_LOG_AVAILABILITY.md
```

This supports checking reported counts, timings, statuses, and which raw logs are public.

### 3. Representative Rerun

Reconstruct one dataset, place `experiments/spmf.jar`, and run a quick benchmark:

```bash
cd experiments
bash run_benchmark.sh SIGN quick
```

For ablation smoke testing:

```bash
bash run_component_contribution_analysis.sh --profile paper --mode quick
```

### 4. Full Campaign Regeneration

Full regeneration requires the real datasets, SPMF v2.64b, IBMGenerator for synthetic multi-itemset families, and substantial runtime. The main entry points are listed in `experiments/README.md`.

## Dataset Availability

Real single-itemset benchmark datasets are external public datasets from the SPMF dataset repository. They are not committed because of size and source ownership. Expected filenames are documented in `experiments/datasets/README.md`.

Synthetic multi-itemset datasets were generated with IBMGenerator-style parameters. The repository includes the scripts and parameterization used to regenerate them. IBMGenerator itself is an external dependency available at:

```text
https://github.com/zakimjz/IBMGenerator
```

The IBMGenerator binary/source is not redistributed as part of this MIT-licensed repository.

## Raw Logs

The paper's tables were derived from archived benchmark logs and post-processing summaries. This public repository includes:

- selected raw logs under `experiments/logs/selected-kosarak/`;
- complete derived run-level and summary artifacts under `experiments/results/`;
- `experiments/logs/LOG_AVAILABILITY.csv`, marking which manifest rows have a public raw log and which are represented by derived public records only.

This distinction is intentional: the repository does not claim that every historical raw log is included.

## License Boundary

The MIT license in this repository applies to the TriBack-Clo code and repository-authored scripts/docs. External dependencies such as SPMF and IBMGenerator remain under their own distribution terms.
