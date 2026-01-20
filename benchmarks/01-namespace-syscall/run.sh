#!/bin/bash
# benchmarks/01-namespace-syscall/run.sh
# Run namespace syscall overhead benchmark

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Benchmark 01: Namespace Syscall Overhead"
echo "========================================="
echo ""

# Check if binary exists
if [ ! -f ./getpid_bench ]; then
    echo "Binary not found. Compiling..."
    ./compile.sh
    echo ""
fi

# Create results directory
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="results/${TIMESTAMP}"
mkdir -p "$RESULT_DIR"

echo "Results will be saved to: $RESULT_DIR"
echo ""

# Check if perf works
PERF_WORKS=false
if command -v perf &> /dev/null; then
    if perf stat -e cycles -- sleep 0.1 &> /dev/null; then
        PERF_WORKS=true
    fi
fi

#############################################
# Test A: Host PID Namespace (Baseline)
#############################################

echo "=== Test A: Host PID Namespace (Baseline) ==="

if [ "$PERF_WORKS" = true ]; then
    echo "Running with perf (CPU cycle counters)..."
    taskset -c 0 perf stat -e cycles,instructions,cache-misses \
        ./getpid_bench 2>&1 | tee "$RESULT_DIR/test-a-host.txt"
else
    echo "Running without perf (timing only)..."
    ./getpid_bench 2>&1 | tee "$RESULT_DIR/test-a-host.txt"
fi

echo ""

#############################################
# Test B: Container PID Namespace
#############################################

echo "=== Test B: Container PID Namespace ==="
echo "Running inside Docker container..."
docker run --rm -v "$SCRIPT_DIR:/work:ro" alpine /work/getpid_bench \
    2>&1 | tee "$RESULT_DIR/test-b-container.txt"

echo ""

#############################################
# Test C: Cross-Namespace (nsenter)
#############################################

echo "=== Test C: Cross-Namespace (nsenter) ==="
docker run -d --name nstest-$$ alpine sleep 600 > /dev/null
TARGET_PID=$(docker inspect nstest-$$ --format '{{.State.Pid}}')

echo "Running 1000 nsenter operations..."
START_TIME=$(date +%s%N)
for i in {1..1000}; do
    nsenter --target $TARGET_PID --pid -- /bin/true > /dev/null 2>&1
done
END_TIME=$(date +%s%N)

ELAPSED_NS=$((END_TIME - START_TIME))
AVG_US=$((ELAPSED_NS / 1000 / 1000))

echo "Average: ${AVG_US} microseconds per nsenter" | tee "$RESULT_DIR/test-c-nsenter.txt"

docker rm -f nstest-$$ > /dev/null

echo ""

#############################################
# Summary
#############################################

echo "=== Results Summary ==="
echo ""

HOST_NS=$(grep "Average:" "$RESULT_DIR/test-a-host.txt" 2>/dev/null | awk '{print $2}' || echo "N/A")
CONTAINER_NS=$(grep "Average:" "$RESULT_DIR/test-b-container.txt" 2>/dev/null | awk '{print $2}' || echo "N/A")

echo "Test A (Host):      ${HOST_NS} ns"
echo "Test B (Container): ${CONTAINER_NS} ns"
echo "Test C (nsenter):   ${AVG_US} microseconds"

if [ "$HOST_NS" != "N/A" ] && [ "$CONTAINER_NS" != "N/A" ]; then
    OVERHEAD=$(echo "scale=1; (($CONTAINER_NS - $HOST_NS) / $HOST_NS) * 100" | bc 2>/dev/null || echo "N/A")
    if [ "$OVERHEAD" != "N/A" ]; then
        echo ""
        echo "Container overhead: +${OVERHEAD}%"
    fi
fi

echo ""
echo "Full results: $RESULT_DIR/"
echo ""
echo "Next: Review results and compare with expected_results.md"