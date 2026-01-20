#!/bin/bash
# cleanup.sh
# Clean up benchmark containers and old results

echo "=== Benchmark Cleanup Utility ==="
echo ""

#############################################
# Clean Docker Containers
#############################################

echo "=== Cleaning Docker Containers ==="

# List of containers used by benchmarks
CONTAINERS="nstest-bench01 netserver webserver throttle-baseline throttle-moderate throttle-aggressive"

REMOVED=0
for container in $CONTAINERS; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container}"; then
        echo "  Removing: $container"
        docker rm -f $container 2>/dev/null && REMOVED=$((REMOVED + 1))
    fi
done

# Clean pattern-matched containers
for name in $(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "nstest-|netserver-|throttle-"); do
    echo "  Removing: $name"
    docker rm -f $name 2>/dev/null && REMOVED=$((REMOVED + 1))
done

if [ $REMOVED -eq 0 ]; then
    echo "  No benchmark containers found"
else
    echo "  Removed $REMOVED container(s)"
fi
echo ""

#############################################
# Clean Old Results
#############################################

echo "=== Cleaning Old Results ==="

# Count existing results
TOTAL=0

# Root results
if [ -d "results" ]; then
    COUNT=$(find results -maxdepth 1 -type d -name "full-suite-*" 2>/dev/null | wc -l)
    echo "  Root results: $COUNT"
    TOTAL=$((TOTAL + COUNT))
fi

# Individual benchmark results
for bench in benchmarks/*/; do
    if [ -d "${bench}results" ]; then
        BENCH_NAME=$(basename "$bench")
        COUNT=$(find "${bench}results" -maxdepth 1 -type d \( -name "20*" -o -name "manual-*" \) 2>/dev/null | wc -l)
        if [ $COUNT -gt 0 ]; then
            echo "  $BENCH_NAME: $COUNT"
            TOTAL=$((TOTAL + COUNT))
        fi
    fi
done

if [ $TOTAL -eq 0 ]; then
    echo "  No results to clean"
else
    echo ""
    echo "  Total: $TOTAL result set(s)"
    echo ""
    read -p "  Keep latest and delete old? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Clean root
        LATEST=$(find results -maxdepth 1 -type d -name "full-suite-*" 2>/dev/null | sort -r | head -1)
        for dir in results/full-suite-*; do
            [ -d "$dir" ] && [ "$dir" != "$LATEST" ] && echo "  Removing: $dir" && rm -rf "$dir"
        done
        [ -n "$LATEST" ] && echo "  Kept: $LATEST"
        
        # Clean benchmarks
        for bench in benchmarks/*/; do
            if [ -d "${bench}results" ]; then
                LATEST=$(find "${bench}results" -maxdepth 1 -type d \( -name "20*" -o -name "manual-*" \) 2>/dev/null | sort -r | head -1)
                for dir in "${bench}results"/20* "${bench}results"/manual-*; do
                    [ -d "$dir" ] && [ "$dir" != "$LATEST" ] && echo "  Removing: $dir" && rm -rf "$dir"
                done
            fi
        done
        
        echo "  Cleanup complete"
    else
        echo "  Cancelled"
    fi
fi

echo ""
echo "=== Summary ==="
echo "  Docker containers: $(docker ps -q 2>/dev/null | wc -l) running"
echo "  Result dirs: $(find results benchmarks/*/results -type d \( -name "20*" -o -name "full-suite-*" -o -name "manual-*" \) 2>/dev/null | wc -l) remaining"
echo ""
echo "Done!"