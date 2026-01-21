#!/bin/bash
# benchmarks/02-cpu-throttling/run.sh
# FIXED VERSION - Read cgroup stats BEFORE container stops

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Benchmark 02: CPU Throttling Overhead"
echo "========================================="
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "Docker not found."
    exit 1
fi

if ! docker info &> /dev/null 2>&1; then
    echo "Docker daemon not running."
    exit 1
fi

# Compile if needed
if [ ! -f pure_cpu_workload ]; then
    echo "Compiling pure CPU workload..."
    ./compile.sh
    echo ""
fi

# Create results
mkdir -p results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="results/${TIMESTAMP}"
mkdir -p "$RESULT_DIR"

echo "Results: $RESULT_DIR"
echo ""

# Cleanup
docker rm -f throttle-baseline throttle-moderate throttle-aggressive throttle-control 2>/dev/null || true

# Test duration
TEST_DURATION=30  # 30 seconds
echo "Test duration: ${TEST_DURATION} seconds per test"
echo "Workload: Pure CPU (50ms burst + 50ms sleep)"
echo ""

# Function to find cgroup path for a container
find_cgroup_path() {
    local container_name=$1
    local container_id=$(docker inspect "$container_name" --format '{{.Id}}')
    
    # Try common cgroup v2 paths first
    if [ -d "/sys/fs/cgroup/system.slice/docker-${container_id}.scope" ]; then
        echo "/sys/fs/cgroup/system.slice/docker-${container_id}.scope"
        return 0
    fi
    
    # Try cgroup v1 paths
    for base_path in \
        "/sys/fs/cgroup/cpu/docker/${container_id}" \
        "/sys/fs/cgroup/cpu,cpuacct/docker/${container_id}" \
        "/sys/fs/cgroup/cpu/system.slice/docker-${container_id}.scope" \
        "/sys/fs/cgroup/cpuacct/docker/${container_id}"
    do
        if [ -d "$base_path" ]; then
            echo "$base_path"
            return 0
        fi
    done
    
    # Last resort: search
    local found=$(find /sys/fs/cgroup -type d -name "*${container_id:0:12}*" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

# Function to read CPU stats from cgroup
read_cpu_stats() {
    local cgroup_path=$1
    local output_file=$2
    
    if [ -f "${cgroup_path}/cpu.stat" ]; then
        # cgroup v2
        cat "${cgroup_path}/cpu.stat" | tee -a "$output_file"
        
        local nr_periods=$(grep "nr_periods" "${cgroup_path}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        local nr_throttled=$(grep "nr_throttled" "${cgroup_path}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        local throttled_usec=$(grep "throttled_usec" "${cgroup_path}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        
        echo "nr_periods:$nr_periods" >> "$output_file"
        echo "nr_throttled:$nr_throttled" >> "$output_file"
        echo "throttled_usec:$throttled_usec" >> "$output_file"
        
    elif [ -f "${cgroup_path}/cpu.cfs_period_us" ]; then
        # cgroup v1
        echo "=== cgroup v1 CPU stats ===" | tee -a "$output_file"
        [ -f "${cgroup_path}/cpu.cfs_quota_us" ] && echo "cpu.cfs_quota_us: $(cat ${cgroup_path}/cpu.cfs_quota_us)" | tee -a "$output_file"
        [ -f "${cgroup_path}/cpu.cfs_period_us" ] && echo "cpu.cfs_period_us: $(cat ${cgroup_path}/cpu.cfs_period_us)" | tee -a "$output_file"
        [ -f "${cgroup_path}/cpu.stat" ] && cat "${cgroup_path}/cpu.stat" | tee -a "$output_file"
        [ -f "${cgroup_path}/cpuacct.stat" ] && cat "${cgroup_path}/cpuacct.stat" | tee -a "$output_file"
        
        # Parse throttling stats
        local nr_periods=$(grep "nr_periods" "${cgroup_path}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        local nr_throttled=$(grep "nr_throttled" "${cgroup_path}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        local throttled_time=$(grep "throttled_time" "${cgroup_path}/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
        
        echo "nr_periods:$nr_periods" >> "$output_file"
        echo "nr_throttled:$nr_throttled" >> "$output_file"
        echo "throttled_time:$throttled_time" >> "$output_file"
    else
        echo "WARNING: No CPU stats found in $cgroup_path" | tee -a "$output_file"
        return 1
    fi
    
    return 0
}

# Function to analyze results
analyze_results() {
    local result_file=$1
    local actual_cpu=$2
    local test_name=$3
    
    if [ ! -f "$result_file" ]; then
        echo "  WARNING: No stats file found"
        return
    fi
    
    local nr_periods=$(grep "^nr_periods:" "$result_file" 2>/dev/null | cut -d: -f2 || echo "0")
    local nr_throttled=$(grep "^nr_throttled:" "$result_file" 2>/dev/null | cut -d: -f2 || echo "0")
    
    if [ "$nr_periods" -gt 0 ]; then
        local throttle_percent=$(echo "scale=1; ($nr_throttled / $nr_periods) * 100" | bc -l)
        
        echo "" | tee -a "$result_file"
        echo "Summary:" | tee -a "$result_file"
        echo "  CPU usage: ${actual_cpu}%" | tee -a "$result_file"
        echo "  Throttle rate: ${throttle_percent}%" | tee -a "$result_file"
        echo "  Periods: $nr_periods" | tee -a "$result_file"
        echo "  Throttled: $nr_throttled" | tee -a "$result_file"
    else
        echo "" | tee -a "$result_file"
        echo "Summary:" | tee -a "$result_file"
        echo "  CPU usage: ${actual_cpu}%" | tee -a "$result_file"
        echo "  WARNING: Could not calculate throttle stats" | tee -a "$result_file"
    fi
}

# Function to run one test
run_test() {
    local name=$1
    local cpus=$2
    local hypothesis=$3
    
    echo "=== $name ==="
    echo "Hypothesis: $hypothesis"
    echo ""
    
    # Run container
    if [ "$cpus" = "none" ]; then
        docker run -d --name "$name" -v "$(pwd)/pure_cpu_workload:/workload" alpine /workload 50 50 ${TEST_DURATION} > /dev/null
    else
        docker run -d --name "$name" --cpus="$cpus" -v "$(pwd)/pure_cpu_workload:/workload" alpine /workload 50 50 ${TEST_DURATION} > /dev/null
    fi
    
    # Wait for startup
    sleep 2
    
    echo "Workload running..."
    
    # Find cgroup path WHILE container is running
    CGROUP_PATH=$(find_cgroup_path "$name")
    
    if [ -z "$CGROUP_PATH" ]; then
        echo "  WARNING: Could not find cgroup path for $name"
        echo "  Skipping stats collection"
    else
        echo "  Found cgroup: $CGROUP_PATH"
    fi
    
    # Sample CPU during execution
    echo "Sampling CPU usage..."
    ACTUAL_CPU=$(for i in $(seq 1 5); do
        docker stats --no-stream --format "{{.CPUPerc}}" "$name" 2>/dev/null | sed 's/%//' || echo "0"
        sleep 2
    done | awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print "0"}')
    
    echo "Observed average CPU usage: ${ACTUAL_CPU}%"
    
    # Read stats BEFORE container stops
    if [ -n "$CGROUP_PATH" ]; then
        echo "Reading cgroup stats..."
        RESULT_FILE="$RESULT_DIR/${name}.txt"
        echo "=== CPU Statistics ===" | tee "$RESULT_FILE"
        if read_cpu_stats "$CGROUP_PATH" "$RESULT_FILE"; then
            echo "  Stats saved to $RESULT_FILE"
            # Analyze after reading
            analyze_results "$RESULT_FILE" "$ACTUAL_CPU" "$name"
        fi
    fi
    
    # Now wait for completion
    echo "Waiting for workload to complete..."
    docker wait "$name" > /dev/null 2>&1 || true
    
    echo ""
    docker rm -f "$name" > /dev/null 2>&1 || true
    sleep 2
}

#############################################
# Run tests
#############################################

# Test A: No limit
run_test "throttle-baseline" "none" "Unlimited CPU → minimal throttling"

# Test B: 50% limit
run_test "throttle-moderate" "0.5" "50% limit on 50% workload → moderate throttling"

# Test C: 10% limit
run_test "throttle-aggressive" "0.1" "10% limit → high throttling"

# Test D: 100% limit (control)
run_test "throttle-control" "1.0" "100% limit → minimal throttling (control)"

#############################################
# Summary
#############################################

echo ""
echo "=== Summary ==="
echo ""
echo "Full results: $RESULT_DIR/"
echo ""
echo "Result files:"
ls -lh "$RESULT_DIR/"*.txt 2>/dev/null || echo "  (no .txt files created - check for errors above)"
echo ""
echo "Done."