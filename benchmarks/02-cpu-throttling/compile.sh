#!/bin/bash
# compile.sh - Compile the pure CPU workload program

set -e

echo "Compiling pure_cpu_workload.c (static binary for Alpine compatibility)..."

gcc -o pure_cpu_workload pure_cpu_workload.c -O2 -Wall -static

if [ -f pure_cpu_workload ]; then
    echo "Successfully compiled pure_cpu_workload"
    echo ""
    echo "Test it:"
    echo "  ./pure_cpu_workload              # Default: 50ms burst, 50ms sleep, 60s"
    echo "  ./pure_cpu_workload 100 100 10   # 100ms burst, 100ms sleep, 10s"
else
    echo "Compilation failed"
    exit 1
fi