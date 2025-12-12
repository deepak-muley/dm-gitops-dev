# India Region

GitOps configuration for India region availability zones.

## Availability Zones

| AZ | Bootstrap | Status | Management Cluster |
|----|-----------|--------|-------------------|
| az1 | `az1/bootstrap.yaml` | 🔜 Planned | - |
| az2 | `az2/bootstrap.yaml` | 🔜 Planned | - |
| az3 | `az3/bootstrap.yaml` | 🔜 Planned | - |

## Bootstrap

```bash
# Bootstrap AZ1 (when ready)
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-india/az1/bootstrap.yaml

# Bootstrap AZ2 (when ready)
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-india/az2/bootstrap.yaml

# Bootstrap AZ3 (when ready)
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-india/az3/bootstrap.yaml
```

## Setting Up This Region

1. Copy the structure from `region-usa/az1/` to `region-india/az1/`:
   ```bash
   cp -r region-usa/az1/{namespaces,global,workspaces} region-india/az1/
   ```

2. Update configurations:
   - Prism Central endpoint
   - Cluster IPs and subnets
   - Sealed secrets (regenerate)
   - Workspace/cluster names

3. Update `az1/kustomization.yaml` to reference resources

4. Apply the bootstrap file to the management cluster
