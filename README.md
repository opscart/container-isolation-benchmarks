# Container Isolation Overhead Benchmarks

**Measuring the real performance cost of Docker containers vs Kubernetes pods**

This repository contains benchmarks to measure the overhead of Linux container isolation primitives: namespaces, cgroups, and network virtualization.

## Why This Matters

Container isolation isn't free. In production environments with hundreds or thousands of containers, the overhead of namespace crossing, cgroup throttling, and network virtualization can consume 10-20% of your compute budget.

This project provides:
- **Reproducible benchmarks** you can run on your infrastructure
- **Real measurements** from production-grade AKS clusters
- **Honest analysis** of trade-offs between isolation and performance

## What We Measure

### Benchmark 01: Namespace Syscall Overhead
- **Question:** How much does crossing namespace boundaries cost?
- **Method:** Measure `getpid()` syscall in host vs container vs cross-namespace
- **Key Finding:** Cross-namespace operations (like `kubectl exec`) add 700%+ overhead

### Benchmark 02: CPU Throttling Waste
- **Question:** How much CPU does the kernel waste enforcing cgroup limits?
- **Method:** Run CPU-intensive workload with `--cpus` limit, measure scheduler overhead
- **Key Finding:** At high throttle rates (>80%), kernel spends 10-15% CPU just enforcing limits

### Benchmark 03: Network Namespace Latency
- **Question:** What's the cost of veth pairs vs shared network namespaces?
- **Method:** Use `sockperf` to measure Docker (veth) vs Kubernetes pod (shared namespace)
- **Key Finding:** veth pairs add 35μs per packet; shared namespaces eliminate this overhead

## Quick Start

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y build-essential linux-tools-generic docker.io

# For network tests
sudo apt-get install -y sockperf

# For Kubernetes tests
# Install kubectl, minikube, or have access to AKS cluster
```

### Run All Benchmarks

```bash
# Clone repository
git clone https://github.com/opscart/container-isolation-benchmarks
cd container-isolation-benchmarks

# Install dependencies
./setup/install-tools.sh

# Run benchmarks
./benchmarks/01-namespace-syscall/run.sh
./benchmarks/02-cpu-throttling/run.sh
./benchmarks/03-network-latency/run.sh

# View results
cat results/summary.txt
```

### Run Individual Benchmark

```bash
cd benchmarks/01-namespace-syscall
./run.sh
```

## Repository Structure

```
container-isolation-benchmarks/
├── README.md                     # This file
├── RESULTS.md                    # Our production AKS results
├── LICENSE                       # MIT License
│
├── benchmarks/
│   ├── 01-namespace-syscall/     # Namespace crossing overhead
│   ├── 02-cpu-throttling/        # cgroup CPU limit overhead  
│   └── 03-network-latency/       # veth vs shared namespace
│
├── analysis/
│   └── visualize.py              # Generate charts from results
│
├── setup/
│   └── install-tools.sh          # Install dependencies
│
└── results/
    ├── local/                    # Your local test results
    └── aks-production/           # Production cluster results
```

## Test Environments

### Our Results Come From:

**Local Testing:**
- 3-node Minikube cluster
- Ubuntu 24.04, kernel 6.5
- Docker 25.0.3, containerd 1.7.12

**Production Testing:**
- Azure AKS cluster
- 3 nodes, Standard_D8s_v3 (8 vCPU, 32GB RAM each)
- Kubernetes 1.28.5
- Real production workload characteristics

## Contributing

We welcome contributions! Please:

1. Run benchmarks on your infrastructure
2. Submit results via PR to `results/community/`
3. Include system info: CPU model, kernel version, container runtime

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Related Articles

- [The Hidden Cost of Container Isolation](https://opscart.com/container-isolation-overhead) - Main article with full analysis
- [DZone: Docker vs Kubernetes Performance](https://dzone.com/...) - Condensed version

## Credits

Created by [Shamsher Khan](https://github.com/opscart) | [OpsCart.com](https://opscart.com)

IEEE Senior Member | Senior DevOps Engineer at GlobalLogic (Hitachi Group)

## License

MIT License - See [LICENSE](LICENSE) file for details