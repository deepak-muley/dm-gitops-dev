# Kubemark Cluster Infrastructure

This directory contains templates for creating Kubemark clusters using Cluster API Provider Kubemark (CAPK).

## What is Kubemark?

Kubemark is a performance testing tool for Kubernetes that allows you to simulate large clusters without actual hardware. It creates "hollow" nodes that mimic real node behavior but run as pods within the management cluster.

**Use Cases:**
- Scale testing (simulate 100s-1000s of nodes)
- Performance benchmarking
- Testing cluster autoscaler behavior
- Validating controllers at scale
- Cost-effective load testing

## Prerequisites

### Option 1: Install CAPK via Bootstrap Script (Recommended)

Use the provided bootstrap script for easy installation:

```bash
# Install CAPK on management cluster
./scripts/bootstrap-capk.sh mgmt

# Or use --direct to bypass clusterctl (if you have TLS issues)
./scripts/bootstrap-capk.sh --direct mgmt

# Check CAPK status
./scripts/bootstrap-capk.sh --status mgmt
```

### Option 2: Manual Installation

```bash
# Get kubeconfig for management cluster
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# Download and apply CAPK v0.10.0 directly
curl -sL https://github.com/kubernetes-sigs/cluster-api-provider-kubemark/releases/download/v0.10.0/infrastructure-components.yaml | kubectl apply -f -

# Verify installation
kubectl get pods -n capk-system
kubectl get crds | grep kubemark
```

### Option 3: GitOps Installation

Download CAPK components and add them to GitOps:

```bash
# Download CAPK manifests for GitOps
./scripts/bootstrap-capk.sh --generate-manifests

# This creates: capk-provider/capk-components.yaml
# Then uncomment 'capk-components.yaml' in capk-provider/kustomization.yaml
# Commit and push to git - Flux will apply the manifests
```

## Directory Structure

```
kubemark-infra/
├── capk-provider/          # CAPK provider installation
│   ├── namespace.yaml      # capk-system namespace
│   └── kustomization.yaml
├── bases/                  # Kubemark cluster templates
│   ├── kubemark-cluster.yaml
│   └── kustomization.yaml
├── flux-ks.yaml           # Flux Kustomizations
├── kustomization.yaml
└── README.md
```

## Cluster Configuration

The default cluster template (`bases/kubemark-cluster.yaml`) creates:

- **1 control plane node** (hollow)
- **10 worker nodes** (hollow, scalable to 100)
- **CIDR ranges:**
  - Pods: 192.168.0.0/16
  - Services: 10.96.0.0/12

### Customizing the Cluster

1. **Change node count:**
   ```yaml
   spec:
     replicas: 50  # Number of hollow nodes
   ```

2. **Enable autoscaling:**
   ```yaml
   annotations:
     cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size: "10"
     cluster.x-k8s.io/cluster-api-autoscaler-node-group-max-size: "500"
   ```

3. **Change Kubernetes version:**
   ```yaml
   spec:
     version: v1.30.0
   ```

## Deployment

### Step 1: Ensure CAPK Provider is Installed

```bash
# Verify CAPK is running
kubectl get pods -n capk-system

# Expected output:
# NAME                                           READY   STATUS
# capk-controller-manager-xxxxx                  1/1     Running
```

### Step 2: Apply Cluster via GitOps

The cluster will be created automatically by Flux once:
1. CAPK provider is installed
2. The kubemark-infra is added to the clusters kustomization

### Step 3: Verify Cluster Creation

```bash
# Watch cluster provisioning
kubectl get clusters -n dm-dev-workspace -w

# Check hollow nodes
kubectl get machines -n dm-dev-workspace

# Get kubeconfig for kubemark cluster
clusterctl get kubeconfig dm-kubemark-cluster-1 -n dm-dev-workspace > dm-kubemark-cluster-1.kubeconfig
```

## Important Notes

⚠️ **Resource Consumption:** Each hollow node consumes minimal resources (~50Mi memory), but at scale (1000+ nodes), this adds up. Monitor management cluster resources.

⚠️ **Not for Production:** Kubemark clusters are for testing only - they don't run actual workloads.

⚠️ **API Server Load:** Large Kubemark clusters generate significant API server load on the management cluster.

## Scaling for Performance Testing

For large-scale testing (500+ nodes):

1. Ensure management cluster has sufficient resources
2. Increase API server resource limits
3. Consider etcd performance tuning
4. Monitor management cluster metrics

```yaml
# Example: Scale to 500 hollow nodes
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
spec:
  replicas: 500
```

## Troubleshooting

### CAPK Controller Not Starting
```bash
kubectl logs -n capk-system -l control-plane=controller-manager
```

### Cluster Stuck in Provisioning
```bash
kubectl describe cluster dm-kubemark-cluster-1 -n dm-dev-workspace
kubectl get events -n dm-dev-workspace --sort-by='.lastTimestamp'
```

### Hollow Nodes Not Ready
```bash
kubectl get machines -n dm-dev-workspace
kubectl describe machine <machine-name> -n dm-dev-workspace
```

## References

- [Cluster API Provider Kubemark](https://github.com/kubernetes-sigs/cluster-api-provider-kubemark)
- [Kubemark Documentation](https://github.com/kubernetes/kubernetes/tree/master/test/kubemark)
- [Cluster API Book](https://cluster-api.sigs.k8s.io/)

