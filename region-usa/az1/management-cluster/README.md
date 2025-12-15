# Management Cluster GitOps - USA Region AZ1

This directory contains GitOps configurations for the **NKP management cluster** in USA Region AZ1.

## Structure

```
management-cluster/
├── bootstrap.yaml              # Bootstrap manifest - apply this first
├── kustomization.yaml          # Main kustomization referencing all Flux resources
├── global/                     # Cluster-wide resources
│   ├── sealed-secrets-controller/
│   └── virtualgroups.yaml
├── namespaces/                 # Namespace definitions
└── workspaces/
    └── dm-dev-workspace/
        ├── application-catalogs/   # Custom app catalogs
        ├── applications/           # Workspace-level applications
        ├── clusters/               # CAPI workload cluster definitions
        │   ├── nutanix-infra/      # Nutanix CAPI clusters
        │   │   ├── bases/
        │   │   ├── overlays/
        │   │   └── sealed-secrets/
        │   ├── eks-infra/          # AWS EKS clusters (placeholder)
        │   ├── aks-infra/          # Azure AKS clusters (placeholder)
        │   ├── gke-infra/          # GCP GKE clusters (placeholder)
        │   ├── eks-a-infra/        # AWS EKS Anywhere (placeholder)
        │   ├── openshift-infra/    # OpenShift clusters (placeholder)
        │   ├── kubemark-infra/     # Kubemark clusters (placeholder)
        │   └── docker-infra/       # Docker/Kind clusters (placeholder)
        ├── projects/
        ├── rbac/
        └── resourcequotas/
```

## Bootstrap

### Prerequisites

1. NKP management cluster is running
2. `kubectl` configured to access the management cluster
3. Kommander is installed (provides the `kommander` namespace)

### Apply Bootstrap

```bash
# From the management cluster
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/management-cluster/bootstrap.yaml

# Or locally
kubectl apply -f region-usa/az1/management-cluster/bootstrap.yaml
```

### What Gets Created

The bootstrap creates:
1. **GitRepository** `gitops-usa-az1` in `kommander` namespace - points to this repo
2. **Kustomization** `clusterops-usa-az1` in `kommander` namespace - reconciles this directory

This triggers a cascade of Flux Kustomizations that deploy:
- Global resources (sealed-secrets controller, etc.)
- Workspaces (NKP Workspace CRs)
- Workspace applications
- CAPI workload cluster definitions
- Projects and project applications

## Verify Deployment

```bash
# Check Flux Kustomizations
kubectl get kustomizations -n dm-nkp-gitops

# Check workload clusters
kubectl get clusters -n dm-dev-workspace

# Check workspace
kubectl get workspaces
```

## Workload Clusters

This directory manages workload cluster **definitions** (CAPI Cluster CRs).

For resources deployed **inside** workload clusters, see:
[../workload-clusters/README.md](../workload-clusters/README.md)

