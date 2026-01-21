#!/bin/bash
# benchmarks/03-network-latency/run.sh
# Network Latency Benchmark - FIXED PARSING

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Benchmark 03: Network Latency"
echo "========================================="
echo ""

# Check tools
for cmd in docker sockperf; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: $cmd not found"
        exit 1
    fi
done

# Create results
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="results/${TIMESTAMP}"
mkdir -p "$RESULT_DIR"

echo "Results: $RESULT_DIR"
echo "Kernel: $(uname -r)"
echo ""

# Cleanup
docker rm -f net-test-server 2>/dev/null || true
killall sockperf 2>/dev/null || true

#############################################
# Test A: Loopback Baseline
#############################################

echo "=== Test A: Loopback Baseline ==="
echo ""

# Start sockperf server
echo "Starting sockperf server on 127.0.0.1..."
sockperf server --tcp -p 12345 > /dev/null 2>&1 &
SP_PID=$!
sleep 3

echo "Running sockperf ping-pong (10 seconds)..."
sockperf ping-pong -i 127.0.0.1 --tcp -p 12345 -t 10 2>&1 | tee "$RESULT_DIR/test-a-loopback.txt"

kill $SP_PID 2>/dev/null || true
wait $SP_PID 2>/dev/null || true

# Extract latency - CORRECT field number
LOOPBACK_LATENCY=$(grep "Summary: Latency is" "$RESULT_DIR/test-a-loopback.txt" | awk '{print $5}')
echo ""
echo "Loopback latency: $LOOPBACK_LATENCY μs"
echo ""
sleep 2

#############################################
# Test B: Docker veth
#############################################

echo "=== Test B: Docker veth ==="
echo ""

# Clean any old container
docker rm -f net-test-server 2>/dev/null || true

# Use Debian (has sockperf in apt)
echo "Starting Debian container..."
docker run -d --name net-test-server debian:bullseye-slim sh -c '
  apt-get update > /dev/null 2>&1
  apt-get install -y sockperf > /dev/null 2>&1
  sockperf server --tcp -p 12345
' > /dev/null 2>&1

# Wait for container to start
echo "Waiting for container to start..."
sleep 10

# Verify container is running
if ! docker ps | grep -q net-test-server; then
    echo "ERROR: Container not running."
    docker logs net-test-server 2>&1 | head -20
    docker rm -f net-test-server 2>/dev/null || true
    exit 1
fi

# Get container IP
CONTAINER_IP=$(docker inspect net-test-server --format '{{.NetworkSettings.IPAddress}}')

if [ -z "$CONTAINER_IP" ]; then
    echo "ERROR: Could not get container IP"
    docker rm -f net-test-server 2>/dev/null || true
    exit 1
fi

echo "Container IP: $CONTAINER_IP"
echo ""
echo "Running sockperf ping-pong (10 seconds)..."
sockperf ping-pong -i $CONTAINER_IP --tcp -p 12345 -t 10 2>&1 | tee "$RESULT_DIR/test-b-docker-veth.txt"

# Extract latency - CORRECT field number
VETH_LATENCY=$(grep "Summary: Latency is" "$RESULT_DIR/test-b-docker-veth.txt" | awk '{print $5}')
echo ""
echo "veth latency: $VETH_LATENCY μs"
echo ""

# Cleanup
docker rm -f net-test-server > /dev/null 2>&1 || true

#############################################
# Analysis
#############################################

echo "=== Analysis ==="
echo ""

if [ -n "$LOOPBACK_LATENCY" ] && [ -n "$VETH_LATENCY" ]; then
    # Calculate overhead (can be negative if veth is faster due to noise)
    OVERHEAD=$(echo "scale=3; $VETH_LATENCY - $LOOPBACK_LATENCY" | bc -l)
    OVERHEAD_ABS=$(echo "${OVERHEAD#-}")  # Absolute value
    
    # Only calculate percentage if loopback is not zero
    if (( $(echo "$LOOPBACK_LATENCY > 0" | bc -l) )); then
        OVERHEAD_PERCENT=$(echo "scale=1; ($OVERHEAD / $LOOPBACK_LATENCY) * 100" | bc -l)
    else
        OVERHEAD_PERCENT="N/A"
    fi
    
    echo "TCP Latency Comparison:" | tee "$RESULT_DIR/summary.txt"
    echo "  Loopback (127.0.0.1): $LOOPBACK_LATENCY μs" | tee -a "$RESULT_DIR/summary.txt"
    echo "  Docker veth:          $VETH_LATENCY μs" | tee -a "$RESULT_DIR/summary.txt"
    
    # Handle negative overhead (veth faster than loopback)
    if (( $(echo "$OVERHEAD < 0" | bc -l) )); then
        echo "  Overhead:             ${OVERHEAD} μs (${OVERHEAD_PERCENT}%)" | tee -a "$RESULT_DIR/summary.txt"
        echo "" | tee -a "$RESULT_DIR/summary.txt"
        echo "Note: Negative overhead indicates measurement variance." | tee -a "$RESULT_DIR/summary.txt"
        echo "      At this precision (~19μs), differences <1μs are within noise." | tee -a "$RESULT_DIR/summary.txt"
        echo "      Both measurements are essentially identical." | tee -a "$RESULT_DIR/summary.txt"
    else
        echo "  Overhead:             $OVERHEAD μs (${OVERHEAD_PERCENT}%)" | tee -a "$RESULT_DIR/summary.txt"
    fi
    
    echo "" | tee -a "$RESULT_DIR/summary.txt"
    
    # Interpretation
    echo "Interpretation:" | tee -a "$RESULT_DIR/summary.txt"
    if (( $(echo "$OVERHEAD_ABS < 1" | bc -l) )); then
        echo "  Excellent: Minimal veth overhead (<1μs)" | tee -a "$RESULT_DIR/summary.txt"
        echo "  Kernel $(uname -r) has highly optimized veth performance" | tee -a "$RESULT_DIR/summary.txt"
    elif (( $(echo "$OVERHEAD_ABS < 5" | bc -l) )); then
        echo "  Very Good: Low veth overhead (<5μs)" | tee -a "$RESULT_DIR/summary.txt"
    elif (( $(echo "$OVERHEAD_ABS < 15" | bc -l) )); then
        echo "  Good: Moderate veth overhead (<15μs)" | tee -a "$RESULT_DIR/summary.txt"
    else
        echo "  ⚠ Significant veth overhead (>15μs)" | tee -a "$RESULT_DIR/summary.txt"
        echo "  Consider: kernel upgrade or alternative CNI plugins" | tee -a "$RESULT_DIR/summary.txt"
    fi
    
    echo "" | tee -a "$RESULT_DIR/summary.txt"
    echo "Environment:" | tee -a "$RESULT_DIR/summary.txt"
    echo "  Kernel: $(uname -r)" | tee -a "$RESULT_DIR/summary.txt"
    echo "  Docker Network: bridge (default)" | tee -a "$RESULT_DIR/summary.txt"
    echo "  Date: $(date)" | tee -a "$RESULT_DIR/summary.txt"
    
else
    echo "ERROR: Failed to extract latency measurements"
    echo "Check $RESULT_DIR/test-a-loopback.txt and test-b-docker-veth.txt"
fi

#############################################
# Summary
#############################################

echo ""
echo "=== Summary ==="
echo ""
echo "Full results saved to: $RESULT_DIR/"
echo ""
echo "Result files:"
ls -lh "$RESULT_DIR/"*.txt 2>/dev/null
echo ""

if [ -f "$RESULT_DIR/summary.txt" ]; then
    echo "=== FINAL RESULTS ==="
    cat "$RESULT_DIR/summary.txt"
fi

echo ""
echo "Done."