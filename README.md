# NKP GitOps - Multi-Region Multi-AZ

GitOps repository for managing NKP (Nutanix Kubernetes Platform) resources across multiple regions and availability zones.

## Quick Start

### Bootstrap a Region/AZ

Each region and availability zone has its own bootstrap file. Apply the one matching your management cluster:

```bash
# USA Region - AZ1 (Currently Active)
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/bootstrap.yaml

# USA Region - AZ2
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az2/bootstrap.yaml

# USA Region - AZ3
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az3/bootstrap.yaml

# India Region - AZ1
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-india/az1/bootstrap.yaml

# India Region - AZ2
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-india/az2/bootstrap.yaml

# India Region - AZ3
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-india/az3/bootstrap.yaml
```

## Regions & Availability Zones

| Region | Location | AZ | Bootstrap File | Status |
|--------|----------|-----|----------------|--------|
| region-usa | USA | az1 | `region-usa/az1/bootstrap.yaml` | ✅ Active |
| region-usa | USA | az2 | `region-usa/az2/bootstrap.yaml` | 🔜 Planned |
| region-usa | USA | az3 | `region-usa/az3/bootstrap.yaml` | 🔜 Planned |
| region-india | India | az1 | `region-india/az1/bootstrap.yaml` | 🔜 Planned |
| region-india | India | az2 | `region-india/az2/bootstrap.yaml` | 🔜 Planned |
| region-india | India | az3 | `region-india/az3/bootstrap.yaml` | 🔜 Planned |

## What This Manages

Each region/az can manage:

- **Namespaces** - GitOps namespace for Flux Kustomizations
- **Global Resources** - VirtualGroups, Sealed Secrets Controller
- **Workspaces** - Workspace definitions and configurations
- **Clusters** - Workload cluster definitions with sealed secrets
- **RBAC** - Role bindings for workspace access
- **Network Policies** - Cross-workspace traffic controls
- **Resource Quotas** - Workspace resource limits
- **Projects** - Project definitions within workspaces
- **Applications** - Platform and project-level applications

## Repository Structure

```
.
├── bootstrap.yaml                              # Reference bootstrap (use region/az specific)
├── kustomization.yaml                          # Root kustomization (for legacy/CI)
├── README.md
│
├── region-usa/                                 # 🇺🇸 USA Region
│   ├── az1/                                    # Availability Zone 1 ✅ Active
│   │   ├── bootstrap.yaml                      # ← Bootstrap for this AZ
│   │   ├── kustomization.yaml                  # ← Resources for this AZ
│   │   ├── namespaces/
│   │   │   └── dm-nkp-gitops-namespace.yaml
│   │   ├── global/
│   │   │   ├── flux-ks.yaml
│   │   │   ├── kustomization.yaml
│   │   │   ├── virtualgroups.yaml
│   │   │   └── sealed-secrets-controller/
│   │   │       ├── flux-ks.yaml
│   │   │       ├── helmrelease.yaml
│   │   │       ├── helmrepository.yaml
│   │   │       └── namespace.yaml
│   │   └── workspaces/
│   │       ├── flux-ks.yaml
│   │       ├── kustomization.yaml
│   │       └── dm-dev-workspace/
│   │           ├── dm-dev-workspace.yaml
│   │           ├── applications/
│   │           │   ├── flux-ks.yaml
│   │           │   ├── platform-applications/
│   │           │   └── nkp-nutanix-products-catalog-applications/
│   │           ├── clusters/
│   │           │   ├── flux-ks.yaml
│   │           │   ├── bases/
│   │           │   ├── overlays/
│   │           │   └── sealed-secrets/
│   │           ├── networkpolicies/
│   │           │   └── flux-ks.yaml
│   │           ├── projects/
│   │           │   ├── flux-ks.yaml
│   │           │   └── dm-dev-project/
│   │           ├── rbac/
│   │           │   └── flux-ks.yaml
│   │           └── resourcequotas/
│   │               └── flux-ks.yaml
│   ├── az2/                                    # Availability Zone 2 🔜 Planned
│   │   ├── bootstrap.yaml
│   │   ├── kustomization.yaml
│   │   └── README.md
│   └── az3/                                    # Availability Zone 3 🔜 Planned
│       ├── bootstrap.yaml
│       ├── kustomization.yaml
│       └── README.md
│
└── region-india/                               # 🇮🇳 India Region
    ├── az1/                                    # Availability Zone 1 🔜 Planned
    │   ├── bootstrap.yaml
    │   ├── kustomization.yaml
    │   └── README.md
    ├── az2/                                    # Availability Zone 2 🔜 Planned
    │   ├── bootstrap.yaml
    │   ├── kustomization.yaml
    │   └── README.md
    └── az3/                                    # Availability Zone 3 🔜 Planned
        ├── bootstrap.yaml
        ├── kustomization.yaml
        └── README.md
```

## Bootstrap Architecture

Each bootstrap file creates two Flux resources:

```yaml
# 1. GitRepository - Points to this repo
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-<region>-<az>
  namespace: kommander

# 2. Kustomization - Points to region/az path
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: clusterops-<region>-<az>
  namespace: kommander
spec:
  path: ./region-<name>/az<n>
```

## Flux Kustomization Dependencies

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
   mkdir -p region-<name>/{az1,az2,az3}
   ```

2. For each AZ, create:
   - `bootstrap.yaml` - Copy from existing and update names
   - `kustomization.yaml` - Start with empty resources
   - `README.md` - Document the AZ

3. Copy the structure from `region-usa/az1/` when ready to configure

4. Update this README with new region status

## Adding a New AZ in Existing Region

1. The `bootstrap.yaml` and `kustomization.yaml` already exist

2. Copy structure from an active AZ:
   ```bash
   cp -r region-usa/az1/{namespaces,global,workspaces} region-usa/az2/
   ```

3. Update all configurations:
   - Namespace names
   - Workspace names
   - Cluster names and IPs
   - Sealed secrets (regenerate for new cluster)
   - Prism Central endpoints

4. Update `region-<name>/az<n>/kustomization.yaml` to reference resources

## Adding a New Workspace

1. Create workspace directory:
   ```bash
   mkdir -p region-<name>/az<n>/workspaces/<workspace-name>
   ```

2. Add required files:
   - `<workspace-name>.yaml` - Workspace definition
   - `applications/flux-ks.yaml`
   - `clusters/flux-ks.yaml`
   - `rbac/flux-ks.yaml`
   - etc.

3. Update `region-<name>/az<n>/workspaces/kustomization.yaml`

## Adding a New Cluster

1. Add cluster YAML under `.../clusters/bases/`
2. Add overlay patch under `.../clusters/overlays/<version>/`
3. Add sealed secrets under `.../clusters/sealed-secrets/`
4. Update the respective `kustomization.yaml` files

## Currently Active Configuration

### USA Region - AZ1

| Resource | Name | Details |
|----------|------|---------|
| Management Cluster | dm-nkp-mgmt-1 | NKP v2.17.0-rc.1 |
| Workspace | dm-dev-workspace | Development workspace |
| Workload Clusters | dm-nkp-workload-1, dm-nkp-workload-2 | 1 CP + 3 workers each |
| Project | dm-dev-project | Development project |

### Platform Applications

- Sealed Secrets Controller
- Kube Prometheus Stack
- Rook Ceph / Rook Ceph Cluster
- Grafana Loki (project-level)
- Grafana Logging (project-level)

### NKP Catalog Applications

- NDK (Nutanix Data Services for Kubernetes)
- Nutanix AI

## Troubleshooting

### Check Flux Status

```bash
# Check GitRepository
kubectl get gitrepository -n kommander

# Check Kustomizations
kubectl get kustomization -n kommander
kubectl get kustomization -n dm-nkp-gitops

# Check for errors
flux get all -A
```

### Force Reconciliation

```bash
# Reconcile GitRepository
flux reconcile source git gitops-usa-az1 -n kommander

# Reconcile Kustomization
flux reconcile kustomization clusterops-usa-az1 -n kommander
```

### View Flux Logs

```bash
kubectl logs -n kommander-flux deploy/source-controller
kubectl logs -n kommander-flux deploy/kustomize-controller
```
