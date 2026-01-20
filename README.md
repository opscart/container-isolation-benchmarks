# Container Isolation Overhead Benchmarks

**Empirical measurements of Docker container isolation costs in production environments**

> *"We watched a production AKS cluster with 500+ cores throttle itself into 90% CPU waste because of aggressive container limits. We needed to understand: where does the overhead actually come from, and when does it matter?"*

This repository contains reproducible benchmarks measuring the performance overhead of Linux container isolation primitives: namespaces, cgroups, and network virtualization.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## 🎯 Why This Matters

Container isolation isn't free. Understanding these costs helps you make informed decisions about:
- **Resource allocation**: Why aggressive CPU limits waste more resources than they save
- **Workload placement**: When to use containers vs VMs vs bare metal
- **Cost optimization**: Where your compute budget actually goes
- **Performance tuning**: Identifying bottlenecks in production clusters

## 📊 What We Measured

> **⚠️ Terminology Note:** This benchmark measures **Linux kernel namespaces** (PID, network, mount isolation), NOT Kubernetes namespaces (API/RBAC grouping). See clarification below:
> 
> | Concept | Scope | Performance Impact |
> |---------|-------|-------------------|
> | **Linux Namespace** | Kernel-level isolation | +20% syscall overhead, 1800x cross-boundary |
> | **Kubernetes Namespace** | API/RBAC grouping | No performance overhead |

### Benchmark 01: Namespace Syscall Overhead
**Question:** How much does namespace isolation cost for system calls?

**Method:** Measure `getpid()` syscall performance across isolation boundaries
- Host process (baseline)
- Container process (same syscall, different namespace)
- Cross-namespace operation (nsenter)

**Key Finding:** Container namespace adds **+20% overhead** (147ns vs 116ns), but cross-namespace operations are **1800x slower** (1872 microseconds vs 116 nanoseconds)

**Implication:** Tools like `kubectl exec` or `docker exec` are expensive operations - avoid in tight loops or high-frequency monitoring.

---

### Benchmark 02: CPU Throttling Overhead
**Question:** How much CPU does the kernel waste enforcing cgroup limits?

**Method:** Run CPU-intensive workload with different `--cpus` limits, measure throttling statistics from cgroup v2

> **🚨 Critical Finding:** 
> 
> ```
> 50% CPU limit → 90% throttle rate → 30s wasted out of 60s
> 10% CPU limit → 100% throttle rate → 54s wasted out of 60s (90% waste!)
> ```
> 
> **At >80% throttle rate, the kernel wastes ~6-7 seconds just enforcing limits.**
> 
> This isn't a Kubernetes problem - it's kernel scheduler overhead from aggressive cgroup throttling.

**Key Finding:** 
- **50% CPU limit** → 90% throttle rate, 30s wasted out of 60s (50% waste)
- **10% CPU limit** → 100% throttle rate, 54s wasted out of 60s (90% waste)
- At >80% throttle rate, estimated **~6-7 seconds of scheduler overhead**

**Implication:** Aggressive CPU limits don't just restrict resources - they actively waste CPU cycles. For production workloads, prefer CPU requests over hard limits, or keep limits >50% utilization to avoid pathological throttling.

---

### Benchmark 03: Network Namespace Latency
**Question:** What's the latency cost of Docker veth pairs?

**Method:** Measure ICMP ping latency across network isolation boundaries
- Loopback interface (baseline)
- Docker bridge with veth pair
- Kubernetes pod with shared namespace (demonstrates why pods share network namespace - containers in same pod communicate via localhost with no veth overhead)

**Key Finding:** Docker veth pairs add **+20% latency** (0.063ms vs 0.050ms baseline)

**Implication:** For ultra-low-latency workloads, consider host networking or shared network namespaces.

---

## 📋 Quick Summary

| Benchmark | Overhead Measured | Risk Level | Key Recommendation |
|-----------|-------------------|------------|-------------------|
| **01: Namespace Syscall** | +20% / 1800× cross-namespace | Low / Extreme | Avoid frequent `kubectl exec` or `nsenter` in monitoring |
| **02: CPU Throttling** | 50-100% CPU wasted | **High** | Keep throttle rate <80%, prefer requests over limits |
| **03: Network veth** | +20% latency | Low | Host networking only for ultra-low-latency (<100μs) |

---

## 🚀 Quick Start

### Prerequisites

**Linux environment required** (Ubuntu 22.04+ or Azure VM recommended)
- Docker installed and running
- Root/sudo access for cgroup and namespace operations
- `bc`, `gcc`, and standard Linux tools

**Note:** Mac/Windows users can only run Benchmark 01 (namespace syscall). Benchmarks 02 and 03 require Linux kernel cgroup v2 and proper network namespace support.

### Installation

```bash
# Clone repository
git clone https://github.com/opscart/container-isolation-benchmarks.git
cd container-isolation-benchmarks

# Install dependencies (optional - script will check)
./setup/install-tools.sh
```

### Run All Benchmarks (Recommended)

```bash
# Run complete benchmark suite (~7-10 minutes)
sudo ./run-all-benchmarks.sh
```

This will:
1. Run all three benchmarks sequentially
2. Aggregate results in `results/full-suite-TIMESTAMP/`
3. Display summary with key findings
4. Handle errors gracefully (one failing benchmark won't stop the suite)

### Run Individual Benchmarks

```bash
# Benchmark 01: Namespace syscall overhead
cd benchmarks/01-namespace-syscall
sudo ./run.sh

# Benchmark 02: CPU throttling overhead
cd benchmarks/02-cpu-throttling
sudo ./run.sh

# Benchmark 03: Network latency overhead
cd benchmarks/03-network-latency
sudo ./run.sh
```

### View Results

```bash
# View aggregated results
ls -R results/full-suite-*/

# View individual benchmark results
cat results/full-suite-*/benchmark-*-full-output.txt

# Compare with our reference results
diff results/full-suite-*/01-namespace-syscall/ results/full-suite-20260120_155951/01-namespace-syscall/
```

### Cleanup

```bash
# Clean up old results and Docker containers
sudo ./cleanup.sh

# Options:
# sudo ./cleanup.sh --containers  # Clean only Docker containers
# sudo ./cleanup.sh --results     # Clean only old results
# sudo ./cleanup.sh --all         # Clean both (default)
```

---

## 📁 Repository Structure

```
container-isolation-benchmarks/
│
├── README.md                          # This file
├── LICENSE                            # MIT License
│
├── run-all-benchmarks.sh              # Master script - runs all benchmarks
├── cleanup.sh                         # Utility to clean containers and results
│
├── benchmarks/
│   ├── 01-namespace-syscall/
│   │   ├── README.md                  # Detailed methodology
│   │   ├── getpid_bench.c             # C program for syscall measurement
│   │   ├── compile.sh                 # Compile helper
│   │   ├── run.sh                     # Main benchmark script
│   │   └── results/                   # Output directory (generated)
│   │
│   ├── 02-cpu-throttling/
│   │   ├── README.md                  # Detailed methodology
│   │   ├── run.sh                     # Main benchmark script
│   │   └── results/                   # Output directory (generated)
│   │
│   └── 03-network-latency/
│       ├── README.md                  # Detailed methodology
│       ├── run.sh                     # Main benchmark script
│       └── results/                   # Output directory (generated)
│
├── results/
│   └── full-suite-20260120_155951/    # Example results from Azure VM
│       ├── 01-namespace-syscall/
│       ├── 02-cpu-throttling/
│       ├── 03-network-latency/
│       ├── benchmark-01-full-output.txt
│       ├── benchmark-02-full-output.txt
│       └── benchmark-03-full-output.txt
│
├── setup/
│   └── install-tools.sh               # Install dependencies
│
└── analysis/                          # Future: visualization tools
```

---

## 🖥️ Test Environment

### Reference Results From:

**Hardware:** Azure Standard B2ms VM
- 2 vCPUs (Intel Xeon Platinum 8370C @ 2.80GHz)
- 8GB RAM
- Standard SSD

**Software:**
- OS: Ubuntu 24.04 LTS
- Kernel: 6.14.0-1017-azure
- Docker: 28.2.2
- Cgroup: v2 (unified hierarchy)

### Platform Compatibility

| Platform | Benchmark 01 | Benchmark 02 | Benchmark 03 | Notes |
|----------|--------------|--------------|--------------|-------|
| **Linux (Ubuntu/RHEL/Azure)** | ✅ Tested | ✅ Tested | ✅ Tested | Docker on Azure VM |
| **macOS (Docker Desktop)** | ⚠️ Partial | ❌ | ❌ | Syscall test only, no cgroup v2 |
| **Windows (WSL2)** | ❓ Untested | ❓ Untested | ❓ Untested | Not validated, use at own risk |
| **Kubernetes/AKS** | ✅ Compatible* | ✅ Compatible* | ⚠️ Partial* | *See note below |

> **\* Kubernetes/AKS Compatibility Note:**  
> Kubernetes uses the same Linux kernel primitives (namespaces, cgroups, veth pairs) as Docker. Benchmarks 01 and 02 results apply directly to K8s pods since the underlying kernel mechanisms are identical. Benchmark 03 Test C (shared pod networking) is expected to match loopback performance based on architecture but has not been empirically validated on AKS.

---

## 📈 Understanding the Results

### What the Numbers Mean

**Namespace overhead (+20%):**
- ✅ **Acceptable** for most workloads - security benefits outweigh minimal performance cost
- ✅ The kernel's PID namespace translation is well-optimized
- ⚠️ **Watch out** for cross-namespace operations (kubectl exec, debug containers) - these are 1800x slower

**CPU throttling waste:**
- ✅ **<50% throttle rate**: Normal overhead, limits are working as intended
- ⚠️ **50-80% throttle rate**: High but manageable - monitor for performance impact
- 🚨 **>80% throttle rate**: Pathological - kernel is spending significant CPU cycles just enforcing limits
- 💡 **The mechanics**: CFS (Completely Fair Scheduler) must wake/sleep processes every 100ms period. At high throttle rates, this context switching overhead dominates.

**Network overhead (+20%):**
- ✅ **Acceptable** for most applications - the veth driver is efficient
- ✅ Kubernetes pods share network namespace by default (no veth between containers in same pod)
- ⚠️ Consider host networking for ultra-low-latency requirements (<100μs)

### When Does Overhead Matter?

**System-level understanding:**
- **High-frequency syscalls** - Millions of operations per second amplify the 20% overhead
- **Aggressive throttling** - The scheduler wastes cycles enforcing limits it can't realistically meet
- **Cross-namespace operations** - Tools like `kubectl exec` pay the full context switch cost

**Making Informed Decisions:**

Instead of blindly "reducing limits to save money," understand:
1. **What the kernel is actually doing** (namespace lookup, throttle enforcement, packet forwarding)
2. **Where the overhead comes from** (scheduler context switches, veth packet copies)
3. **When it becomes pathological** (>80% throttle rate, thousands of exec calls)

Then you can make engineering trade-offs based on your workload characteristics, not generic advice.

> **Key Insight:** The "cost" (money, performance, latency) is a consequence of understanding kernel mechanics. Engineers who understand *why* throttling wastes CPU will naturally make better scaling and resource allocation decisions.

---

## 🤝 Contributing

We welcome benchmark results from diverse environments! To contribute:

1. **Run benchmarks** on your infrastructure (cloud, on-prem, different CPU architectures)
2. **Archive results:** `tar -czf my-results.tar.gz results/full-suite-*/`
3. **Submit PR** with results and system info
4. **Document differences** if you observe different patterns

See individual benchmark README files for detailed methodology.

---

## 📚 Related Content

**Published Articles:**
- [Container Isolation Overhead Analysis](https://opscart.com) - Full methodology and kernel-level analysis
- [Understanding CPU Throttling in Production](https://dzone.com) - Deep dive into cgroup v2 scheduler mechanics
- [Measuring Container Performance: A Practical Guide](https://dev.to) - Benchmark methodology and reproduction

**Research:**
- IEEE TechRxiv: "Empirical Analysis of Container Isolation Overhead in Production Environments"
- OpsCart Blog: DevOps best practices based on production experience

> **Note:** These articles explain *what happens inside the kernel* when you set container limits and how to make informed decisions about resource allocation. The cost implications are a consequence of understanding the mechanics, not the primary focus.

---

## 👨‍💻 Author

**Shamsher Khan**
- IEEE Senior Member
- Senior DevOps Engineer @ GlobalLogic (Hitachi Group)
- 15+ years managing production Kubernetes clusters (500+ cores, Fortune 500 clients)
- Focus: Container security, cost optimization, AI-powered DevOps

**Connect:**
- Website: [opscart.com](https://opscart.com)
- GitHub: [github.com/opscart](https://github.com/opscart)
- LinkedIn: [Shamsher Khan](https://linkedin.com/in/shamsher-khan)
- IEEE Collabratec: [Profile](https://ieee-collabratec.ieee.org)

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Linux kernel developers for transparent cgroup v2 metrics
- Docker and Kubernetes communities for containerization technology
- Azure for providing test infrastructure
- GlobalLogic for supporting open-source contributions

---

## 🔖 Citation

If you use these benchmarks in research or publications:

```bibtex
@misc{khan2025container,
  author = {Khan, Shamsher},
  title = {Container Isolation Overhead Benchmarks: Empirical Measurements of Docker and Kubernetes Performance Costs},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/opscart/container-isolation-benchmarks}
}
```

---

**Questions? Issues?** Open an issue on GitHub or reach out via [opscart.com](https://opscart.com)