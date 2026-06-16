#!/bin/bash
# ==============================================================================
# Generate Figure 15 Datasets - Varying S and I
# Replicates CloFAST Paper Figure 15
# ==============================================================================
# Fixed: D=50, C=20, T=20, N=2.5, min_sup=0.4
# Vary: S = {2, 4, 6, 8, 10}, I = {2, 4, 6, 8, 10}
# Total: 25 datasets
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
echo "Figure 15: Varying S and I (Pattern Parameters)"
echo "Fixed: D=50, C=20, T=20, N=2.5"
echo "Vary: S = {2, 4, 6, 8, 10}, I = {2, 4, 6, 8, 10}"
echo "min_sup = 0.4 (40%)"
echo "=========================================================="

# Generate 25 datasets varying S and I
for S in 2 4 6 8 10; do
    for I in 2 4 6 8 10; do
        NAME="D50C20T20N2.5S${S}I${I}"
        ARGS="-ncust 50 -slen 20 -tlen 20 -nitems 2.5 -seq.corr 0.25 -seq.patlen $S -lit.patlen $I"
        generate_dataset "$NAME" "$ARGS"
    done
done

echo ""
echo "=========================================================="
echo "Generation Complete. Figure 15 Datasets:"
ls -lh "$OUT/"D50C20T20N2.5S*.txt 2>/dev/null || echo "No datasets generated"
echo "=========================================================="
