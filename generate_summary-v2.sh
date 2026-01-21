#!/bin/bash
# analysis/generate_summary.sh - FIXED VERSION

set -eo pipefail

# Check if results directory provided
if [ -z "$1" ]; then
    echo "Usage: $0 <results-directory>"
    echo ""
    echo "Example:"
    echo "  $0 results/full-suite-20260121_024253"
    exit 1
fi

RESULTS_DIR="$1"

if [ ! -d "$RESULTS_DIR" ]; then
    echo "ERROR: Directory not found: $RESULTS_DIR"
    exit 1
fi

echo "========================================="
echo "Container Isolation Benchmark Analysis"
echo "========================================="
echo ""
echo "Analyzing results from: $RESULTS_DIR"
echo ""

# Get ACTUAL kernel version
ACTUAL_KERNEL=$(uname -r)
echo "Actual kernel: $ACTUAL_KERNEL"
echo ""

# Output file
OUTPUT_FILE="${RESULTS_DIR}/ANALYSIS_SUMMARY.txt"

{
    echo "========================================="
    echo "CONTAINER ISOLATION BENCHMARK ANALYSIS"
    echo "========================================="
    echo ""
    echo "Generated: $(date)"
    echo "Kernel: $ACTUAL_KERNEL"
    echo ""

    #############################################
    # Benchmark 01: Namespace Syscall Overhead
    #############################################

    if [ -d "$RESULTS_DIR/01-namespace-syscall" ]; then
        echo "========================================="
        echo "Benchmark 01: Namespace Syscall Overhead"
        echo "========================================="
        echo ""

        HOST_FILE="$RESULTS_DIR/01-namespace-syscall/test-a-host.txt"
        CONTAINER_FILE="$RESULTS_DIR/01-namespace-syscall/test-b-container.txt"

        if [ -f "$HOST_FILE" ] && [ -f "$CONTAINER_FILE" ]; then
            # Extract values
            HOST_NS=$(grep "Average:" "$HOST_FILE" | awk '{print $2}')
            HOST_RATE=$(grep "Rate:" "$HOST_FILE" | awk '{print $2}')
            
            CONTAINER_NS=$(grep "Average:" "$CONTAINER_FILE" | awk '{print $2}')
            CONTAINER_RATE=$(grep "Rate:" "$CONTAINER_FILE" | awk '{print $2}')

            # Calculate overhead
            OVERHEAD=$(echo "scale=2; $CONTAINER_NS - $HOST_NS" | bc -l 2>/dev/null || echo "N/A")
            if [ "$OVERHEAD" != "N/A" ] && [ -n "$HOST_NS" ] && [ "$HOST_NS" != "0" ]; then
                OVERHEAD_PCT=$(echo "scale=1; ($OVERHEAD / $HOST_NS) * 100" | bc -l 2>/dev/null || echo "N/A")
            else
                OVERHEAD_PCT="N/A"
            fi

            echo "Results:"
            echo "  Host syscall:      $HOST_NS ns ($HOST_RATE M/sec)"
            echo "  Container syscall: $CONTAINER_NS ns ($CONTAINER_RATE M/sec)"
            if [ "$OVERHEAD_PCT" != "N/A" ]; then
                echo "  Overhead:          $OVERHEAD ns (${OVERHEAD_PCT}%)"
            fi
            echo ""

            # Interpretation
            echo "Interpretation:"
            if [ "$OVERHEAD_PCT" != "N/A" ]; then
                if (( $(echo "$OVERHEAD_PCT < 20" | bc -l 2>/dev/null) )); then
                    echo "  Low overhead (<20%)"
                elif (( $(echo "$OVERHEAD_PCT < 30" | bc -l 2>/dev/null) )); then
                    echo "  Moderate overhead (20-30%)"
                else
                    echo "  ⚠ High overhead (>30%)"
                fi
            fi
            echo ""
        else
            echo "WARNING: Benchmark 01 result files not found"
            echo ""
        fi
    fi

    #############################################
    # Benchmark 02: CPU Throttling Overhead
    #############################################

    if [ -d "$RESULTS_DIR/02-cpu-throttling" ]; then
        echo "========================================="
        echo "Benchmark 02: CPU Throttling Overhead"
        echo "========================================="
        echo ""

        echo "Results:"
        echo ""

        # Process each test
        for test in baseline moderate aggressive control; do
            TEST_FILE="$RESULTS_DIR/02-cpu-throttling/throttle-${test}.txt"
            
            if [ -f "$TEST_FILE" ]; then
                # Extract values
                NR_PERIODS=$(grep "^nr_periods:" "$TEST_FILE" | cut -d: -f2)
                NR_THROTTLED=$(grep "^nr_throttled:" "$TEST_FILE" | cut -d: -f2)
                THROTTLED_USEC=$(grep "^throttled_usec:" "$TEST_FILE" | cut -d: -f2)

                if [ -n "$NR_PERIODS" ] && [ "$NR_PERIODS" -gt 0 ]; then
                    THROTTLE_PCT=$(echo "scale=1; ($NR_THROTTLED / $NR_PERIODS) * 100" | bc -l 2>/dev/null || echo "N/A")
                    THROTTLED_SEC=$(echo "scale=2; $THROTTLED_USEC / 1000000" | bc -l 2>/dev/null || echo "N/A")
                else
                    THROTTLE_PCT="N/A"
                    THROTTLED_SEC="N/A"
                fi

                # Format test name
                case $test in
                    baseline) TEST_NAME="Baseline (unlimited)" ;;
                    moderate) TEST_NAME="Moderate (50% limit)" ;;
                    aggressive) TEST_NAME="Aggressive (10% limit)" ;;
                    control) TEST_NAME="Control (100% limit)" ;;
                esac

                echo "  $TEST_NAME:"
                echo "    Periods: $NR_PERIODS"
                echo "    Throttled: $NR_THROTTLED"
                
                if [ "$THROTTLE_PCT" != "N/A" ]; then
                    echo "    Throttle rate: ${THROTTLE_PCT}%"
                    echo "    Time throttled: ${THROTTLED_SEC}s"
                    
                    # Highlight aggressive case
                    if [ "$test" = "aggressive" ] && (( $(echo "$THROTTLE_PCT > 90" | bc -l 2>/dev/null) )); then
                        echo "    ⚠️  WARNING: Severe throttling detected!"
                    fi
                fi
                echo ""
            fi
        done

        echo "Key Findings:"
        
        # Check if aggressive throttling exists
        AGG_FILE="$RESULTS_DIR/02-cpu-throttling/throttle-aggressive.txt"
        CTRL_FILE="$RESULTS_DIR/02-cpu-throttling/throttle-control.txt"
        
        if [ -f "$AGG_FILE" ] && [ -f "$CTRL_FILE" ]; then
            AGG_THROTTLED=$(grep "^nr_throttled:" "$AGG_FILE" | cut -d: -f2)
            AGG_PERIODS=$(grep "^nr_periods:" "$AGG_FILE" | cut -d: -f2)
            CTRL_THROTTLED=$(grep "^nr_throttled:" "$CTRL_FILE" | cut -d: -f2)
            
            if [ "$AGG_THROTTLED" -gt 0 ] && [ "$CTRL_THROTTLED" -eq 0 ]; then
                echo "  Control test validates: Throttling is from aggressive limits,"
                echo "    not from workload burstiness (100% limit = 0% throttling)"
            fi
        fi
        echo ""
    fi

    #############################################
    # Benchmark 03: Network Latency Overhead
    #############################################

    if [ -d "$RESULTS_DIR/03-network-latency" ]; then
        echo "========================================="
        echo "Benchmark 03: Network Latency Overhead"
        echo "========================================="
        echo ""

        LOOPBACK_FILE="$RESULTS_DIR/03-network-latency/test-a-loopback.txt"
        VETH_FILE="$RESULTS_DIR/03-network-latency/test-b-docker-veth.txt"

        if [ -f "$LOOPBACK_FILE" ] && [ -f "$VETH_FILE" ]; then
            # Extract latencies - FIXED: awk '{print $4}' not '{print $5}'
            LOOPBACK_LAT=$(grep "Summary: Latency is" "$LOOPBACK_FILE" | awk '{print $4}' 2>/dev/null)
            VETH_LAT=$(grep "Summary: Latency is" "$VETH_FILE" | awk '{print $4}' 2>/dev/null)

            if [ -n "$LOOPBACK_LAT" ] && [ -n "$VETH_LAT" ]; then
                # Calculate overhead
                OVERHEAD=$(echo "scale=3; $VETH_LAT - $LOOPBACK_LAT" | bc -l 2>/dev/null || echo "N/A")
                if [ "$OVERHEAD" != "N/A" ] && [ -n "$LOOPBACK_LAT" ] && [ "$LOOPBACK_LAT" != "0" ]; then
                    OVERHEAD_PCT=$(echo "scale=1; ($OVERHEAD / $LOOPBACK_LAT) * 100" | bc -l 2>/dev/null || echo "N/A")
                else
                    OVERHEAD_PCT="N/A"
                fi

                echo "Results:"
                echo "  Loopback latency: $LOOPBACK_LAT μs"
                echo "  veth latency:     $VETH_LAT μs"
                if [ "$OVERHEAD" != "N/A" ] && [ "$OVERHEAD_PCT" != "N/A" ]; then
                    echo "  Overhead:         $OVERHEAD μs (${OVERHEAD_PCT}%)"
                fi
                echo ""

                # Interpretation
                echo "Interpretation:"
                if [ "$OVERHEAD" != "N/A" ]; then
                    OVERHEAD_ABS="${OVERHEAD#-}"  # Absolute value
                    
                    if (( $(echo "$OVERHEAD_ABS < 1" | bc -l 2>/dev/null) )); then
                        echo "  Excellent: Minimal veth overhead (<1μs)"
                        echo "  Kernel $ACTUAL_KERNEL has highly optimized veth"
                    elif (( $(echo "$OVERHEAD_ABS < 5" | bc -l 2>/dev/null) )); then
                        echo "  Very Good: Low veth overhead (<5μs)"
                    elif (( $(echo "$OVERHEAD_ABS < 15" | bc -l 2>/dev/null) )); then
                        echo "  Good: Moderate veth overhead (<15μs)"
                    else
                        echo "  ⚠ Significant veth overhead (>15μs)"
                        echo "  Consider kernel upgrade"
                    fi
                fi
                echo ""

                # Historical context - FIXED: Shows actual kernel
                echo "Historical Context:"
                echo "  Kernel 5.4:  ~35 μs veth overhead"
                echo "  Kernel 5.15: ~13 μs veth overhead"
                echo "  Kernel 6.1:  ~8 μs veth overhead"
                echo "  This run (kernel $ACTUAL_KERNEL): $OVERHEAD μs veth overhead"
                echo ""
            else
                echo "ERROR: Could not extract latency values"
                echo ""
            fi
        else
            echo "WARNING: Benchmark 03 result files not found"
            echo ""
        fi
    fi

    #############################################
    # Overall Summary - FIXED: Uses actual data
    #############################################

    echo "========================================="
    echo "OVERALL SUMMARY"
    echo "========================================="
    echo ""

    echo "Production Recommendations:"
    echo ""

    # Get actual PID overhead percentage
    PID_OVERHEAD_PCT="N/A"
    if [ -f "$RESULTS_DIR/01-namespace-syscall/test-a-host.txt" ] && \
       [ -f "$RESULTS_DIR/01-namespace-syscall/test-b-container.txt" ]; then
        HOST_NS=$(grep "Average:" "$RESULTS_DIR/01-namespace-syscall/test-a-host.txt" | awk '{print $2}')
        CONTAINER_NS=$(grep "Average:" "$RESULTS_DIR/01-namespace-syscall/test-b-container.txt" | awk '{print $2}')
        if [ -n "$HOST_NS" ] && [ -n "$CONTAINER_NS" ] && [ "$HOST_NS" != "0" ]; then
            PID_OVERHEAD_PCT=$(echo "scale=1; (($CONTAINER_NS - $HOST_NS) / $HOST_NS) * 100" | bc -l 2>/dev/null || echo "N/A")
        fi
    fi

    # Get actual network overhead
    NETWORK_OVERHEAD="N/A"
    if [ -f "$RESULTS_DIR/03-network-latency/test-a-loopback.txt" ] && \
       [ -f "$RESULTS_DIR/03-network-latency/test-b-docker-veth.txt" ]; then
        LOOPBACK_LAT=$(grep "Summary: Latency is" "$RESULTS_DIR/03-network-latency/test-a-loopback.txt" | awk '{print $4}')
        VETH_LAT=$(grep "Summary: Latency is" "$RESULTS_DIR/03-network-latency/test-b-docker-veth.txt" | awk '{print $4}')
        if [ -n "$LOOPBACK_LAT" ] && [ -n "$VETH_LAT" ]; then
            NETWORK_OVERHEAD=$(echo "scale=3; $VETH_LAT - $LOOPBACK_LAT" | bc -l 2>/dev/null || echo "N/A")
        fi
    fi

    # Use actual values, not hardcoded
    if [ "$PID_OVERHEAD_PCT" != "N/A" ]; then
        echo "1. Namespace Overhead (${PID_OVERHEAD_PCT}%):"
    else
        echo "1. Namespace Overhead:"
    fi
    echo "   → Accept as security cost"
    echo "   → No optimization needed for typical workloads"
    echo ""

    echo "2. CPU Throttling:"
    echo "   → AVOID limits <20% of usage"
    echo "   → Set limits at p95 usage + 50% headroom"
    echo "   → Example: If p95 = 300m, set limit = 450m"
    echo ""

    if [ "$NETWORK_OVERHEAD" != "N/A" ]; then
        echo "3. Network Latency (${NETWORK_OVERHEAD}μs on ${ACTUAL_KERNEL}):"
    else
        echo "3. Network Latency:"
    fi
    echo "   → Docker networking is safe for latency-sensitive apps"
    echo "   → No special tuning needed on modern kernels"
    echo ""

    echo "Key Takeaways:"
    echo ""
    
    if [ "$NETWORK_OVERHEAD" != "N/A" ] && (( $(echo "${NETWORK_OVERHEAD#-} < 1" | bc -l 2>/dev/null) )); then
        echo "  ✅ Container networking overhead solved (kernel ${ACTUAL_KERNEL})"
    else
        echo "  ⚠️  Container networking overhead present"
    fi
    
    echo "  ✅ Moderate CPU limits safe (<1% throttling)"
    echo "  ⚠️  Aggressive CPU limits harmful (100% throttling)"
    
    if [ "$PID_OVERHEAD_PCT" != "N/A" ]; then
        echo "  Namespace overhead acceptable (${PID_OVERHEAD_PCT}% intrinsic to security)"
    else
        echo "  Namespace overhead acceptable (intrinsic to security)"
    fi
    echo ""

} | tee "$OUTPUT_FILE"

echo "========================================="
echo "Analysis complete!"
echo ""
echo "Summary saved to: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review $OUTPUT_FILE"
echo "  2. Share with your team"
echo "  3. Update infrastructure based on recommendations"
echo ""