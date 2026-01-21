#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Benchmark 01: Namespace Syscall Overhead"
echo "========================================="
echo ""

# Create results directory
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="results/${TIMESTAMP}"
mkdir -p "$RESULT_DIR"

echo "Results will be saved to: $RESULT_DIR"
echo ""

# Compile
if [ ! -f ./getpid_bench ]; then
    echo "Compiling getpid_bench..."
    ./compile.sh
fi

#############################################
# Test A: Host PID Namespace (Baseline)
#############################################

echo "=== Test A: Host PID Namespace (Baseline) ==="
echo "Running 10M getpid() syscalls on host..."

./getpid_bench | tee "$RESULT_DIR/test-a-host.txt"

#############################################
# Test B: Container PID Namespace
#############################################

echo ""
echo "=== Test B: Container PID Namespace ==="
echo "Running 10M getpid() syscalls inside Docker container..."

docker run --rm -v "$(pwd)/getpid_bench:/getpid_bench" alpine /getpid_bench | tee "$RESULT_DIR/test-b-container.txt"

#############################################
# Summary
#############################################

echo ""
echo "=== Results Summary ==="
echo ""

HOST_NS=$(grep "Average:" "$RESULT_DIR/test-a-host.txt" 2>/dev/null | head -1 | awk '{print $2, $3}' || echo "N/A")
CONTAINER_NS=$(grep "Average:" "$RESULT_DIR/test-b-container.txt" 2>/dev/null | head -1 | awk '{print $2, $3}' || echo "N/A")

echo "Test A (Host):      $HOST_NS"
echo "Test B (Container): $CONTAINER_NS"

if [ "$HOST_NS" != "N/A" ] && [ "$CONTAINER_NS" != "N/A" ]; then
    HOST_VAL=$(echo "$HOST_NS" | awk '{print $1}')
    CONTAINER_VAL=$(echo "$CONTAINER_NS" | awk '{print $1}')
    
    OVERHEAD=$(echo "scale=1; (($CONTAINER_VAL - $HOST_VAL) / $HOST_VAL) * 100" | bc 2>/dev/null || echo "N/A")
    
    if [ "$OVERHEAD" != "N/A" ]; then
        echo ""
        echo "Namespace overhead: +${OVERHEAD}%"
        echo ""
        echo "What this means:"
        echo "  - Container syscalls are ${OVERHEAD}% slower due to PID namespace translation"
        echo "  - This overhead is constant for ALL syscalls in containers"
        echo "  - The kernel must translate PIDs through the namespace hierarchy"
    fi
fi

echo ""
echo "Full results: $RESULT_DIR/"
echo ""
echo "Next: Review results and compare with expected_results.md"