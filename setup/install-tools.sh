#!/bin/bash
# setup/install-tools.sh
# Install dependencies for container isolation benchmarks

set -euo pipefail

echo "=== Installing Container Isolation Benchmark Tools ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS. Please install tools manually."
    exit 1
fi

echo "Detected OS: $OS"

# Install based on OS
case $OS in
    ubuntu|debian)
        echo "Installing tools for Ubuntu/Debian..."
        apt-get update
        
        # Build tools for C programs
        apt-get install -y build-essential
        
        # Performance analysis tools
        apt-get install -y linux-tools-generic linux-tools-common
        
        # Network benchmarking
        apt-get install -y sockperf iperf3 jq
        
        # Container runtime (if not already installed)
        if ! command -v docker &> /dev/null; then
            echo "Docker not found. Installing..."
            apt-get install -y docker.io
            systemctl enable docker
            systemctl start docker
        fi
        
        # Utilities
        apt-get install -y bc jq curl
        ;;
        
    centos|rhel|fedora)
        echo "Installing tools for CentOS/RHEL/Fedora..."
        yum install -y gcc make kernel-devel
        yum install -y perf iperf3 bc jq curl
        
        if ! command -v docker &> /dev/null; then
            yum install -y docker
            systemctl enable docker
            systemctl start docker
        fi
        
        # Note: sockperf may need to be compiled from source
        echo "Warning: sockperf not available in default repos. May need manual installation."
        ;;
        
    *)
        echo "Unsupported OS: $OS"
        echo "Please install these tools manually:"
        echo "  - gcc, make"
        echo "  - perf (linux-tools)"
        echo "  - sockperf"
        echo "  - iperf3"
        echo "  - docker"
        echo "  - bc, jq"
        exit 1
        ;;
esac

# Verify installations
echo ""
echo "=== Verifying Tool Installation ==="

check_tool() {
    if command -v $1 &> /dev/null; then
        VERSION=$($1 --version 2>&1 | head -n1 || echo "installed")
        echo "$1: $VERSION"
        return 0
    else
        echo "$1: NOT FOUND"
        return 1
    fi
}

ALL_GOOD=true

check_tool gcc || ALL_GOOD=false
check_tool perf || ALL_GOOD=false
check_tool docker || ALL_GOOD=false
check_tool sockperf || echo "⚠ sockperf: Optional (for network benchmark)"
check_tool iperf3 || echo "⚠ iperf3: Optional (for throughput benchmark)"
check_tool bc || ALL_GOOD=false
check_tool jq || ALL_GOOD=false

if [ "$ALL_GOOD" = true ]; then
    echo ""
    echo "All required tools installed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. cd benchmarks/01-namespace-syscall"
    echo "  2. ./run.sh"
else
    echo ""
    echo "Some required tools are missing. Please install them manually."
    exit 1
fi

# Verify perf can access kernel symbols
echo ""
echo "=== Checking perf permissions ==="
if perf stat -e cycles -- sleep 0.1 2>&1 | grep -q "not counted"; then
    echo "⚠ Warning: perf may have permission issues"
    echo "Try: sudo sysctl -w kernel.perf_event_paranoid=-1"
else
    echo "perf has proper permissions"
fi

# Check if running in container
echo ""
echo "=== Environment Check ==="
if [ -f /.dockerenv ]; then
    echo "⚠ Warning: Running inside a container"
    echo "Some benchmarks may not work correctly. Run on host for best results."
else
    echo "Running on host system"
fi

echo ""
echo "=== Setup Complete ==="
echo "You can now run benchmarks from the benchmarks/ directory"