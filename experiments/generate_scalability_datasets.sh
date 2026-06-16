#!/bin/bash
# ==============================================================================
# Generate Scalability Study Datasets
# Replicates CloFAST Paper Figure 15 - Varying D (number of sequences)
# ==============================================================================
# Generates 6 datasets: D50k to D300k sequences
# All with constant: C=20, T=20, N=2.5, S=6, I=4
# ==============================================================================

cd /home/nabil/habilitation-project/TriBack-Clo/experiments
IBM_GEN="./IBMGenerator/gen"
OUT="datasets/synthetic/clofast_paper"
mkdir -p "$OUT"

# Check for IBM Generator
if [ ! -f "$IBM_GEN" ]; then
    echo "Error: IBM Generator binary not found at $IBM_GEN"
    echo "Please ensure the generator is compiled."
    exit 1
fi

# Function to convert IBM .data format to SPMF format
convert() {
    local input=$1
    local output=$2
    python3 -c "
from collections import defaultdict
import sys, os

try:
    sequences = defaultdict(list)
    line_count = 0
    with open('$input') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 4: continue
            cust_id = parts[0]
            trans_id = int(parts[1])
            num_items = int(parts[2])
            items = parts[3:3+num_items]
            sequences[cust_id].append((trans_id, items))
            line_count += 1
            
    with open('$output', 'w') as f:
        for cust_id in sorted(sequences.keys(), key=int):
            trans = sorted(sequences[cust_id], key=lambda x: x[0])
            parts = []
            for tid, items in trans:
                parts.append(' '.join(items))
            f.write(' -1 '.join(parts) + ' -1 -2\n')
    print(f'Converted {len(sequences)} sequences -> $output')
except Exception as e:
    print(f'Error converting {input}: {e}')
"
}

# Wrapper function to generate and convert
generate_dataset() {
    local NAME=$1
    local ARGS=$2
    
    echo "Generating $NAME..."
    $IBM_GEN seq $ARGS -fname "$OUT/$NAME" -ascii > /dev/null 2>&1
    
    if [ -f "$OUT/${NAME}.data" ]; then
        convert "$OUT/${NAME}.data" "$OUT/${NAME}.txt"
        rm -f "$OUT/${NAME}.data" "$OUT/${NAME}.pat" "$OUT/${NAME}.conf" "$OUT/${NAME}.ntpc"
    else
        echo "Failed to generate $NAME"
    fi
}

echo "=========================================================="
echo "Scalability Study Datasets (CloFAST Paper Figure 15)"
echo "Varying D (number of sequences): 50k -> 300k"
echo "Fixed: C=20, T=20, N=2.5, S=6, I=4"
echo "=========================================================="

# Generate datasets with varying D
# D values: 50, 100, 150, 200, 250, 300 (in thousands)
for D in 50 100 150 200 250 300; do
    NAME="D${D}C20T20N2.5S6I4"
    ARGS="-ncust $D -slen 20 -tlen 20 -nitems 2.5 -seq.corr 0.25 -seq.patlen 6 -lit.patlen 4"
    generate_dataset "$NAME" "$ARGS"
done

echo ""
echo "=========================================================="
echo "Generation Complete. Datasets:"
ls -lh "$OUT/"*.txt 2>/dev/null || echo "No datasets generated"
echo "=========================================================="
