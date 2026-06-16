# SPMF Baseline Configuration

The paper audits TriBack-Clo against the public SPMF closed sequential pattern mining implementations using SPMF v2.64b.

## Required Jar

Place the audited SPMF jar at:

```text
experiments/spmf.jar
```

The jar is not redistributed in this repository. Download SPMF from the official SPMF project website and use version v2.64b, matching the paper.

## JVM And Run Policy

The main benchmark campaign used:

```text
OpenJDK 21
-Xms16g -Xmx80g
1 warm-up run
3 measured runs
7200 s timeout per run
```

The shell runners encode this policy directly:

```text
experiments/run_benchmark.sh
experiments/run_benchmark_clofast_single.sh
experiments/run_benchmark_itemsets.sh
experiments/run_component_contribution_analysis.sh
```

## Baseline Commands

SPMF baselines are invoked through their public command-line interface with default algorithm parameters:

```bash
java -Xms16g -Xmx80g -jar experiments/spmf.jar run BIDE+  INPUT OUTPUT MINSUP%
java -Xms16g -Xmx80g -jar experiments/spmf.jar run ClaSP  INPUT OUTPUT MINSUP%
java -Xms16g -Xmx80g -jar experiments/spmf.jar run CloSpan INPUT OUTPUT MINSUP%
java -Xms16g -Xmx80g -jar experiments/spmf.jar run CloFast INPUT OUTPUT MINSUP%
```

TriBack-Clo is invoked through the SPMF-compatible Java class:

```bash
java -Xms16g -Xmx80g \
  -cp triback-clo-java/triback-clo.jar:experiments/spmf.jar \
  ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  INPUT OUTPUT MINSUP%
```

Use `/dev/null` as `OUTPUT` for count-only timing runs, as done in the benchmark scripts.

## Reproducibility Notes

The paper reports implementation-inclusive comparisons against public SPMF implementations. No baseline-specific parameter tuning was applied beyond the common JVM and timeout policy above.
