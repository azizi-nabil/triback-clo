# Component Ablation Context

Last updated: 2026-03-30

This note captures the reasoning, settings, environment caveats, and current run status for the manuscript subsection `Component Contribution Analysis`. It is intended as a handoff file for continuing the study on another machine or in a new chat.

## Goal

Produce a journal-ready ablation study for TriBack-Clo by rerunning `Full`, `NoPrune`, and `NoGate` on a single software/hardware stack, then updating the paper with evidence drawn from the validated component-analysis profile.

## Important Environment Note

Do not mix timing or memory results across the older Rocky Linux runs and the new Debian runs.

- Old main benchmark environment in the manuscript:
  - Rocky Linux 9.7
  - HP Z8 G4 Workstation
  - 2 x Xeon Platinum 8160
  - Reported in the paper at `docs/sn-article-template/triback-clo-paper.tex`
- Current rerun environment:
  - Debian 13 (trixie)
  - HP Z8 G4 Workstation
  - 2 x Xeon Platinum 8160

Safe to compare across OS:
- `Pattern count`
- `Nodes visited`
- `Subtrees pruned`
- `Nodes gated`

Not safe to mix in one final timing or memory table:
- runtime
- external memory / MaxRSS
- JVM memory figures used as timing-memory evidence

Conclusion:
- Use old logs to choose datasets and sanity-check counters.
- For the final ablation table, rerun all variants on the same stack.

## Recommended Profiles

The ablation runner is:

`experiments/run_component_contribution_analysis.sh`

Profiles:

- `paper`
  - exact reproduction of the earlier manuscript table
  - retained for reproducibility and historical comparison
- `journal`
  - recommended core study for the main paper
  - best balance of strength vs runtime
- `full`
  - broader confirmation study for stronger supplementary evidence

## Selected Datasets

### Journal profile

These are the best core datasets selected from the archived logs because they activate pruning and/or gating strongly enough to support real conclusions.

1. `SIGN 1%`
   - role: strong Stage 1 pruning case in single-itemset mining
   - archived full counters: `79,803,670` visited, `12,112,103` pruned, `0` gated
   - source: `experiments/logs_ablation/TriBack-Clo_SIGN_0.01_full_20260329_171944.log`

2. `Kosarak25k 0.05%`
   - role: second prune-dominated low-support single-itemset case
   - archived full counters: `28,462,200` visited, `22,491,700` pruned, `0` gated
   - source: `experiments/logs/TriBack-Clo_Kosarak25k_0.0005_run2_20260111_231217.log`

3. `D20C20 0.1%`
   - role: mixed multi-itemset case where both pruning and gating matter at scale
   - archived full counters: `53,518,876` visited, `17,006,431` pruned, `6,996,211` gated
   - source: `experiments/logs_itemsets/TriBack-Clo-Java_D20C20_0.001_run2_20260120_113319.log`

4. `D5N1 0.4%`
   - role: gating-heavy multi-itemset case
   - archived full counters: `31,904,263` visited, `398,097` pruned, `15,693,152` gated
   - source: `experiments/logs_itemsets/TriBack-Clo-Java_D5N1_0.004_run2_20260114_165858.log`

### Full profile additions

These are confirmation cases added for broader evidence.

5. `BMS2 0.005%`
   - extra prune-dominated single-itemset case
   - archived full counters: `30,341,774` visited, `11,437,291` pruned, `0` gated
   - source: `experiments/logs/TriBack-Clo_BMS2_0.00005_run2_20260111_231217.log`

6. `D20C30 0.1%`
   - strongest mixed multi-itemset case overall, but very expensive
   - archived full counters: `178,768,304` visited, `38,216,450` pruned, `34,204,115` gated
   - source: `experiments/logs_itemsets/TriBack-Clo-Java_D20C30_0.001_run2_20260120_190943.log`

7. `D20C60 0.5%`
   - gating-heavy confirmation in the D20Cx family
   - archived full counters: `2,238,901` visited, `4,286` pruned, `138,284` gated
   - source: `experiments/logs_itemsets/TriBack-Clo-Java_D20C60_0.005_run2_20260123_200636.log`

8. `D5N1.6 0.6%`
   - smaller gating-heavy confirmation case
   - archived full counters: `381,718` visited, `1,779` pruned, `79,363` gated
   - source: `experiments/logs_itemsets/TriBack-Clo-Java_D5N1.6_0.006_run*.log`

## Datasets Deliberately Avoided

Avoid these for the main ablation argument because both counters are usually zero or nearly zero.

- `D10C* 40%` density sweep
- scalability `D50/D150/D300 ...` workloads at current minsup
- most `MSNBC` points
- `FIFA` for component analysis
- many high-support synthetic points

Reason:
- they often have tiny DFS trees
- `Subtrees pruned = 0`
- `Nodes gated = 0`
- they do not support strong component-level conclusions

## Current Runner Behavior

Script:

`bash experiments/run_component_contribution_analysis.sh --profile <profile>`

Default settings:

- `1` warmup run
- `3` measured runs
- `7200 s` timeout per run

Outputs:

- logs: `experiments/logs_ablation/<timestamp>/`
- raw CSV: `experiments/results/component_ablation_runs_<timestamp>.csv`
- summary CSV: `experiments/results/component_ablation_summary_<timestamp>.csv`

Useful commands:

```bash
# Recommended main-paper study
bash experiments/run_component_contribution_analysis.sh --profile journal

# Broader supplementary-strength study
bash experiments/run_component_contribution_analysis.sh --profile full

# Reproduce the earlier manuscript table only
bash experiments/run_component_contribution_analysis.sh --profile paper

# Show cases without running them
bash experiments/run_component_contribution_analysis.sh --profile journal --list
```

## Current Run Status

As of this note, the following long run was started on Debian:

```bash
bash experiments/run_component_contribution_analysis.sh --profile full
```

Timestamp:

- `20260330_230918`

Expected outputs:

- logs: `experiments/logs_ablation/20260330_230918/`
- raw CSV: `experiments/results/component_ablation_runs_20260330_230918.csv`
- summary CSV: `experiments/results/component_ablation_summary_20260330_230918.csv`

## Archived Old-Machine Full Baselines

These values are from the older archived benchmark logs and correspond to the `Full` baseline for the datasets used by `--profile full`. They are useful for sanity checking and historical comparison, but they should not be mixed with new Debian `NoPrune` / `NoGate` timings in the final ablation table.

| Dataset | Ratio | Old timestamp set | Wall (s) | Mining (s) | Internal peak mem (MB) | Patterns | Nodes visited | Pruned | Gated |
|---------|-------|-------------------|----------|------------|------------------------|----------|---------------|--------|-------|
| SIGN | 0.01 | `20260112_163940` | 287.680 | 287.574 | 1559.755 | 37,265,723 | 79,803,670 | 12,112,103 | 0 |
| Kosarak25k | 0.0005 | `20260111_231217` | 89.990 | 89.846 | 801.434 | 211,039 | 28,462,200 | 22,491,700 | 0 |
| D20C20 | 0.001 | `20260120_113319` | — | 706.454 | 1488.218 | 1,464,711 | 53,518,876 | 17,006,431 | 6,996,211 |
| D5N1 | 0.004 | `20260114_165858` | — | 534.157 | 801.434 | 2,906,522 | 31,904,263 | 398,097 | 15,693,152 |
| BMS2 | 0.00005 | `20260111_231217` | 44.890 | 44.710 | 801.434 | 1,196,295 | 30,341,774 | 11,437,291 | 0 |
| D20C30 | 0.001 | `20260120_190943` | — | 3387.995 | 2494.832 | 4,951,322 | 178,768,304 | 38,216,450 | 34,204,115 |
| D20C60 | 0.005 | `20260123_200636` | — | 694.349 | 303.898 | 1,223,050 | 2,238,901 | 4,286 | 138,284 |
| D5N1.6 | 0.006 | `20260114_165858` | — | 22.392 | 209.434 | 236,046 | 381,718 | 1,779 | 79,363 |

Representative source logs:

- `experiments/logs/TriBack-Clo_SIGN_0.01_run1_20260112_163940.log`
- `experiments/logs/TriBack-Clo_Kosarak25k_0.0005_run1_20260111_231217.log`
- `experiments/logs_itemsets/TriBack-Clo-Java_D20C20_0.001_run1_20260120_113319.log`
- `experiments/logs_itemsets/TriBack-Clo-Java_D5N1_0.004_run1_20260114_165858.log`
- `experiments/logs/TriBack-Clo_BMS2_0.00005_run1_20260111_231217.log`
- `experiments/logs_itemsets/TriBack-Clo-Java_D20C30_0.001_run1_20260120_190943.log`
- `experiments/logs_itemsets/TriBack-Clo-Java_D20C60_0.005_run1_20260123_200636.log`
- `experiments/logs_itemsets/TriBack-Clo-Java_D5N1.6_0.006_run1_20260114_165858.log`

## Runtime Expectations

Approximate lower-bound estimates from archived full-mode runtimes:

- `journal` profile: about `5` hours
- `full` profile: about `19` hours

Real runtime can be higher because `NoPrune` and `NoGate` may be slower than `Full`.

## Known Issue Already Fixed

Earlier ablation batch:

- `experiments/logs_ablation/20260330_225444/`

is excluded from final evidence because the archived run was incomplete or invalid.

Cause:
- the runner assumed `/usr/bin/time` existed
- on Debian this path was missing
- some runs failed before Java started

Fix already applied:
- the script now detects an external `time` binary if available
- otherwise it falls back to internal wall-clock timing
- `--skip-existing` now ignores broken `ERROR` logs when reusing prior runs

## How To Resume Safely

If the current Debian run is interrupted and you want to continue on the same stack:

```bash
bash experiments/run_component_contribution_analysis.sh --profile full --skip-existing
```

Use `--skip-existing` only for resuming or exploratory work on the same stack.

For the final ablation table:
- prefer a clean same-stack run
- do not mix reused `Full` results from another OS with new variant runs

## What To Do After The Run Finishes

1. Open the new summary CSV in `experiments/results/`
2. Identify the strongest cases for the main-paper table
3. Update `docs/sn-article-template/triback-clo-paper.tex`
4. Regenerate the supplementary appendix if the ablation table changes materially

Expected likely final paper subset:

- `SIGN 1%`
- `Kosarak25k 0.05%`
- `D20C20 0.1%`
- `D5N1 0.4%`

## Minimal Handoff For A New Chat

If starting a new chat, provide this summary:

- We are revising the `Component Contribution Analysis` subsection.
- Earlier `SIGN + D20C50` evidence is retained only as historical context.
- Stronger selected datasets are `SIGN 1%`, `Kosarak25k 0.05%`, `D20C20 0.1%`, and `D5N1 0.4%`.
- Final timed comparisons should be reported from one OS stack only.
- Current full ablation run started on Debian at timestamp `20260330_230918`.
- Main runner is `experiments/run_component_contribution_analysis.sh`.
- Final inputs for the paper should come from the newest `component_ablation_summary_*.csv`.
