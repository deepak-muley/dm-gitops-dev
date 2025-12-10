# Region India - Availability Zone 1

This availability zone is planned but not yet configured.

## To Activate

1. Copy the structure from `region-usa/az1/` to this directory
2. Update all `flux-ks.yaml` files to reference `region-india/az1/` paths
3. Update workspace names, cluster names, and other region-specific values
4. Update sealed secrets with India-specific credentials
5. Add references to root `kustomization.yaml`

## Expected Structure

```
az1/
├── namespaces/
├── global/
└── workspaces/
    └── <workspace-name>/
        ├── applications/
        ├── clusters/
        ├── networkpolicies/
        ├── projects/
        ├── rbac/
        └── resourcequotas/
```

