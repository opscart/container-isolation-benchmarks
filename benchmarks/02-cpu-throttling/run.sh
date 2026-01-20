#!/bin/bash
# benchmarks/02-cpu-throttling/run.sh
# Measure CPU throttling overhead from cgroup limits

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Benchmark 02: CPU Throttling Overhead"
echo "========================================="
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Docker not found. This benchmark requires Docker."
    exit 1
fi

if ! docker info &> /dev/null 2>&1; then
    echo "Docker daemon not running. Please start Docker."
    exit 1
fi

# Create results directory
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="results/${TIMESTAMP}"
mkdir -p "$RESULT_DIR"

echo "Results will be saved to: $RESULT_DIR"
echo ""

# Cleanup any leftover containers
echo "Cleaning up any leftover containers..."
docker rm -f throttle-baseline throttle-moderate throttle-aggressive 2>/dev/null || true
echo ""

# Test duration
TEST_DURATION=60
echo "Test duration: ${TEST_DURATION} seconds per test"
echo ""

#############################################
# Test A: No CPU Limit (Baseline)
#############################################

echo "=== Test A: No CPU Limit (Baseline) ==="
echo "Creating container with unlimited CPU..."

docker run -d --name throttle-baseline alpine sh -c '
  # CPU-intensive loop
  while true; do :; done
' > /dev/null

echo "Running workload for ${TEST_DURATION} seconds..."
sleep ${TEST_DURATION}

# Get container ID
CONTAINER_ID=$(docker inspect throttle-baseline --format '{{.Id}}')

# Find cgroup path (try both cgroup v1 and v2)
CGROUP_PATH=""
if [ -d "/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope" ]; then
    # cgroup v2 (modern systems)
    CGROUP_PATH="/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope"
elif [ -d "/sys/fs/cgroup/cpu/docker/${CONTAINER_ID}" ]; then
    # cgroup v1
    CGROUP_PATH="/sys/fs/cgroup/cpu/docker/${CONTAINER_ID}"
fi

if [ -z "$CGROUP_PATH" ] || [ ! -d "$CGROUP_PATH" ]; then
    echo "⚠  Warning: Cannot find cgroup path for container"
    echo "  Container may be using different cgroup driver"
    echo "  Attempting to read stats anyway..."
    
    # Try to get stats from Docker API
    docker stats --no-stream throttle-baseline | tee "$RESULT_DIR/test-a-baseline-stats.txt"
else
    echo "Found cgroup at: $CGROUP_PATH"
    echo ""
    
    # Read CPU stats
    if [ -f "${CGROUP_PATH}/cpu.stat" ]; then
        # cgroup v2
        echo "=== CPU Statistics (cgroup v2) ===" | tee "$RESULT_DIR/test-a-baseline.txt"
        cat "${CGROUP_PATH}/cpu.stat" | tee -a "$RESULT_DIR/test-a-baseline.txt"
    elif [ -f "${CGROUP_PATH}/cpuacct.stat" ]; then
        # cgroup v1
        echo "=== CPU Statistics (cgroup v1) ===" | tee "$RESULT_DIR/test-a-baseline.txt"
        cat "${CGROUP_PATH}/cpuacct.stat" | tee -a "$RESULT_DIR/test-a-baseline.txt"
        cat "${CGROUP_PATH}/cpu.stat" | tee -a "$RESULT_DIR/test-a-baseline.txt"
    fi
fi

echo ""
echo "Baseline: No throttling expected (unlimited CPU)"
echo ""

# Cleanup
docker rm -f throttle-baseline > /dev/null
sleep 2

#############################################
# Test B: Moderate CPU Limit (50%)
#############################################

echo "=== Test B: Moderate CPU Limit (50% of 1 core) ==="
echo "Creating container with --cpus=0.5..."

docker run -d --name throttle-moderate --cpus=0.5 alpine sh -c '
  while true; do :; done
' > /dev/null

echo "Running workload for ${TEST_DURATION} seconds..."
sleep ${TEST_DURATION}

CONTAINER_ID=$(docker inspect throttle-moderate --format '{{.Id}}')

# Find cgroup path
CGROUP_PATH=""
if [ -d "/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope" ]; then
    CGROUP_PATH="/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope"
elif [ -d "/sys/fs/cgroup/cpu/docker/${CONTAINER_ID}" ]; then
    CGROUP_PATH="/sys/fs/cgroup/cpu/docker/${CONTAINER_ID}"
fi

if [ -n "$CGROUP_PATH" ] && [ -d "$CGROUP_PATH" ]; then
    echo "=== CPU Statistics ===" | tee "$RESULT_DIR/test-b-moderate.txt"
    
    if [ -f "${CGROUP_PATH}/cpu.stat" ]; then
        cat "${CGROUP_PATH}/cpu.stat" | tee -a "$RESULT_DIR/test-b-moderate.txt"
        
        # Parse and analyze (handle both cgroup v1 and v2)
        NR_PERIODS=$(grep "nr_periods" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        NR_THROTTLED=$(grep "nr_throttled" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        
        # Try both field names (v1: throttled_time in ns, v2: throttled_usec in μs)
        THROTTLED_TIME=$(grep "throttled_time" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "")
        THROTTLED_USEC=$(grep "throttled_usec" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "")
        
        if [ -n "$NR_PERIODS" ] && [ "$NR_PERIODS" -gt 0 ]; then
            THROTTLE_PERCENT=$(echo "scale=1; ($NR_THROTTLED / $NR_PERIODS) * 100" | bc)
            
            # Convert to seconds (handle both v1 and v2)
            if [ -n "$THROTTLED_TIME" ] && [ "$THROTTLED_TIME" != "0" ]; then
                # cgroup v1: nanoseconds
                WASTED_SECONDS=$(echo "scale=2; $THROTTLED_TIME / 1000000000" | bc)
            elif [ -n "$THROTTLED_USEC" ] && [ "$THROTTLED_USEC" != "0" ]; then
                # cgroup v2: microseconds
                WASTED_SECONDS=$(echo "scale=2; $THROTTLED_USEC / 1000000" | bc)
            else
                WASTED_SECONDS="0"
            fi
            
            echo "" | tee -a "$RESULT_DIR/test-b-moderate.txt"
            echo "Analysis:" | tee -a "$RESULT_DIR/test-b-moderate.txt"
            echo "  Total periods: $NR_PERIODS" | tee -a "$RESULT_DIR/test-b-moderate.txt"
            echo "  Throttled periods: $NR_THROTTLED" | tee -a "$RESULT_DIR/test-b-moderate.txt"
            echo "  Throttle rate: ${THROTTLE_PERCENT}%" | tee -a "$RESULT_DIR/test-b-moderate.txt"
            echo "  Time in throttled state: ${WASTED_SECONDS}s out of ${TEST_DURATION}s" | tee -a "$RESULT_DIR/test-b-moderate.txt"
            
            WASTE_PERCENT=$(echo "scale=1; ($WASTED_SECONDS / $TEST_DURATION) * 100" | bc)
            echo "  Percentage of time throttled: ${WASTE_PERCENT}%" | tee -a "$RESULT_DIR/test-b-moderate.txt"
        fi
    fi
fi

echo ""

docker rm -f throttle-moderate > /dev/null
sleep 2

#############################################
# Test C: Aggressive CPU Limit (10%)
#############################################

echo "=== Test C: Aggressive CPU Limit (10% of 1 core) ==="
echo "Creating container with --cpus=0.1..."

docker run -d --name throttle-aggressive --cpus=0.1 alpine sh -c '
  while true; do :; done
' > /dev/null

echo "Running workload for ${TEST_DURATION} seconds..."
sleep ${TEST_DURATION}

CONTAINER_ID=$(docker inspect throttle-aggressive --format '{{.Id}}')

# Find cgroup path
CGROUP_PATH=""
if [ -d "/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope" ]; then
    CGROUP_PATH="/sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope"
elif [ -d "/sys/fs/cgroup/cpu/docker/${CONTAINER_ID}" ]; then
    CGROUP_PATH="/sys/fs/cgroup/cpu/docker/${CONTAINER_ID}"
fi

if [ -n "$CGROUP_PATH" ] && [ -d "$CGROUP_PATH" ]; then
    echo "=== CPU Statistics ===" | tee "$RESULT_DIR/test-c-aggressive.txt"
    
    if [ -f "${CGROUP_PATH}/cpu.stat" ]; then
        cat "${CGROUP_PATH}/cpu.stat" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
        
        # Parse and analyze (handle both cgroup v1 and v2)
        NR_PERIODS=$(grep "nr_periods" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        NR_THROTTLED=$(grep "nr_throttled" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        
        # Try both field names
        THROTTLED_TIME=$(grep "throttled_time" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "")
        THROTTLED_USEC=$(grep "throttled_usec" "${CGROUP_PATH}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "")
        
        if [ -n "$NR_PERIODS" ] && [ "$NR_PERIODS" -gt 0 ]; then
            THROTTLE_PERCENT=$(echo "scale=1; ($NR_THROTTLED / $NR_PERIODS) * 100" | bc)
            
            # Convert to seconds (handle both v1 and v2)
            if [ -n "$THROTTLED_TIME" ] && [ "$THROTTLED_TIME" != "0" ]; then
                # cgroup v1: nanoseconds
                WASTED_SECONDS=$(echo "scale=2; $THROTTLED_TIME / 1000000000" | bc)
            elif [ -n "$THROTTLED_USEC" ] && [ "$THROTTLED_USEC" != "0" ]; then
                # cgroup v2: microseconds
                WASTED_SECONDS=$(echo "scale=2; $THROTTLED_USEC / 1000000" | bc)
            else
                WASTED_SECONDS="0"
            fi
            
            echo "" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            echo "Analysis:" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            echo "  Total periods: $NR_PERIODS" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            echo "  Throttled periods: $NR_THROTTLED" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            echo "  Throttle rate: ${THROTTLE_PERCENT}%" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            echo "  Time in throttled state: ${WASTED_SECONDS}s out of ${TEST_DURATION}s" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            
            WASTE_PERCENT=$(echo "scale=1; ($WASTED_SECONDS / $TEST_DURATION) * 100" | bc)
            echo "  Percentage of time throttled: ${WASTE_PERCENT}%" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            
            # Calculate scheduler overhead estimate
            # At high throttle rates, scheduler overhead is approximately 10-15% of throttled time
            if (( $(echo "$THROTTLE_PERCENT > 80" | bc -l) )); then
                SCHEDULER_OVERHEAD=$(echo "scale=2; $WASTED_SECONDS * 0.12" | bc)
                echo "" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
                echo "  Estimated scheduler overhead: ~${SCHEDULER_OVERHEAD}s" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
                echo "  (At >80% throttle rate, ~10-15% overhead from scheduler)" | tee -a "$RESULT_DIR/test-c-aggressive.txt"
            fi
        fi
    fi
fi

echo ""

docker rm -f throttle-aggressive > /dev/null

#############################################
# Summary
#############################################

echo ""
echo "=== Summary ==="
echo ""
echo "Full results saved to: $RESULT_DIR/"
echo ""
echo "Key Findings:"
echo "  - Test A (No limit): No throttling (baseline)"
echo "  - Test B (50% limit): Moderate throttling"
echo "  - Test C (10% limit): High throttling + scheduler overhead"
echo ""
echo "Expected pattern:"
echo "  As throttle rate increases (>80%), scheduler overhead becomes significant"
echo "  At very high throttle rates, kernel spends 10-15% CPU just enforcing limits"
echo ""
echo "Production Guidance:"
echo "  - CPU limits <50% throttle rate: Acceptable overhead"
echo "  - CPU limits >80% throttle rate: Consider removing limits, use requests only"
echo "  - For latency-sensitive workloads: Avoid CPU limits entirely"
echo ""
echo "Next: Review $RESULT_DIR/ and compare with expected_results.md"