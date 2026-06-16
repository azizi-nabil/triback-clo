#!/bin/bash
# ==============================================================================
# Generate ALL CloFAST Paper Synthetic Datasets
# Based on Section 7.2 of Fumarola et al. (CloFAST Paper)
# ==============================================================================
# This script generates 21 synthetic datasets using the IBM Quest Data Generator.
# It replicates the exact parameters used in the CloFAST paper experiments.
#
# Generates:
# 1. Figure 8: Varying Density (N) - 3 datasets
# 2. Figure 9: Varying Density (T) - 4 datasets
# 3. Figure 10: Varying Sequence Length (C) - 14 datasets (Sparse & Dense)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
IBM_GEN="${IBM_GENERATOR:-$SCRIPT_DIR/IBMGenerator/gen}"
OUT="datasets/synthetic/clofast_paper"
mkdir -p "$OUT"

# Check for IBM Generator
if [ ! -f "$IBM_GEN" ]; then
    echo "Error: IBM Generator binary not found at $IBM_GEN"
    echo "Set IBM_GENERATOR=/path/to/IBMGenerator/gen or place the binary at experiments/IBMGenerator/gen."
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
echo "1. Figure 8: Varying N (T/N Density) - D5 C10 T10 S6 I4"
echo "=========================================================="
# Fixed: D=5, C=10, T=10, S=6, I=4
# Varied N: 2.5, 1.6, 1
for N in 2.5 1.6 1; do
    NAME="D5C10T10N${N}S6I4"
    ARGS="-ncust 5 -slen 10 -tlen 10 -nitems $N -seq.corr 0.25 -seq.patlen 6 -lit.patlen 4"
    generate_dataset "$NAME" "$ARGS"
done

echo ""
echo "=========================================================="
echo "2. Figure 9: Varying T (T/N Density) - D50 C20 N2.5 S6 I4"
echo "=========================================================="
# Fixed: D=50, C=20, N=2.5, S=6, I=4
# Varied T: 10, 20, 30, 40
for T in 10 20 30 40; do
    NAME="D50C20T${T}N2.5S6I4"
    ARGS="-ncust 50 -slen 20 -tlen $T -nitems 2.5 -seq.corr 0.25 -seq.patlen 6 -lit.patlen 4"
    generate_dataset "$NAME" "$ARGS"
done

echo ""
echo "=========================================================="
echo "3. Figure 10: Varying C (Length) - Sparse & Dense"
echo "=========================================================="

echo ">> Sparse Series: D20 C[20-80] T2.5 N10 S10 I1.25"
# S=10, I=1.25
for C in 20 30 40 50 60 70 80; do
    NAME="D20C${C}T2.5N10S10I1.25"
    ARGS="-ncust 20 -slen $C -tlen 2.5 -nitems 10 -seq.corr 0.25 -seq.patlen 10 -lit.patlen 1.25"
    generate_dataset "$NAME" "$ARGS"
done

echo ">> Dense Series: D10 C[20-80] T20 N5 S6 I4"
# S=6, I=4
for C in 20 30 40 50 60 70 80; do
    NAME="D10C${C}T20N5S6I4"
    ARGS="-ncust 10 -slen $C -tlen 20 -nitems 5 -seq.corr 0.25 -seq.patlen 6 -lit.patlen 4"
    generate_dataset "$NAME" "$ARGS"
done

echo "=========================================================="
echo "Generation Complete. Datasets:"
ls -lh "$OUT/"*.txt
