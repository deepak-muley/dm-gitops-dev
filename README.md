# NKP GitOps - Multi-Region Multi-AZ

GitOps repository for managing NKP Management Cluster resources across multiple regions and availability zones.

## Regions & Availability Zones

| Region | Location | Availability Zones | Status |
|--------|----------|-------------------|--------|
| USA    | Region 1 | az1, az2, az3     | ✅ Active (az1) |
| India  | Region 2 | az1, az2, az3     | 🔜 Planned |

This repository currently manages:
- **usa-az1/** - USA Region, Availability Zone 1

## What This Manages

- Workspaces & Workspace RBAC
- Projects & Project RBAC
- Clusters & Sealed Secrets
- Network Policies & Resource Quotas
- Platform Applications

## Bootstrap

Apply the bootstrap manifest to enable GitOps on the cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-gitops-dev/main/bootstrap.yaml
```

Or if you have the repo cloned locally:
```bash
kubectl apply -f bootstrap.yaml
```

> **Note:**
> - The bootstrap creates the GitRepository and root Kustomization in `kommander` namespace
> - All child Kustomizations will be created in `dm-nkp-gitops` namespace automatically

## Repository Structure

```
.
├── bootstrap.yaml                              # Apply once to bootstrap GitOps
├── kustomization.yaml                          # Root - references all flux-ks.yaml files
│
├── usa-az1/                                    # 🇺🇸 USA Region, AZ1
│   ├── namespaces/
│   │   └── dm-nkp-gitops-namespace.yaml
│   ├── global/
│   │   ├── flux-ks.yaml
│   │   ├── kustomization.yaml
│   │   └── virtualgroups.yaml
│   └── workspaces/
│       ├── flux-ks.yaml                        # clusterops-workspaces
│       ├── kustomization.yaml
│       └── dm-dev-workspace/
│           ├── dm-dev-workspace.yaml
│           ├── applications/
│           │   ├── flux-ks.yaml                # clusterops-workspace-applications
│           │   └── ...
│           ├── clusters/
│           │   ├── flux-ks.yaml                # clusterops-clusters
│           │   ├── bases/
│           │   │   ├── dm-nkp-workload-1.yaml
│           │   │   └── dm-nkp-workload-2.yaml
│           │   ├── overlays/
│           │   └── sealed-secrets/
│           │       ├── flux-ks.yaml            # clusterops-sealed-secrets
│           │       └── *.yaml
│           ├── networkpolicies/
│           │   └── flux-ks.yaml                # clusterops-workspace-networkpolicies
│           ├── projects/
│           │   ├── flux-ks.yaml                # clusterops-project-definitions
│           │   └── dm-dev-project/
│           │       └── applications/
│           │           └── flux-ks.yaml        # clusterops-project-applications
│           ├── rbac/
│           │   └── flux-ks.yaml                # clusterops-workspace-rbac
│           └── resourcequotas/
│               └── flux-ks.yaml                # clusterops-workspace-resourcequotas
│
├── usa-az2/                                    # 🇺🇸 USA Region, AZ2 (future)
├── usa-az3/                                    # 🇺🇸 USA Region, AZ3 (future)
├── india-az1/                                  # 🇮🇳 India Region, AZ1 (future)
├── india-az2/                                  # 🇮🇳 India Region, AZ2 (future)
└── india-az3/                                  # 🇮🇳 India Region, AZ3 (future)
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

## Adding a New Region/AZ

1. Copy an existing region-az directory (e.g., `usa-az1/`) to the new name (e.g., `india-az1/`)
2. Update all `flux-ks.yaml` files to reference the new path
3. Update workspace names, cluster names, and other region-specific values
4. Add references to root `kustomization.yaml`

## Adding a New Workspace

1. Create workspace directory: `<region-az>/workspaces/<workspace-name>/`
2. Add workspace YAML: `<workspace-name>.yaml`
3. Add `flux-ks.yaml` for each feature you need
4. Update `<region-az>/workspaces/kustomization.yaml`

## Adding a New Cluster

1. Add cluster YAML under `<region-az>/workspaces/<workspace>/clusters/bases/`
2. Add sealed secrets under `<region-az>/workspaces/<workspace>/clusters/sealed-secrets/`
3. Optionally add overlays for version-specific patches
