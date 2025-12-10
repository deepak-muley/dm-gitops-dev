# Region USA - Availability Zone 3

This availability zone is planned but not yet configured.

## To Activate

1. Copy the structure from `../az1/` to this directory
2. Update all `flux-ks.yaml` files to reference `region-usa/az3/` paths
3. Update workspace names, cluster names, and other AZ-specific values
4. Add references to root `kustomization.yaml`

## Expected Structure

```
az3/
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

