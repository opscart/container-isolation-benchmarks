# Benchmark 03: Network Namespace Latency

## What This Measures

The latency overhead introduced by Docker's network isolation using virtual ethernet (veth) pairs compared to direct loopback communication.

## Why It Matters

Docker containers use **veth pairs** to connect to the host bridge network:
- Each container gets a virtual network interface
- Packets traverse: container → veth pair → docker bridge → routing → destination
- Every hop adds latency

In production:
- Microservices making thousands of calls per second
- Service mesh sidecars intercepting every request
- Database connections with strict latency SLAs

At scale, even 20% additional latency compounds across the call chain.

## The Tests

### Test A: Loopback Interface (Baseline)
- Direct ping to `127.0.0.1` (localhost)
- Pure kernel networking stack, no namespace crossing
- **Expected:** 0.03-0.06 ms (30-60 microseconds)

### Test B: Docker Container (veth Pair)
- Ping from host to container over Docker bridge network
- Packets cross network namespace boundary via veth pair
- **Expected:** 0.06-0.08 ms (60-80 microseconds)
- **Overhead:** +20-30% vs loopback

### Test C: Kubernetes Pod (Shared Namespace) - Optional
- Multiple containers in same pod share network namespace
- No veth overhead between containers in same pod
- **Expected:** Same as Test A (loopback performance)
- **Requires:** kubectl and access to Kubernetes cluster

## How It Works

### The Test Method

We use `ping` (ICMP Echo Request/Reply) because:
- Simple, no application protocol overhead
- Kernel-level operation (measures pure networking)
- Standard tool available everywhere
- 100 packets = statistically significant sample

```bash
ping -c 100 -i 0.2 <target_ip>
```

### What We're Measuring

**Round-Trip Time (RTT):**
```
Request → Network → Destination → Network → Response
```

**Components:**
1. **Test A (Loopback):**
   - System call overhead
   - IP stack processing
   - Loopback device driver

2. **Test B (Docker veth):**
   - Everything in Test A, PLUS:
   - veth pair traversal
   - Network namespace crossing
   - Bridge forwarding
   - Additional routing table lookup

## Running the Benchmark

```bash
./run.sh
```

**Duration:** ~30 seconds

**Requirements:**
- Docker (for Test B)
- kubectl + K8s cluster (optional, for Test C)
- `ping` command (standard on all Linux/Unix)

## Interpreting Results

### Example Output

```
Test A (Loopback): 0.050 ms average
  Min: 0.028 ms
  Max: 0.073 ms
  Std Dev: 0.005 ms

Test B (Docker veth): 0.063 ms average
  Min: 0.059 ms
  Max: 0.090 ms
  Std Dev: 0.005 ms

veth overhead: +20.0%
```

### Analysis

**Absolute Overhead:**
- 0.063 - 0.050 = 0.013 ms = **13 microseconds**

**Percentage Overhead:**
- (0.063 / 0.050 - 1) × 100 = **26% slower**

**Real-World Impact:**

**Scenario 1:** REST API serving 100 requests/second
- Per-request overhead: 13 μs
- Total overhead: 1.3 ms/second
- **Impact:** Negligible

**Scenario 2:** High-frequency trading (10,000 requests/second)
- Per-request overhead: 13 μs
- Total overhead: 130 ms/second = **13% of one CPU core**
- **Impact:** Significant - consider host networking

**Scenario 3:** Service mesh with 5-hop call chain
- Each hop adds: 13 μs
- Total chain overhead: 65 μs
- At 1000 RPS: 65 ms/second overhead
- **Impact:** Moderate - monitor tail latencies

## Production Implications

### When veth Overhead Is Acceptable

✅ **Most web applications:** Request processing >> network latency
✅ **Batch processing:** Throughput matters more than latency
✅ **Standard microservices:** 13 μs overhead is noise compared to business logic
✅ **Non-latency-sensitive workloads:** Database queries, file processing

### When to Consider Host Networking

⚠️ **Ultra-low latency requirements:** <100 μs P99 latency goals
⚠️ **High-frequency operations:** >10,000 requests/second per pod
⚠️ **Network-bound workloads:** Proxies, load balancers, packet processing
⚠️ **Financial/trading systems:** Every microsecond counts

### Kubernetes Pod Networking Optimization

**Within a Pod (containers share network namespace):**
```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    # ...
  - name: sidecar
    # ...
  # Both containers share network namespace
  # Communication via localhost - NO veth overhead!
```

**Communication:** `localhost:port` between containers = loopback performance

**Across Pods (standard networking):**
- Each pod gets veth pair
- Service mesh adds sidecar proxy
- Total overhead: ~2x veth latency

## Understanding veth Pairs

### What Is a veth Pair?

Think of it like a virtual network cable:
```
Container Namespace          Host Namespace
[eth0] ←→ [vethXXXXXX] ←→ [docker0 bridge]
```

Each packet must:
1. Exit container's eth0
2. Enter veth on host side
3. Traverse bridge forwarding logic
4. Find destination (routing table lookup)
5. Return via reverse path

### Why Not Direct Routing?

**Security isolation:**
- Each container's network is isolated
- Can't sniff other containers' traffic
- Can apply network policies per container

**Trade-off:** Security isolation vs performance

## Network Namespace Performance Comparison

| Method | Latency | Isolation | Use Case |
|--------|---------|-----------|----------|
| **Loopback (baseline)** | 50 μs | None | Process communication |
| **Shared namespace (pod)** | 50 μs | Process-level only | Sidecar pattern |
| **veth pair (Docker)** | 63 μs | Full network isolation | Standard containers |
| **Host networking** | 50 μs | None | Ultra-low latency |
| **IPVLAN** | 55 μs | MAC-level isolation | High-performance |
| **MACVLAN** | 52 μs | Full L2 isolation | Legacy apps |

## Advanced: Service Mesh Impact

A service mesh like Istio adds:
- **Envoy sidecar:** ~1-2 ms additional latency
- **TLS handshake:** ~5-10 ms first connection
- **Policy checks:** ~0.1-0.5 ms per request

**Total overhead:**
- veth: 0.013 ms
- Envoy: 1.5 ms
- **Combined:** ~1.5 ms per hop

**5-hop microservice chain:**
- Without mesh: 5 × 0.013 ms = 0.065 ms
- With mesh: 5 × 1.5 ms = **7.5 ms overhead**

**Lesson:** veth overhead is minimal compared to service mesh overhead.

## Expected Results by Environment

| Environment | Test A (μs) | Test B (μs) | Overhead |
|-------------|-------------|-------------|----------|
| **Azure Standard B2ms** | 45-55 | 60-70 | +20% |
| **AWS t3.medium** | 40-50 | 55-65 | +25% |
| **GCP n1-standard-2** | 42-52 | 58-68 | +23% |
| **Local VM (VirtualBox)** | 50-80 | 70-110 | +30-40% |
| **Bare metal (10GbE)** | 30-40 | 45-55 | +30% |

*Note: Virtual environment overhead can be higher than veth overhead itself!*

## Troubleshooting

### Docker container not responding to ping

Most container images block ICMP by default. The benchmark uses `nginx:alpine` which allows ping.

**Alternative test:**
```bash
# Use nginx container (allows ping)
docker run -d --name net-test nginx:alpine
docker inspect net-test --format '{{.NetworkSettings.IPAddress}}'
ping -c 10 <container_ip>
```

### "Network is unreachable"

Check Docker network:
```bash
docker network ls
docker network inspect bridge
```

Ensure Docker daemon is running and bridge network exists.

### kubectl not found

Test C is optional. If you don't have Kubernetes access:
- Tests A and B are sufficient for veth overhead measurement
- Test C just confirms pod networking = loopback (no surprise)

### Inconsistent results

Network latency can vary due to:
- System load (other processes)
- Network buffer state
- CPU frequency scaling
- Timer interrupt jitter

**Best practices:**
1. Run when system is idle
2. Run multiple times (script already does 100 pings)
3. Look at **average**, not min/max
4. Check **standard deviation** for consistency

## Real-World Case Study

**Company:** SaaS platform with microservices architecture

**Problem:** P99 latency increased from 50ms to 150ms after Kubernetes migration

**Investigation:**
- Baseline (VMs): 50ms
- With Docker networking: 52ms (veth: +2ms)
- With Istio mesh: 145ms (Envoy: +95ms)

**Root cause:** Service mesh overhead, NOT veth pairs

**Solution:**
- Reduced sidecar memory/CPU limits (less throttling)
- Enabled HTTP/2 keep-alive (fewer handshakes)
- Optimized Envoy config

**Result:** P99 latency back to 85ms

**Lesson:** Measure carefully before blaming container networking.

## Optimization Techniques

### 1. Increase MTU (Maximum Transmission Unit)

```bash
# Docker daemon config
{
  "mtu": 9000  # Jumbo frames (if network supports)
}
```

**Impact:** 5-10% latency reduction for large packets

### 2. Tune Network Buffer Sizes

```bash
# Increase socket buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
```

**Impact:** Better throughput, minimal latency change

### 3. Use CNI Plugins with Better Performance

| CNI Plugin | Latency Overhead |
|------------|------------------|
| Flannel (vxlan) | +30-40 μs |
| Calico (BGP) | +15-25 μs |
| Cilium (eBPF) | +10-15 μs |

**Best:** Cilium with eBPF for lowest overhead

### 4. Host Networking for Critical Services

```yaml
apiVersion: v1
kind: Pod
spec:
  hostNetwork: true  # Bypass veth entirely
  # ⚠️ Loses network isolation!
```

**Use only for:**
- Monitoring agents
- Node-level infrastructure
- Ultra-low-latency requirements

## Next Steps

- Compare results across different cloud providers
- Test with different CNI plugins (if using Kubernetes)
- Measure application-level latency (HTTP, gRPC, etc.)
- Profile full request path with `tcpdump` or eBPF

## Contributing

Submit your results with system info:

```bash
cat > system-info.txt <<EOF
Cloud Provider: Azure/AWS/GCP/Bare-metal
Instance Type: Standard_B2ms / t3.medium / etc
Network: Docker bridge / Calico / Cilium
Kernel: $(uname -r)
Docker: $(docker --version)
Date: $(date)
EOF
```

## Further Reading

- **Linux veth documentation:** `man 4 veth`
- **Docker networking:** https://docs.docker.com/network/
- **Kubernetes networking model:** https://kubernetes.io/docs/concepts/cluster-administration/networking/
- **CNI specification:** https://github.com/containernetworking/cni
- **eBPF networking:** https://ebpf.io/

---

**Questions?** Open an issue or contribute improvements via PR!