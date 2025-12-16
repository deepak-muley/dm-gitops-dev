# CAPD (Docker) Cluster Infrastructure

This directory contains configurations for creating Docker-based Kubernetes clusters using Cluster API Provider Docker (CAPD) with Kubemark hollow nodes for scale testing.

## Overview

The CAPD cluster (`dm-capd-workload-1`) is configured with:
- **1 control plane node** (Docker container)
- **3 CAPD worker nodes** (Docker containers)
- **10 Kubemark hollow nodes** (simulated, for scale testing)

## Directory Structure

```
docker-infra/
├── kustomization.yaml              # Main kustomization
├── README.md                       # This file
├── bases/                          # CAPD cluster base resources
│   ├── kustomization.yaml
│   ├── cluster.yaml                # Cluster CR
│   ├── docker-cluster.yaml         # DockerCluster infrastructure
│   ├── control-plane.yaml          # KubeadmControlPlane + templates
│   └── workers.yaml                # MachineDeployment + templates
├── capk-provider/                  # CAPK (Kubemark) provider resources
│   ├── kustomization.yaml
│   └── capk-system-namespace.yaml  # CAPK namespace
└── kubemark-hollow-machines/       # Hollow nodes for scale testing
    ├── kustomization.yaml
    └── capd-kubemark-hollow-machines.yaml
```

## Prerequisites

### 1. Install CAPD Provider (Docker)

```bash
# Using the bootstrap script
./scripts/bootstrap-capd.sh

# Or manually with clusterctl
clusterctl init --infrastructure docker

# Or apply directly
kubectl apply -f https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.8.5/infrastructure-components-development.yaml
```

### 2. Install CAPK Provider (Kubemark) for hollow nodes

```bash
# Using the bootstrap script
./scripts/bootstrap-capk.sh

# Or apply directly
kubectl apply -f https://github.com/kubernetes-sigs/cluster-api-provider-kubemark/releases/download/v0.10.0/infrastructure-components.yaml
```

### 3. Verify Providers

```bash
kubectl get providers -A | grep -E "(docker|kubemark)"
```

## Cluster Resources

### Cluster CR (`bases/cluster.yaml`)

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: dm-capd-workload-1
  namespace: dm-dev-workspace
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
```

### CAPD Workers (Real Docker Containers)

3 real CAPD worker nodes that:
- Run actual workloads
- Use Docker containers as "machines"
- Provide real Kubernetes functionality

### Kubemark Hollow Nodes (Simulated)

10 hollow nodes that:
- Simulate real node behavior
- Consume minimal resources (~50Mi each)
- Can scale to 100 nodes via autoscaler
- Are useful for scale testing

## Deployment

### Build and Preview

```bash
# Preview the generated manifests
kustomize build .

# Apply to cluster
kustomize build . | kubectl apply -f -
```

### Monitor Cluster Creation

```bash
# Watch cluster status
kubectl get cluster dm-capd-workload-1 -n dm-dev-workspace -w

# Check all machines
kubectl get machines -n dm-dev-workspace

# Expected machines:
# - 1 control plane (dm-capd-workload-1-control-plane-xxxxx)
# - 3 CAPD workers (dm-capd-workload-1-md-0-xxxxx)
# - 10 hollow nodes (dm-capd-workload-1-kubemark-md-0-xxxxx)
```

### Get Kubeconfig

```bash
clusterctl get kubeconfig dm-capd-workload-1 -n dm-dev-workspace > dm-capd-workload-1.kubeconfig

# Use the kubeconfig
KUBECONFIG=dm-capd-workload-1.kubeconfig kubectl get nodes
```

## Scaling

### Scale CAPD Workers

```bash
kubectl scale machinedeployment dm-capd-workload-1-md-0 -n dm-dev-workspace --replicas=5
```

### Scale Hollow Nodes

```bash
kubectl scale machinedeployment dm-capd-workload-1-kubemark-md-0 -n dm-dev-workspace --replicas=50
```

## Use Cases

1. **Local Development**: Test cluster operations locally using Docker
2. **CI/CD Testing**: Spin up test clusters in CI pipelines
3. **Scale Testing**: Use hollow nodes to simulate large clusters
4. **Controller Testing**: Validate custom controllers at scale
5. **Cost-Effective Testing**: Run "large" clusters without cloud costs

## Important Notes

⚠️ **Docker Requirement**: CAPD requires Docker to be running on the management cluster nodes. If your management cluster uses containerd only, CAPD won't work.

⚠️ **Not for Production**: CAPD clusters are for development/testing only.

⚠️ **Resource Consumption**: Each hollow node consumes ~50Mi memory. At scale (1000+ nodes), monitor management cluster resources.

## Troubleshooting

### CAPD Cluster Not Creating

```bash
kubectl describe cluster dm-capd-workload-1 -n dm-dev-workspace
kubectl logs -n capd-system -l control-plane=controller-manager
```

### Hollow Nodes Not Joining

```bash
kubectl describe machinedeployment dm-capd-workload-1-kubemark-md-0 -n dm-dev-workspace
kubectl logs -n capk-system -l control-plane=controller-manager
```

### Docker Not Available

If CAPD fails because Docker isn't available on management cluster nodes:
1. Use a local kind cluster as the management cluster
2. Or install Docker on management cluster nodes

## References

- [Cluster API Provider Docker](https://github.com/kubernetes-sigs/cluster-api/tree/main/test/infrastructure/docker)
- [Cluster API Provider Kubemark](https://github.com/kubernetes-sigs/cluster-api-provider-kubemark)
- [Cluster API Documentation](https://cluster-api.sigs.k8s.io/)
