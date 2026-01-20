#!/bin/bash
# run-all-benchmarks.sh
# Run all three benchmarks sequentially

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=============================================="
echo "Container Isolation Benchmarks - Full Suite"
echo "=============================================="
echo ""
echo "This will run all three benchmarks:"
echo "  1. Namespace Syscall Overhead (~2 minutes)"
echo "  2. CPU Throttling Overhead (~3 minutes)"
echo "  3. Network Namespace Latency (~2 minutes)"
echo ""
echo "Total estimated time: 7-10 minutes"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "⚠  Some tests require root access"
   echo "  Run with: sudo ./run-all-benchmarks.sh"
   echo ""
   read -p "Continue anyway? (y/N) " -n 1 -r
   echo
   if [[ ! $REPLY =~ ^[Yy]$ ]]; then
       exit 1
   fi
fi

# Create master results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MASTER_RESULTS="results/full-suite-${TIMESTAMP}"
mkdir -p "$MASTER_RESULTS"

echo "Results will be saved to: $MASTER_RESULTS"
echo ""

# Track successes and failures
BENCHMARKS_RUN=0
BENCHMARKS_PASSED=0
BENCHMARKS_FAILED=0

#############################################
# Benchmark 01: Namespace Syscall Overhead
#############################################

echo ""
echo "========================================="
echo "Running Benchmark 01: Namespace Syscall"
echo "========================================="
echo ""

cd benchmarks/01-namespace-syscall

if [ ! -f ./run.sh ]; then
    echo "Benchmark 01 not found"
    BENCHMARKS_FAILED=$((BENCHMARKS_FAILED + 1))
else
    BENCHMARKS_RUN=$((BENCHMARKS_RUN + 1))
    if sudo ./run.sh 2>&1 | tee "${SCRIPT_DIR}/${MASTER_RESULTS}/benchmark-01-full-output.txt"; then
        echo ""
        echo "Benchmark 01 completed successfully"
        BENCHMARKS_PASSED=$((BENCHMARKS_PASSED + 1))
        
        # Copy latest results
        if [ -d results ]; then
            LATEST_01=$(find results -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -1)
            if [ -n "$LATEST_01" ]; then
                mkdir -p "${SCRIPT_DIR}/${MASTER_RESULTS}/01-namespace-syscall"
                cp -r "$LATEST_01"/* "${SCRIPT_DIR}/${MASTER_RESULTS}/01-namespace-syscall/" 2>/dev/null || true
            fi
        fi
    else
        echo ""
        echo "Benchmark 01 failed (exit code: $?)"
        BENCHMARKS_FAILED=$((BENCHMARKS_FAILED + 1))
    fi
fi

cd "$SCRIPT_DIR"

#############################################
# Benchmark 02: CPU Throttling
#############################################

echo ""
echo "========================================="
echo "Running Benchmark 02: CPU Throttling"
echo "========================================="
echo ""

cd benchmarks/02-cpu-throttling

if [ ! -f ./run.sh ]; then
    echo "Benchmark 02 not found"
    BENCHMARKS_FAILED=$((BENCHMARKS_FAILED + 1))
else
    BENCHMARKS_RUN=$((BENCHMARKS_RUN + 1))
    if sudo ./run.sh 2>&1 | tee "${SCRIPT_DIR}/${MASTER_RESULTS}/benchmark-02-full-output.txt"; then
        echo ""
        echo "Benchmark 02 completed successfully"
        BENCHMARKS_PASSED=$((BENCHMARKS_PASSED + 1))
        
        # Copy latest results
        if [ -d results ]; then
            LATEST_02=$(find results -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -1)
            if [ -n "$LATEST_02" ]; then
                mkdir -p "${SCRIPT_DIR}/${MASTER_RESULTS}/02-cpu-throttling"
                cp -r "$LATEST_02"/* "${SCRIPT_DIR}/${MASTER_RESULTS}/02-cpu-throttling/" 2>/dev/null || true
            fi
        fi
    else
        echo ""
        echo "Benchmark 02 failed (exit code: $?)"
        BENCHMARKS_FAILED=$((BENCHMARKS_FAILED + 1))
    fi
fi

cd "$SCRIPT_DIR"

#############################################
# Benchmark 03: Network Latency
#############################################

echo ""
echo "========================================="
echo "Running Benchmark 03: Network Latency"
echo "========================================="
echo ""

cd benchmarks/03-network-latency

if [ ! -f ./run.sh ]; then
    echo "Benchmark 03 not found"
    BENCHMARKS_FAILED=$((BENCHMARKS_FAILED + 1))
else
    BENCHMARKS_RUN=$((BENCHMARKS_RUN + 1))
    if sudo ./run.sh 2>&1 | tee "${SCRIPT_DIR}/${MASTER_RESULTS}/benchmark-03-full-output.txt"; then
        echo ""
        echo "Benchmark 03 completed successfully"
        BENCHMARKS_PASSED=$((BENCHMARKS_PASSED + 1))
        
        # Copy latest results
        if [ -d results ]; then
            LATEST_03=$(find results -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -1)
            if [ -n "$LATEST_03" ]; then
                mkdir -p "${SCRIPT_DIR}/${MASTER_RESULTS}/03-network-latency"
                cp -r "$LATEST_03"/* "${SCRIPT_DIR}/${MASTER_RESULTS}/03-network-latency/" 2>/dev/null || true
            fi
        fi
    else
        echo ""
        echo "Benchmark 03 failed (exit code: $?)"
        BENCHMARKS_FAILED=$((BENCHMARKS_FAILED + 1))
    fi
fi

cd "$SCRIPT_DIR"

#############################################
# Summary
#############################################

echo ""
echo "=============================================="
echo "Benchmark Suite Summary"
echo "=============================================="
echo ""
echo "Benchmarks run: $BENCHMARKS_RUN"
echo "Passed: $BENCHMARKS_PASSED"
echo "Failed: $BENCHMARKS_FAILED"
echo ""
echo "Results saved to: $MASTER_RESULTS/"
echo ""

if [ $BENCHMARKS_PASSED -gt 0 ]; then
    echo "Quick Summary:"
    echo ""

    # Try to extract key findings
    echo "Benchmark 01 (Namespace Syscall):"
    if [ -f "${MASTER_RESULTS}/01-namespace-syscall/test-a-host.txt" ] || [ -f "${MASTER_RESULTS}/01-namespace-syscall/test-a-mac.txt" ]; then
        HOST_FILE="${MASTER_RESULTS}/01-namespace-syscall/test-a-host.txt"
        [ ! -f "$HOST_FILE" ] && HOST_FILE="${MASTER_RESULTS}/01-namespace-syscall/test-a-mac.txt"
        
        CONTAINER_FILE="${MASTER_RESULTS}/01-namespace-syscall/test-b-container.txt"
        
        if [ -f "$HOST_FILE" ]; then
            HOST_NS=$(grep "Average:" "$HOST_FILE" 2>/dev/null | head -1 | awk '{print $2, $3}')
            echo "  Host/Mac:  $HOST_NS"
        fi
        
        if [ -f "$CONTAINER_FILE" ]; then
            CONTAINER_NS=$(grep "Average:" "$CONTAINER_FILE" 2>/dev/null | head -1 | awk '{print $2, $3}')
            echo "  Container: $CONTAINER_NS"
        fi
    else
        echo "  No results available"
    fi
    echo ""

    echo "Benchmark 02 (CPU Throttling):"
    if [ -f "${MASTER_RESULTS}/02-cpu-throttling/test-c-aggressive.txt" ]; then
        THROTTLE_RATE=$(grep "Throttle rate:" "${MASTER_RESULTS}/02-cpu-throttling/test-c-aggressive.txt" 2>/dev/null | head -1 | awk '{print $3}')
        if [ -n "$THROTTLE_RATE" ]; then
            echo "  Aggressive throttle rate: $THROTTLE_RATE"
        else
            echo "  See results directory for details"
        fi
    else
        echo "  No results available"
    fi
    echo ""

    echo "Benchmark 03 (Network Latency):"
    if [ -d "${MASTER_RESULTS}/03-network-latency" ] && [ "$(ls -A ${MASTER_RESULTS}/03-network-latency 2>/dev/null)" ]; then
        echo "  Results in: ${MASTER_RESULTS}/03-network-latency/"
    else
        echo "  No results available"
    fi
    echo ""
fi

echo "Next Steps:"
echo "  1. Review results in $MASTER_RESULTS/"
echo "  2. Compare with expected_results.md in each benchmark"
if [ $BENCHMARKS_FAILED -gt 0 ]; then
    echo "  3. Check failed benchmark logs in $MASTER_RESULTS/"
    echo "  4. Review individual benchmark run.sh scripts"
fi
echo ""

echo "System Info:"
echo "  Kernel: $(uname -r)"
echo "  CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | xargs || echo "N/A")"
echo "  Docker: $(docker --version 2>/dev/null || echo 'N/A')"
echo ""

# Exit with error if any benchmarks failed
if [ $BENCHMARKS_FAILED -gt 0 ]; then
    exit 1
fi