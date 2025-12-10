# cluster-gitops

The objective of this project is to provide guidance on using gitops to manage NKP Management Cluster resources like:
- Workspaces & Workspace RBAC
- Projects & Project RBAC
- Clusters

## Bootstrap

Simply apply the bootstrap manifest to enable GitOps on the cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-gitops-dev/main/bootstrap.yaml
```

Or if you have the repo cloned locally:
```bash
kubectl apply -f bootstrap.yaml
```

> **Note:**
> - The bootstrap creates the GitRepository and root Kustomization in `kommander` namespace (required for Flux)
> - All child Kustomizations will be created in `dm-nkp-gitops` namespace automatically
> - For clusters, any secrets with PC credentials or Registry Credentials should be applied directly in the workspace namespace

### What the bootstrap creates:
- **GitRepository** `gitops-demo` in `kommander` namespace - points to this repo
- **Kustomization** `clusterops-demo` in `kommander` namespace - applies all GitOps manifests

## Repository Structure

The repository is organized into three main directories:

| Directory | Purpose |
|-----------|---------|
| `kustomizations/` | Flux Kustomization resources (`flux-ks.yaml`) and kustomize entry points (`kustomization.yaml`) |
| `resources/` | Actual Kubernetes resources (Workspaces, Clusters, Projects, etc.) |

Each `kustomizations/*` directory contains:
- `flux-ks.yaml` - The Flux Kustomization resource that tells Flux to reconcile this path
- `kustomization.yaml` - The kustomize configuration that references actual resources

```
.
├── bootstrap.yaml                    # Apply once to bootstrap GitOps (not managed by GitOps)
├── kustomization.yaml                # Root kustomization - references all flux-ks.yaml files
├── kustomizations/
│   ├── clusters/
│   │   ├── flux-ks.yaml              # Flux Kustomization for clusters
│   │   └── kustomization.yaml        # References resources/workspaces/*/clusters
│   ├── global/
│   │   ├── flux-ks.yaml
│   │   └── kustomization.yaml
│   ├── project-applications/
│   │   ├── flux-ks.yaml              # Depends on project-definitions
│   │   └── kustomization.yaml
│   ├── project-definitions/
│   │   ├── flux-ks.yaml              # Depends on workspaces
│   │   └── kustomization.yaml
│   ├── sealed-secrets/
│   │   ├── flux-ks.yaml
│   │   └── kustomization.yaml
│   ├── workspace-networkpolicies/
│   │   ├── flux-ks.yaml
│   │   └── kustomization.yaml
│   ├── workspace-rbac/
│   │   ├── flux-ks.yaml
│   │   └── kustomization.yaml
│   ├── workspace-resourcequotas/
│   │   ├── flux-ks.yaml
│   │   └── kustomization.yaml
│   └── workspaces/
│       ├── applications/
│       │   ├── flux-ks.yaml
│       │   └── kustomization.yaml
│       ├── flux-ks.yaml
│       └── kustomization.yaml
└── resources/
    ├── global/
    │   ├── kustomization.yaml
    │   └── virtualgroups.yaml
    ├── namespaces/
    │   ├── dm-nkp-gitops-namespace.yaml
    │   └── kustomization.yaml
    └── workspaces/
        ├── kustomization.yaml
        └── dm-dev-workspace/
            ├── dm-dev-workspace.yaml
            ├── applications/
            │   ├── kustomization.yaml
            │   ├── nkp-nutanix-products-catalog-applications/
            │   │   └── ndk/
            │   │       ├── ndk-2.0.0.yaml
            │   │       └── ndk-2.0.0-config-overrides.yaml
            │   └── platform-applications/
            │       ├── kube-prometheus-stack/
            │       ├── rook-ceph/
            │       └── rook-ceph-cluster/
            ├── clusters/
            │   ├── kustomization.yaml
            │   ├── bases/
            │   │   ├── dm-nkp-workload-1.yaml
            │   │   ├── dm-nkp-workload-1-sealed-secrets.yaml
            │   │   ├── dm-nkp-workload-2.yaml
            │   │   └── dm-nkp-workload-2-sealed-secrets.yaml
            │   └── overlays/
            │       └── 2.17.0-rc1/
            ├── networkpolicies/
            │   └── deny-cross-workspace-traffic.yaml
            ├── projects/
            │   └── dm-dev-project/
            │       ├── dm-dev-project.yaml
            │       └── applications/
            │           └── platform-applications/
            │               ├── project-grafana-loki/
            │               ├── project-logging/
            │               └── project-grafana-logging/
            ├── rbac/
            │   └── dm-dev-workspace-superheros-rolebinding.yaml
            └── resourcequotas/
                └── dm-dev-workspace-quota.yaml
```

## Flux Kustomization Dependencies

The Flux Kustomizations are applied in order based on dependencies:

```
Level 0 (No dependencies):
  ├── clusterops-global
  └── clusterops-workspaces

Level 1 (Depends on workspaces):
  ├── clusterops-workspace-rbac
  ├── clusterops-workspace-networkpolicies
  ├── clusterops-workspace-resourcequotas
  ├── clusterops-workspace-applications
  ├── clusterops-clusters
  ├── clusterops-sealed-secrets
  └── clusterops-project-definitions

Level 2 (Depends on project-definitions):
  └── clusterops-project-applications
```

## Adding a New Workspace

1. Create workspace directory under `resources/workspaces/<workspace-name>/`
2. Add workspace YAML: `<workspace-name>.yaml`
3. Add subdirectories as needed: `clusters/`, `projects/`, `rbac/`, etc.
4. Update `resources/workspaces/kustomization.yaml` to include the new workspace

## Adding a New Cluster

1. Add cluster YAML under `resources/workspaces/<workspace>/clusters/bases/`
2. Add sealed secrets for credentials
3. Optionally add overlays for version-specific patches
