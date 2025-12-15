# NKP Platform Firewall Requirements

This document lists all ports that need to be opened in your firewall for NKP to function properly.

## 📚 Official Nutanix Documentation

> **For the authoritative and complete list of ports, always refer to the official Nutanix documentation:**
>
> | Environment | Documentation Link |
> |-------------|-------------------|
> | **Connected (Internet Access)** | [NKP Ports and Protocols](https://portal.nutanix.com/page/documents/ports-and-protocols?productType=Nutanix%20Kubernetes%20Platform) |
> | **Airgapped (Disconnected)** | [NKP Airgap Ports and Protocols](https://portal.nutanix.com/page/documents/ports-and-protocols?productType=Nutanix%20Kubernetes%20Platform%20%28Airgap%29) |

---

> **⚠️ AIRGAPPED ENVIRONMENTS**: If you are running an airgapped/disconnected environment,
> you do NOT need to open outbound internet ports. Only internal cluster communication
> and management access ports apply. See the [official airgapped documentation](https://portal.nutanix.com/page/documents/ports-and-protocols?productType=Nutanix%20Kubernetes%20Platform%20%28Airgap%29) for details.

---

## Quick Reference

### Inbound to Management Cluster (From Users/Admins)

| Port | Protocol | Service | Required |
|------|----------|---------|----------|
| 443 | TCP | Traefik Ingress (HTTPS) | ✅ Yes |
| 6443 | TCP | Kubernetes API Server | ✅ Yes |
| 22 | TCP | SSH (node access) | Optional |

### Inbound to Worker Nodes (From Control Plane)

| Port | Protocol | Service | Required |
|------|----------|---------|----------|
| 10250 | TCP | Kubelet API | ✅ Yes |
| 10255 | TCP | Kubelet Read-only | Optional |
| 30000-32767 | TCP | NodePort Services | If using NodePort |

### Inter-Node Communication (Between All Nodes)

| Port | Protocol | Service | Required |
|------|----------|---------|----------|
| 2379-2380 | TCP | etcd client/peer | ✅ Yes (control plane) |
| 6443 | TCP | Kubernetes API | ✅ Yes |
| 10250 | TCP | Kubelet | ✅ Yes |
| 6081 | UDP | Geneve (Cilium) | ✅ Yes (NKP default) |
| 8472 | UDP | VXLAN (Cilium) | If VXLAN mode |
| 4240 | TCP | Cilium health | ✅ Yes |
| 7946 | TCP/UDP | MetalLB memberlist | ✅ Yes (L2 mode) |
| 4244 | TCP | Hubble relay | Optional |

---

## Detailed Port Requirements

### Control Plane Ports

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 6443 | TCP | kube-apiserver | Inbound | Kubernetes API server |
| 2379 | TCP | etcd | Internal | etcd client requests |
| 2380 | TCP | etcd | Internal | etcd peer communication |
| 10257 | TCP | kube-controller-manager | Internal | Health/metrics |
| 10259 | TCP | kube-scheduler | Internal | Health/metrics |

### Worker Node Ports

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 10250 | TCP | kubelet | Inbound | Kubelet API (exec, logs, port-forward) |
| 10255 | TCP | kubelet | Inbound | Read-only kubelet API (optional) |
| 30000-32767 | TCP/UDP | NodePort | Inbound | NodePort service range |

### CNI (Cilium) Ports

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 6081 | UDP | Geneve | Inter-node | Pod-to-pod overlay networking (NKP default) |
| 8472 | UDP | VXLAN | Inter-node | Alternative overlay (if VXLAN mode) |
| 4240 | TCP | Cilium | Inter-node | Cilium health checks |
| 4244 | TCP | Hubble | Internal | Hubble relay (observability) |
| 4245 | TCP | Hubble | Internal | Hubble peer |
| 9962 | TCP | Cilium | Internal | Cilium agent metrics |
| 9963 | TCP | Cilium | Internal | Cilium operator metrics |
| 9964 | TCP | Envoy | Internal | Envoy metrics |

> **Note:** NKP uses **Geneve** tunnel protocol by default (port 6081), not VXLAN (port 8472).

### MetalLB (Load Balancer)

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 7472 | TCP | MetalLB | Internal | Metrics |
| 7473 | TCP | MetalLB | Internal | Metrics |
| 7946 | TCP/UDP | MetalLB | Inter-node | Memberlist (L2 mode) |

### Nutanix CSI/CCM

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 9807 | TCP | Nutanix CSI | Internal | CSI driver metrics |
| 9808 | TCP | Nutanix CSI | Internal | CSI driver metrics |

### NKP Platform Services

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 443 | TCP | Traefik | Inbound | HTTPS ingress (Kommander UI, Grafana, etc.) |
| 80 | TCP | Traefik | Inbound | HTTP (redirects to HTTPS) |
| 5000 | TCP | Registry | Inbound | Container registry (if enabled) |
| 8085 | TCP | Ceph Dashboard | Inbound | Rook-Ceph dashboard |

### Monitoring Stack

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 9090 | TCP | Prometheus | Internal | Prometheus server |
| 9093 | TCP | Alertmanager | Internal | Alertmanager |
| 3000 | TCP | Grafana | Internal | Grafana dashboards |
| 9100 | TCP | Node Exporter | Internal | Node metrics |
| 8888 | TCP | kube-rbac-proxy | Internal | RBAC proxy for metrics |

### Cluster API

| Port | Protocol | Component | Direction | Description |
|------|----------|-----------|-----------|-------------|
| 9440 | TCP | CAPI webhooks | Internal | Cluster API webhooks |
| 9443 | TCP | CAPI webhooks | Internal | Cluster API admission |

---

## Firewall Rules by Environment

### Connected Environment (Internet Access)

**Outbound Rules (to Internet):**

| Port | Protocol | Destination | Purpose |
|------|----------|-------------|---------|
| 443 | TCP | *.docker.io | Docker Hub images |
| 443 | TCP | *.gcr.io | Google Container Registry |
| 443 | TCP | ghcr.io | GitHub Container Registry |
| 443 | TCP | quay.io | Quay.io images |
| 443 | TCP | mcr.microsoft.com | Microsoft Container Registry |
| 443 | TCP | registry.k8s.io | Kubernetes images |
| 443 | TCP | *.nutanix.com | Nutanix services |
| 443 | TCP | github.com | Git operations |
| 443 | TCP | *.githubusercontent.com | GitHub raw content |

### Airgapped Environment (No Internet)

> **For airgapped environments, you do NOT need any outbound internet rules.**
>
> Instead, ensure:
> 1. All container images are mirrored to your internal registry
> 2. Internal registry is accessible from all nodes
> 3. Update `allowed-repos` Gatekeeper policy to only allow your internal registry

**Internal Registry Access:**

| Port | Protocol | Destination | Purpose |
|------|----------|-------------|---------|
| 443 | TCP | your-registry.internal | Internal container registry |
| 5000 | TCP | your-registry.internal | Internal registry (if using port 5000) |

---

## NKP Services Exposed via LoadBalancer

Current LoadBalancer services in your cluster:

| Service | Namespace | Ports | NodePorts |
|---------|-----------|-------|-----------|
| kommander-traefik | kommander | 80, 443, 5000, 8085 | 31649, 31224, 30531, 30328 |

---

## Verification Commands

```bash
# List all exposed services
kubectl get svc -A -o wide | grep -E "LoadBalancer|NodePort"

# Check what ports are listening on nodes
ss -tlnp | grep -E "kube|etcd|cilium"

# Verify connectivity to API server
curl -k https://<control-plane-ip>:6443/healthz

# Test Traefik ingress
curl -k https://<traefik-lb-ip>/
```

---

## How to Detect Missing Firewall Rules

### 1. Gatekeeper Policy (Preventive)

The `validate-external-ports` policy warns when NEW services expose ports not in the approved list:

```bash
# Check for violations
kubectl get constraints validate-external-ports -o yaml | grep -A 20 violations
```

**Limitation:** Gatekeeper validates Kubernetes resources, not actual network connectivity.

### 2. Connectivity Test Job (Active Testing)

Run periodic connectivity tests to verify firewall rules are working:

```bash
# Run one-time test
kubectl apply -f network-tests/connectivity-test-job.yaml
kubectl logs job/network-connectivity-test

# Or use the CronJob for hourly testing
kubectl apply -f network-tests/connectivity-test-job.yaml
```

See: `network-tests/connectivity-test-job.yaml`

### 3. Prometheus Alerts (Reactive Monitoring)

Deploy alerts that detect firewall-related failures:

```bash
kubectl apply -f network-tests/prometheus-alerts.yaml
```

**Alerts included:**
| Alert | Indicates |
|-------|-----------|
| `ImagePullBackOff` | Can't reach container registry |
| `KubeAPIServerDown` | Port 6443 blocked |
| `EtcdUnreachable` | Ports 2379/2380 blocked |
| `KubeletUnreachable` | Port 10250 blocked |
| `ConnectivityTestFailed` | General connectivity issue |

See: `network-tests/prometheus-alerts.yaml`

### 4. Common Symptoms of Missing Firewall Rules

| Symptom | Likely Cause | Ports to Check |
|---------|--------------|----------------|
| Pods stuck in `ImagePullBackOff` | Registry blocked | 443 outbound to registries |
| Pods stuck in `Pending` | API server unreachable | 6443 |
| `kubectl exec` fails | Kubelet unreachable | 10250 |
| Pod-to-pod traffic fails | CNI ports blocked | 6081 (Geneve) or 8472 (VXLAN) |
| Nodes `NotReady` | Multiple ports | 6443, 10250, 2379-2380 |
| Services unreachable | LoadBalancer/NodePort | Check specific service ports |

### 5. Quick Diagnostic Commands

```bash
# Check for ImagePull issues
kubectl get pods -A | grep -E "ImagePull|ErrImage"

# Check node connectivity
kubectl get nodes -o wide

# Test API server from a pod
kubectl run test --rm -it --image=busybox -- nc -zv kubernetes.default.svc 443

# Check service endpoints
kubectl get endpoints -A | grep "<none>"

# View recent events for network issues
kubectl get events -A --field-selector reason=FailedMount,reason=FailedScheduling,reason=NetworkNotReady
```

---

## References

### Official Nutanix Documentation (Primary Source)
- [NKP Ports and Protocols (Connected)](https://portal.nutanix.com/page/documents/ports-and-protocols?productType=Nutanix%20Kubernetes%20Platform)
- [NKP Ports and Protocols (Airgapped)](https://portal.nutanix.com/page/documents/ports-and-protocols?productType=Nutanix%20Kubernetes%20Platform%20%28Airgap%29)

### Kubernetes & CNI Documentation
- [Kubernetes Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)
- [Cilium System Requirements](https://docs.cilium.io/en/stable/operations/system_requirements/)

