#!/bin/bash
# benchmarks/03-network-latency/run.sh
# Measure network namespace overhead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Benchmark 03: Network Namespace Latency"
echo "========================================="
echo ""

# CLEANUP: Remove any leftover containers from previous runs
echo "Cleaning up any leftover containers..."
docker rm -f netserver 2>/dev/null || true
docker rm -f webserver 2>/dev/null || true
echo ""

# Create results directory
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="results/${TIMESTAMP}"
mkdir -p "$RESULT_DIR"

echo "Results will be saved to: $RESULT_DIR"
echo ""

#############################################
# Test A: Loopback Baseline
#############################################

echo "=== Test A: Loopback (Baseline) ==="
echo "Running ping test on localhost..."
ping -c 100 -i 0.2 127.0.0.1 2>&1 | tee "$RESULT_DIR/test-a-loopback.txt"

echo ""
sleep 2

#############################################
# Test B: Docker veth
#############################################

echo "=== Test B: Docker Containers (veth Pair) ==="
echo "Starting nginx container..."

# Use unique name with timestamp to avoid conflicts
CONTAINER_NAME="netserver-$$"
docker run -d --name $CONTAINER_NAME nginx:alpine > /dev/null
sleep 3

SERVER_IP=$(docker inspect $CONTAINER_NAME --format '{{.NetworkSettings.IPAddress}}')
echo "Server IP: $SERVER_IP"
echo "Running ping test..."
ping -c 100 -i 0.2 $SERVER_IP 2>&1 | tee "$RESULT_DIR/test-b-docker-veth.txt"

# Cleanup
docker rm -f $CONTAINER_NAME > /dev/null

echo ""

#############################################
# Test C: Kubernetes Pod (if available)
#############################################

echo "=== Test C: Kubernetes Pod (Shared Namespace) ==="

if ! command -v kubectl &> /dev/null; then
    echo "⚠ kubectl not found - skipping Kubernetes test"
    echo "  Install kubectl to test pod networking"
elif ! kubectl cluster-info > /dev/null 2>&1; then
    echo "⚠ No Kubernetes cluster access - skipping"
    echo "  This test requires access to a K8s cluster"
else
    echo "Kubernetes cluster accessible - running pod test..."
    echo "⚠ Pod test not implemented yet"
fi

echo ""

#############################################
# Summary
#############################################

echo "=== Results Summary ==="
echo ""

if [ -f "$RESULT_DIR/test-a-loopback.txt" ]; then
    LOOPBACK_AVG=$(grep "rtt min/avg/max" "$RESULT_DIR/test-a-loopback.txt" 2>/dev/null | awk -F'/' '{print $5}' || echo "N/A")
    echo "Test A (Loopback): ${LOOPBACK_AVG} ms"
fi

if [ -f "$RESULT_DIR/test-b-docker-veth.txt" ]; then
    DOCKER_AVG=$(grep "rtt min/avg/max" "$RESULT_DIR/test-b-docker-veth.txt" 2>/dev/null | awk -F'/' '{print $5}' || echo "N/A")
    echo "Test B (Docker veth): ${DOCKER_AVG} ms"
    
    if [ "$LOOPBACK_AVG" != "N/A" ] && [ "$DOCKER_AVG" != "N/A" ]; then
        OVERHEAD=$(echo "scale=1; (($DOCKER_AVG - $LOOPBACK_AVG) / $LOOPBACK_AVG) * 100" | bc 2>/dev/null || echo "N/A")
        if [ "$OVERHEAD" != "N/A" ]; then
            echo ""
            echo "veth overhead: +${OVERHEAD}%"
        fi
    fi
fi

echo ""
echo "Full results: $RESULT_DIR/"
echo ""
echo "Next: Review results and compare with expected_results.md"