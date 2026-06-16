#!/bin/bash
# Build script for Java TriBack-Clo
# Uses the spmf.jar from experiments for dependencies

cd "$(dirname "$0")"

SPMF_JAR="../experiments/spmf.jar"
OUTPUT_DIR="build"

# Clean
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Find Java 21 javac
JAVAC=""
for path in "/usr/lib/jvm/java-21-openjdk-"*/bin/javac; do
    if [ -x "$path" ]; then
        JAVAC="$path"
        break
    fi
done

if [ -z "$JAVAC" ]; then
    # Try to use java itself to find the JDK
    JAVA_BIN=$(dirname $(readlink -f $(which java)))
    if [ -x "$JAVA_BIN/javac" ]; then
        JAVAC="$JAVA_BIN/javac"
    else
        echo "Warning: Java 21 javac not found, using default javac"
        JAVAC="javac"
    fi
fi

echo "Using javac: $JAVAC"
echo "Building..."

# Compile
$JAVAC --release 21 -cp "$SPMF_JAR" -d "$OUTPUT_DIR" \
    ca/pfv/spmf/algorithms/sequentialpatterns/tribackclo/*.java

if [ $? -eq 0 ]; then
    echo "Compilation successful. Packaging JAR..."
    jar cf triback-clo.jar -C "$OUTPUT_DIR" .
    echo "JAR created: triback-clo.jar"
    
    echo "Build successful!"
    echo ""
    echo "To run:"
    echo "  java -cp triback-clo.jar:../experiments/spmf.jar ca.pfv.spmf.algorithms.sequentialpatterns.tribackclo.MainTestTriBackClo <input> <output> <minsup>"
else
    echo "Build failed!"
    exit 1
fi
