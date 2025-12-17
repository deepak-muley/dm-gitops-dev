# NKP GitOps - Multi-Region Multi-AZ

GitOps repository for managing NKP (Nutanix Kubernetes Platform) resources across multiple regions and availability zones.

## Quick Start

### Bootstrap Management Cluster

Each region and availability zone has its own bootstrap file. Apply the one matching your management cluster:

```bash
# USA Region - AZ1 (Currently Active)
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/management-cluster/bootstrap.yaml

# USA Region - AZ2
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az2/management-cluster/bootstrap.yaml

# USA Region - AZ3
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az3/management-cluster/bootstrap.yaml

# India Region - AZ1
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-india/az1/management-cluster/bootstrap.yaml
```

### Bootstrap Workload Clusters

After workload clusters are created by CAPI, bootstrap GitOps inside them.
NKP workload clusters already have Flux controllers in `kommander-flux` namespace
watching all namespaces, so no need to install Flux separately:

```bash
# dm-nkp-workload-1
export KUBECONFIG=~/.kube/dm-nkp-workload-1.kubeconfig
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/workload-clusters/dm-nkp-workload-1/bootstrap.yaml

# dm-nkp-workload-2
export KUBECONFIG=~/.kube/dm-nkp-workload-2.kubeconfig
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/workload-clusters/dm-nkp-workload-2/bootstrap.yaml
```

## Regions & Availability Zones

| Region | Location | AZ | Management Cluster Bootstrap | Status |
|--------|----------|-----|------------------------------|--------|
| region-usa | USA | az1 | `region-usa/az1/management-cluster/bootstrap.yaml` | ✅ Active |
| region-usa | USA | az2 | `region-usa/az2/management-cluster/bootstrap.yaml` | 🔜 Planned |
| region-usa | USA | az3 | `region-usa/az3/management-cluster/bootstrap.yaml` | 🔜 Planned |
| region-india | India | az1 | `region-india/az1/management-cluster/bootstrap.yaml` | 🔜 Planned |
| region-india | India | az2 | `region-india/az2/management-cluster/bootstrap.yaml` | 🔜 Planned |
| region-india | India | az3 | `region-india/az3/management-cluster/bootstrap.yaml` | 🔜 Planned |

## What This Manages

### Management Cluster Resources
- **Namespaces** - GitOps namespace for Flux Kustomizations
- **Global Resources** - VirtualGroups, Sealed Secrets Controller
- **Workspaces** - Workspace definitions and configurations
- **CAPI Clusters** - Workload cluster definitions with sealed secrets
- **RBAC** - Role bindings for workspace access
- **Network Policies** - Cross-workspace traffic controls
- **Resource Quotas** - Workspace resource limits
- **Projects** - Project definitions within workspaces
- **Applications** - Platform and project-level applications (deployed via Kommander)

### Workload Cluster Resources
- **Infrastructure** - Core infrastructure components (cert-manager, ingress, etc.)
- **Apps** - Applications deployed directly inside workload clusters

## Repository Structure

```
.
├── README.md
│
├── region-usa/                                     # 🇺🇸 USA Region
│   └── az1/                                        # Availability Zone 1 ✅ Active
│       ├── management-cluster/                     # Resources for NKP management cluster
│       │   ├── bootstrap.yaml                      # ← Bootstrap for management cluster
│       │   ├── kustomization.yaml
│       │   ├── namespaces/
│       │   │   └── dm-nkp-gitops-namespace.yaml
│       │   ├── global/
│       │   │   ├── flux-ks.yaml
│       │   │   ├── virtualgroups.yaml
│       │   │   └── sealed-secrets-controller/
│       │   └── workspaces/
│       │       ├── flux-ks.yaml
│       │       └── dm-dev-workspace/
│       │           ├── dm-dev-workspace.yaml
│       │           ├── application-catalogs/       # Custom app catalogs
│       │           ├── applications/               # Workspace applications
│       │           │   ├── platform-applications/
│       │           │   └── nkp-nutanix-products-catalog-applications/
│       │           ├── clusters/                   # CAPI workload cluster definitions
│       │           │   ├── flux-ks.yaml           # Unified Flux Kustomization for all clusters
│       │           │   ├── kustomization.yaml     # Includes nutanix-infra and docker-infra
│       │           │   ├── nutanix-infra/         # Nutanix CAPI clusters ✅ Active
│       │           │   │   ├── bases/             # Base cluster definitions
│       │           │   │   ├── overlays/          # Version-specific JSON patches
│       │           │   │   └── sealed-secrets/    # Encrypted credentials
│       │           │   ├── docker-infra/          # CAPD clusters + Kubemark ✅ Active
│       │           │   │   ├── bases/             # CAPD cluster (control-plane, workers)
│       │           │   │   ├── capk-provider/     # Kubemark provider namespace
│       │           │   │   └── kubemark-hollow-machines/  # Hollow nodes for scale testing
│       │           │   ├── eks-infra/             # AWS EKS clusters (placeholder)
│       │           │   ├── aks-infra/             # Azure AKS clusters (placeholder)
│       │           │   ├── gke-infra/             # GCP GKE clusters (placeholder)
│       │           │   ├── eks-a-infra/           # AWS EKS Anywhere clusters (placeholder)
│       │           │   └── openshift-infra/       # OpenShift clusters (placeholder)
│       │           ├── projects/
│       │           │   └── dm-dev-project/
│       │           ├── rbac/
│       │           └── resourcequotas/
│       │
│       └── workload-clusters/                      # Resources deployed INSIDE workload clusters
│           ├── _base/                              # Shared base configurations
│           │   └── infrastructure/
│           ├── dm-nkp-workload-1/
│           │   ├── bootstrap.yaml                  # ← Single command bootstrap
│           │   ├── infrastructure/                 # Infra components
│           │   └── apps/                           # Applications
│           └── dm-nkp-workload-2/
│               ├── bootstrap.yaml                  # ← Single command bootstrap
│               ├── infrastructure/
│               └── apps/
│
└── region-india/                                   # 🇮🇳 India Region
    └── az1/, az2/, az3/                            # 🔜 Planned
```

## Bootstrap Architecture

### Management Cluster Bootstrap

Each management cluster bootstrap file creates two Flux resources:

```yaml
# 1. GitRepository - Points to this repo
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-<region>-<az>
  namespace: kommander

# 2. Kustomization - Points to management-cluster path
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: clusterops-<region>-<az>
  namespace: kommander
spec:
  path: ./region-<name>/az<n>/management-cluster
```

### Workload Cluster Bootstrap

Each workload cluster gets its own Flux installation in `dm-nkp-gitops-workload` namespace:

```yaml
# GitRepository - Points to this repo
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: dm-nkp-gitops-infra
  namespace: dm-nkp-gitops-workload

# Kustomizations - Point to cluster-specific paths
# - infrastructure: ./region-usa/az1/workload-clusters/<cluster>/infrastructure
# - apps: ./region-usa/az1/workload-clusters/<cluster>/apps
```

## Flux Kustomization Dependencies (Management Cluster)

```
Level 0 (No dependencies):
  ├── clusterops-global
  └── clusterops-workspaces

Level 1 (Depends on workspaces):
  ├── clusterops-workspace-applications
  ├── clusterops-workspace-rbac
  ├── clusterops-workspace-networkpolicies
  ├── clusterops-workspace-resourcequotas
  ├── clusterops-clusters
  ├── clusterops-sealed-secrets
  └── clusterops-project-definitions

Level 2 (Depends on project-definitions):
  └── clusterops-project-applications
```

## Adding a New Region

1. Create region directory structure:
   ```bash
   mkdir -p region-<name>/az1/{management-cluster,workload-clusters}
   ```

2. For each AZ, create management-cluster structure:
   - `bootstrap.yaml` - Copy from existing and update names/paths
   - `kustomization.yaml` - Start with empty resources
   - Copy subdirectories from active AZ when ready

3. Update this README with new region status

## Adding a New AZ in Existing Region

1. Copy structure from an active AZ:
   ```bash
   cp -r region-usa/az1/* region-usa/az2/
   ```

2. Update all configurations:
   - Namespace names
   - Workspace names
   - Cluster names and IPs
   - Sealed secrets (regenerate for new cluster)
   - Prism Central endpoints
   - All path references in flux-ks.yaml files

## Adding a New Workspace

1. Create workspace directory:
   ```bash
   mkdir -p region-<name>/az<n>/management-cluster/workspaces/<workspace-name>
   ```

2. Add required files:
   - `<workspace-name>.yaml` - Workspace definition
   - `applications/flux-ks.yaml`
   - `clusters/flux-ks.yaml`
   - `rbac/flux-ks.yaml`
   - etc.

3. Update `management-cluster/workspaces/kustomization.yaml`

## Adding a New CAPI Cluster

1. Choose the appropriate infra folder based on provider:
   - Nutanix: `.../clusters/nutanix-infra/`
   - AWS EKS: `.../clusters/eks-infra/`
   - Azure AKS: `.../clusters/aks-infra/`
   - GCP GKE: `.../clusters/gke-infra/`
   - EKS Anywhere: `.../clusters/eks-a-infra/`
   - OpenShift: `.../clusters/openshift-infra/`
   - Docker/Kind: `.../clusters/docker-infra/`
2. Add cluster YAML under `.../clusters/<provider>-infra/bases/`
3. Add overlay patch under `.../clusters/<provider>-infra/overlays/<version>/`
4. Add sealed secrets under `.../clusters/<provider>-infra/sealed-secrets/`
5. Update the respective `kustomization.yaml` files
6. Create workload cluster GitOps folder under `workload-clusters/<cluster-name>/`

## Kustomize Patching Strategy

### JSON Patches (RFC 6902) for Cluster Overlays

For version-specific cluster overlays, we use **JSON patches** instead of strategic merge patches.
This prevents base fields (like `imageRegistries`, `dns`, `users`) from being overwritten.

```yaml
# overlays/2.17.0/kustomization.yaml
patches:
  - target:
      kind: Cluster
      name: dm-nkp-workload-1
    patch: |-
      - op: replace
        path: /spec/topology/class
        value: nkp-nutanix-v2.17.0-rc.4
      - op: add
        path: /spec/topology/workers/machineDeployments/0/replicas
        value: 3
      - op: remove
        path: /spec/topology/workers/machineDeployments/0/metadata/annotations/cluster.x-k8s.io~1cluster-api-autoscaler-node-group-max-size
```

**Why JSON patches?**
- Strategic merge patches replace entire nested objects
- JSON patches surgically modify specific fields
- Base fields like `imageRegistries` remain intact

## CAPD Clusters (Docker-based)

### Overview

The `docker-infra` directory contains CAPD (Cluster API Docker) cluster configurations:
- **dm-capd-workload-1**: 1 control plane + 3 CAPD workers + 10 Kubemark hollow nodes

### Prerequisites

CAPD requires Docker on management cluster nodes. For NKP clusters using containerd:
1. Use a local kind cluster as management cluster, OR
2. Use the configuration as a template for Docker-enabled environments

### Bootstrap Scripts

```bash
# Install CAPD provider
./scripts/bootstrap-capd.sh mgmt

# Install CAPK provider (for hollow nodes)
./scripts/bootstrap-capk.sh mgmt

# Check status
./scripts/bootstrap-capd.sh --status mgmt
./scripts/bootstrap-capk.sh --status mgmt
```

### Generate CAPD Cluster YAML

```bash
clusterctl generate cluster test \
  --infrastructure docker \
  --kubernetes-version v1.31.0 \
  --control-plane-machine-count 1 \
  --worker-machine-count 3 \
  > test-capd-cluster.yaml
```

## Gatekeeper Security Policies

### Policy Categories

| Category | Purpose |
|----------|---------|
| `image-security` | Container registry restrictions, image digest requirements |
| `network-security` | NodePort/LoadBalancer restrictions, port validation |
| `pod-security` | Privileged containers, host namespaces, capabilities |
| `rbac` | ServiceAccount tokens, wildcard RBAC, cluster-admin |
| `resource-management` | Resource limits, probes, labels |

### Excluded Namespaces

System namespaces are excluded from policies:
- `kube-system`, `kube-public`, `kube-node-lease`
- CAPI namespaces: `capi-system`, `capa-system`, `capz-system`, `capg-system`, `capv-system`, `caaph-system`
- Provider namespaces: `capk-system`, `capd-system`

### Namespace Targeting Options

```yaml
# Option 1: Exclude specific namespaces (current - secure by default)
excludedNamespaces:
  - kube-system
  - capd-system

# Option 2: Include only specific namespaces (allowlist)
namespaces:
  - production
  - staging

# Option 3: Label-based (best for large deployments)
namespaceSelector:
  matchLabels:
    policy.gatekeeper.sh/enforce: "true"
```

## Currently Active Configuration

### USA Region - AZ1

| Resource | Name | Details |
|----------|------|---------|
| Management Cluster | dm-nkp-mgmt-1 | NKP v2.17.0-rc.4 |
| Workspace | dm-dev-workspace | Development workspace |
| Project | dm-dev-project | Development project |

### Workload Clusters

| Cluster | Provider | Control Plane | Workers | Status |
|---------|----------|---------------|---------|--------|
| dm-nkp-workload-1 | Nutanix | 1 | 3 | ✅ Provisioned |
| dm-nkp-workload-2 | Nutanix | 1 | 3 | ✅ Provisioned |
| dm-capd-workload-1 | Docker (CAPD) | 1 | 3 + 10 hollow | ⚠️ Requires Docker |

### Platform Applications (Management Cluster)

- Sealed Secrets Controller
- Kube Prometheus Stack
- Rook Ceph / Rook Ceph Cluster
- Grafana Loki (project-level)
- Grafana Logging (project-level)

### NKP Catalog Applications

- NDK (Nutanix Data Services for Kubernetes)
- Nutanix AI

## Troubleshooting

### Check Flux Status (Management Cluster)

```bash
# Check GitRepository
kubectl get gitrepository -n kommander

# Check Kustomizations
kubectl get kustomization -n kommander
kubectl get kustomization -n dm-nkp-gitops

# Check for errors
flux get all -A
```

### Check Flux Status (Workload Cluster)

```bash
export KUBECONFIG=~/.kube/dm-nkp-workload-1.kubeconfig

# Check Flux resources
kubectl get gitrepository,kustomization -n dm-nkp-gitops-workload
```

### Force Reconciliation

```bash
# Management cluster
flux reconcile source git gitops-usa-az1 -n kommander
flux reconcile kustomization clusterops-usa-az1 -n kommander

# Workload cluster
flux reconcile source git dm-nkp-gitops-infra -n dm-nkp-gitops-workload
flux reconcile kustomization infrastructure -n dm-nkp-gitops-workload
```

### View Flux Logs

```bash
kubectl logs -n kommander-flux deploy/source-controller
kubectl logs -n kommander-flux deploy/kustomize-controller
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-capd.sh` | Install CAPD provider on management cluster |
| `scripts/bootstrap-capk.sh` | Install CAPK (Kubemark) provider for hollow nodes |
| `scripts/check-violations.sh` | Check Gatekeeper policy violations |
| `scripts/migrate-to-new-structure.sh` | Migration helper for repo restructuring |

### Usage Examples

```bash
# Install CAPD provider
./scripts/bootstrap-capd.sh mgmt
./scripts/bootstrap-capd.sh --direct mgmt  # Direct download (bypasses clusterctl)
./scripts/bootstrap-capd.sh --status mgmt  # Check status

# Install CAPK provider
./scripts/bootstrap-capk.sh mgmt
./scripts/bootstrap-capk.sh --patch-resources mgmt  # Fix OOMKilled issues
./scripts/bootstrap-capk.sh --generate-manifests    # Generate for GitOps

# Check policy violations
./scripts/check-violations.sh
```
