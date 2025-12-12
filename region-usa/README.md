# USA Region

GitOps configuration for USA region availability zones.

## Availability Zones

| AZ | Bootstrap | Status | Management Cluster |
|----|-----------|--------|-------------------|
| az1 | `az1/bootstrap.yaml` | ✅ Active | dm-nkp-mgmt-1 |
| az2 | `az2/bootstrap.yaml` | 🔜 Planned | - |
| az3 | `az3/bootstrap.yaml` | 🔜 Planned | - |

## Bootstrap

```bash
# Bootstrap AZ1
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az1/bootstrap.yaml

# Bootstrap AZ2 (when ready)
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az2/bootstrap.yaml

# Bootstrap AZ3 (when ready)
kubectl apply -f https://raw.githubusercontent.com/deepak-muley/dm-nkp-gitops-infra/main/region-usa/az3/bootstrap.yaml
```

## AZ1 Resources

Currently managing:
- Workspace: `dm-dev-workspace`
- Clusters: `dm-nkp-workload-1`, `dm-nkp-workload-2`
- Project: `dm-dev-project`

## Adding a New AZ

1. Update the `az<n>/kustomization.yaml` with resources
2. Copy structure from `az1/` as a template
3. Update all configurations (IPs, names, secrets)
4. Apply the bootstrap file to the new management cluster
