#!/bin/bash
# Generate synthetic datasets from CloFAST paper using SPMF IBM generator
# Based on: Fumarola et al. 2016 - CloFAST paper configurations
#
# IBM Generator Parameters:
#   D = Number of sequences (×1000)
#   C = Average itemsets per sequence
#   T = Average items per itemset
#   N = Number of different items (×1000)
#   S = Average length of maximal patterns
#   I = Average size of itemsets in maximal patterns
#
# SPMF command: Generate_a_sequence_database output numSequences numItems avgItemsetsPerSeq avgItemsPerItemset

SPMF_JAR="../spmf.jar"
OUTPUT_DIR="synthetic"

mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "CloFAST Synthetic Dataset Generator"
echo "=========================================="

# Function to generate dataset
generate_dataset() {
    local name=$1
    local num_sequences=$2
    local num_items=$3        # N×1000
    local avg_itemsets=$4     # C
    local avg_items=$5        # T
    
    echo ""
    echo "Generating: $name"
    echo "  Sequences: $num_sequences, Items: $num_items, Avg itemsets/seq: $avg_itemsets, Avg items/itemset: $avg_items"
    
    java -jar "$SPMF_JAR" run Generate_a_sequence_database \
        "$OUTPUT_DIR/${name}.txt" \
        $num_sequences $num_items $avg_itemsets $avg_items
    
    if [ -f "$OUTPUT_DIR/${name}.txt" ]; then
        local size=$(du -h "$OUTPUT_DIR/${name}.txt" | cut -f1)
        local lines=$(wc -l < "$OUTPUT_DIR/${name}.txt")
        echo "  ✓ Created: $OUTPUT_DIR/${name}.txt ($size, $lines sequences)"
    else
        echo "  ✗ Failed to create dataset"
    fi
}

echo ""
echo "=== SPARSE DATASETS (low density) ==="
# D5C10T10N2.5 -> 5000 sequences, 2500 items, 10 itemsets/seq, 10 items/itemset
generate_dataset "sparse_D5C10T10N2500" 5000 2500 10 10

# D5C10T10N1600 (higher density)
generate_dataset "sparse_D5C10T10N1600" 5000 1600 10 10

# D5C10T10N1000 (even higher density)  
generate_dataset "sparse_D5C10T10N1000" 5000 1000 10 10

echo ""
echo "=== MEDIUM DATASETS ==="
# D10C20T20N2500
generate_dataset "medium_D10C20T20N2500" 10000 2500 20 20

# D50C20T20N2500 (larger)
generate_dataset "medium_D50C20T20N2500" 50000 2500 20 20

echo ""
echo "=== DENSE DATASETS (high density) ==="
# D10C60T20N5000 - many itemsets per sequence
generate_dataset "dense_D10C60T20N5000" 10000 5000 60 20

echo ""
echo "=== SCALABILITY TEST SERIES (varying D) ==="
for D in 50 100 150 200; do
    generate_dataset "scale_D${D}C20T20N2500" $((D * 1000)) 2500 20 20
done

echo ""
echo "=========================================="
echo "Dataset generation complete!"
echo "Output directory: $OUTPUT_DIR/"
echo "=========================================="
ls -lh "$OUTPUT_DIR/"
