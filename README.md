# cluster-gitops

The objective of this project is to provide guidance on using gitops to manage NKP Management Cluster resources like:
- Workspaces & Workspace RBAC
- Projects & Workspace RBAC
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

Here is the structure of the folders and files.

> Note: The GitRepository and root Kustomization (`clusterops-demo`) run in `kommander` namespace.
> All child Flux Kustomizations run in `dm-nkp-gitops` namespace and depend on `clusterops-namespaces` to create that namespace first.

```
.
├── bootstrap.yaml                         # Apply this once to bootstrap GitOps (not managed by GitOps)
├── kustomization.yaml
├── namespaces-kustomization.yaml          # Creates dm-nkp-gitops namespace (runs in kommander)
├── global-kustomization.yaml              # Runs in dm-nkp-gitops
├── workspaces-kustomization.yaml          # Runs in dm-nkp-gitops
├── workspace-rbac-kustomization.yaml      # Runs in dm-nkp-gitops
├── workspace-networkpolicies-kustomization.yaml
├── workspace-resourcequotas-kustomization.yaml
├── workspace-applications-kustomization.yaml
├── projects-kustomization.yaml
├── clusters-kustomization.yaml
├── README.md
├── kustomizations
│   ├── clusters
│   │   └── kustomization.yaml
│   ├── global
│   │   └── kustomization.yaml
│   ├── projects
│   │   └── kustomization.yaml
│   ├── workspace-networkpolicies
│   │   └── kustomization.yaml
│   ├── workspace-rbac
│   │   └── kustomization.yaml
│   ├── workspace-resourcequotas
│   │   └── kustomization.yaml
│   └── workspaces
│       ├── applications
│       │   └── kustomization.yaml
│       └── kustomization.yaml
└── resources
    ├── namespaces
    │   ├── kustomization.yaml
    │   └── dm-nkp-gitops-namespace.yaml
    ├── global
    │   ├── kustomization.yaml
    │   └── virtualgroups.yaml
    └── workspaces
        ├── kustomization.yaml
        └── dm-dev-workspace
            ├── dm-dev-workspace.yaml
            ├── applications
            │   ├── kustomization.yaml
            │   ├── nkp-nutanix-products-catalog-applications
            │   │   ├── kustomization.yaml
            │   │   └── ndk
            │   │       ├── kustomization.yaml
            │   │       ├── ndk-2.0.0-config-overrides.yaml
            │   │       └── ndk-2.0.0.yaml
            │   └── platform-applications
            │       ├── kustomization.yaml
            │       ├── kube-prometheus-stack
            │       │   ├── kustomization.yaml
            │       │   ├── kube-prometheus-stack.yaml
            │       │   └── kube-prometheus-stack-overrides-configmap.yaml
            │       ├── rook-ceph
            │       │   ├── kustomization.yaml
            │       │   └── rook-ceph.yaml
            │       └── rook-ceph-cluster
            │           ├── kustomization.yaml
            │           └── rook-ceph-cluster.yaml
            ├── clusters
            │   ├── kustomization.yaml
            │   ├── bases
            │   │   ├── kustomization.yaml
            │   │   ├── README.md
            │   │   ├── dm-nkp-workload-1.yaml
            │   │   ├── dm-nkp-workload-1-sealed-secrets.yaml
            │   │   ├── dm-nkp-workload-2.yaml
            │   │   ├── dm-nkp-workload-2-sealed-secrets.yaml
            │   │   └── sealed-secrets-public-key.pem
            │   └── overlays
            │       └── 2.17.0-rc1
            │           ├── kustomization.yaml
            │           ├── dm-nkp-workload-1-patch.yaml
            │           └── dm-nkp-workload-2-patch.yaml
            ├── networkpolicies
            │   ├── kustomization.yaml
            │   └── deny-cross-workspace-traffic.yaml
            ├── projects
            │   ├── kustomization.yaml
            │   └── dm-dev-project
            │       ├── dm-dev-project.yaml
            │       └── applications
            │           └── platform-applications
            │               ├── kustomization.yaml
            │               ├── project-grafana-loki
            │               │   ├── kustomization.yaml
            │               │   ├── project-grafana-loki.yaml
            │               │   ├── project-grafana-loki-overrides-configmap.yaml
            │               │   └── project-grafana-loki-memory-alerts.yaml
            │               ├── project-logging
            │               │   ├── kustomization.yaml
            │               │   └── project-logging.yaml
            │               └── project-grafana-logging
            │                   ├── kustomization.yaml
            │                   └── project-grafana-logging.yaml
            ├── rbac
            │   ├── kustomization.yaml
            │   └── dm-dev-workspace-superheros-rolebinding.yaml
            └── resourcequotas
                ├── kustomization.yaml
                └── dm-dev-workspace-quota.yaml
```
