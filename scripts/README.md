# Scripts

Utility scripts for managing the NKP GitOps infrastructure.

## migrate-to-new-structure.sh

Safely migrates from the old repository structure to the new management-cluster/workload-clusters structure.

### What It Does

1. **Disables pruning** on the Flux Kustomization (prevents resource deletion)
2. **Prompts you to push** changes to Git
3. **Applies new bootstrap** with updated path
4. **Triggers reconciliation** via Flux CLI or kubectl annotations
5. **Verifies** resources are healthy
6. **Optionally re-enables pruning**

### Usage

```bash
# Make sure kubectl is configured to management cluster
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# Run the migration
./scripts/migrate-to-new-structure.sh
```

### Why Is This Needed?

The repository structure changed from:
```
region-usa/az1/
├── bootstrap.yaml
├── global/
├── namespaces/
└── workspaces/
```

To:
```
region-usa/az1/
├── management-cluster/           # Management cluster resources
│   ├── bootstrap.yaml
│   ├── global/
│   │   └── sealed-secrets-controller/
│   ├── namespaces/
│   └── workspaces/
│       └── dm-dev-workspace/
│           ├── clusters/         # CAPI cluster definitions
│           ├── applications/
│           └── projects/
│
└── workload-clusters/            # Resources deployed INSIDE workload clusters
    ├── _base/
    │   └── infrastructure/
    │       └── sealed-secrets-controller/
    ├── dm-nkp-workload-1/
    │   ├── bootstrap.yaml        # Apply to workload cluster
    │   ├── infrastructure/
    │   │   └── sealed-secrets/
    │   └── apps/
    └── dm-nkp-workload-2/
        ├── bootstrap.yaml
        ├── infrastructure/
        │   └── sealed-secrets/
        └── apps/
```

The Flux Kustomization path changed from `./region-usa/az1` to `./region-usa/az1/management-cluster`.

Without disabling pruning first, Flux would see the old path as empty and **delete all resources** including your clusters!

### Bootstrapping Workload Clusters

After migration, bootstrap workload clusters (Flux is already installed by NKP):

```bash
# dm-nkp-workload-1
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig
kubectl apply -f region-usa/az1/workload-clusters/dm-nkp-workload-1/bootstrap.yaml

# dm-nkp-workload-2
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig
kubectl apply -f region-usa/az1/workload-clusters/dm-nkp-workload-2/bootstrap.yaml
```
