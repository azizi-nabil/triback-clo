# TriBack-Clo Experiments

## Quick Start

```bash
# 1. Download/reconstruct datasets (see datasets/README.md)
# 2. Copy SPMF v2.64b to this folder as spmf.jar
# 3. Build the Java TriBack-Clo JAR
cd ../triback-clo-java && bash build.sh

# 4. Run experiments
python run_experiments.py --experiment A
./run_component_contribution_analysis.sh --profile journal --skip-existing
python run_experiments.py --experiment all
```

For exact baseline policy, dataset reconstruction, raw-log artifacts, and ablation notes, see:

- `experiments/SPMF_BASELINE.md`
- `experiments/datasets/README.md`
- `experiments/logs/README.md`
- `experiments/COMPONENT_ABLATION_CONTEXT.md`

## Folder Structure

```
experiments/
├── datasets/           # Put .txt files here
│   ├── kosarak_sequences.txt
│   ├── FIFA.txt
│   ├── Bible.txt
│   ├── Leviathan.txt
│   └── BMS1_spmf.txt
├── logs/               # Selected raw logs and generated runtime logs
├── results/            # JSON results
├── scripts/            # Analysis scripts
├── run_experiments.py  # Main automation
├── spmf.jar            # User-provided SPMF v2.64b jar
└── README.md           # This file
```

## Dataset Downloads

Download public real datasets from the [SPMF Dataset Repository](http://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php). The full filename mapping is in `datasets/README.md`:

| Dataset | Link | Size | Description |
|---------|------|------|-------------|
| **Kosarak** | [Download](http://www.philippe-fournier-viger.com/spmf/datasets/kosarak_sequences.txt) | 990K seqs | Volume stress test |
| **FIFA** | [Download](http://www.philippe-fournier-viger.com/spmf/datasets/FIFA.txt) | 20K seqs | Length stress test |
| **Bible** | [Download](http://www.philippe-fournier-viger.com/spmf/datasets/Bible.txt) | 36K seqs | Text/vocabulary test |
| **Leviathan** | [Download](http://www.philippe-fournier-viger.com/spmf/datasets/Leviathan.txt) | 5.8K seqs | Density stress test |
| **BMS-WebView-1** | [Download](http://www.philippe-fournier-viger.com/spmf/datasets/BMS1_spmf.txt) | 59K seqs | Classic BIDE benchmark |

## Experiments

### A. Performance Cliff (Runtime vs Support)
- Shows TriBack-Clo survives at low supports
- X: Minsup (%), Y: Runtime (log scale)
- Timeout: 30 minutes

### B. Memory Efficiency
- Proves O(support) memory vs O(occurrences)
- Focus on dense datasets (Leviathan)

### C. Scalability
- Linear scaling with database size
- Sample Kosarak at 20%, 40%, 60%, 80%, 100%

### D. Ablation Study
- Use `run_component_contribution_analysis.sh` for the current component analysis
- Includes `Full`, `NoPrune`, and `NoGate` variants
- Recommended core profile: `--profile journal`
- Reproducibility profile for the current manuscript table: `--profile paper`
- Stronger conclusions come from low-support workloads where pruning/gating counters are substantially nonzero

```bash
# Recommended journal-strength ablation study
bash run_component_contribution_analysis.sh --profile journal --skip-existing

# Broader confirmation study
bash run_component_contribution_analysis.sh --profile full --skip-existing

# Exact reproduction of the current manuscript table
bash run_component_contribution_analysis.sh --profile paper --skip-existing
```

## Manual Runs

```bash
# TriBack-Clo
java -Xmx50g -cp ../triback-clo-java/triback-clo.jar:spmf.jar \
  ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo \
  datasets/FIFA.txt /dev/null 10%

# SPMF BIDE+
java -Xmx50g -jar spmf.jar run BIDE+ datasets/FIFA.txt output.txt 10%

# SPMF ClaSP
java -Xmx50g -jar spmf.jar run ClaSP datasets/FIFA.txt output.txt 10%

# SPMF CloSpan
java -Xmx50g -jar spmf.jar run CloSpan datasets/FIFA.txt output.txt 10%
```

## Results Format

Most paper-ready shell runners save CSV files and logs under `results/` and `logs/`. A selected historical raw-log bundle is included under `logs/selected-kosarak/`. Older Python utilities may save JSONL files such as `results/experiment_X.jsonl`:

```json
{"dataset": "FIFA", "algorithm": "TriBack-Clo", "ratio": 0.1, "runtime_sec": 42.17, "patterns": 40642}
```

## Visualization

After running experiments:

```bash
python scripts/plot_results.py
```
