#!/bin/bash
# benchmarks/01-namespace-syscall/compile.sh
# Compile the getpid benchmark (Mac compatible version)

set -euo pipefail

echo "Compiling getpid_bench..."

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Mac: Can't use -static, use dynamic linking
    # Warnings about syscall are OK - it still works
    gcc -O2 -o getpid_bench getpid_bench.c 2>&1 | grep -v "warning: 'syscall' is deprecated" || true
    
    if [ -f getpid_bench ]; then
        echo "Compiled successfully: getpid_bench (Mac/dynamic)"
        echo "Binary size: $(du -h getpid_bench | cut -f1)"
        echo "⚠ Note: syscall() is deprecated on Mac but still works"
        echo "   For production testing, use Linux (Docker or AKS)"
    else
        echo "Compilation failed"
        exit 1
    fi
else
    # Linux: Use static linking
    gcc -O2 -static -o getpid_bench getpid_bench.c
    
    if [ $? -eq 0 ]; then
        echo "Compiled successfully: getpid_bench"
        echo "Binary size: $(du -h getpid_bench | cut -f1)"
        
        if file getpid_bench | grep -q "statically linked"; then
            echo "Static binary confirmed"
        fi
    else
        echo "Compilation failed"
        exit 1
    fi
fi
