# Region India

🇮🇳 India Region - Planned for future deployment.

## Availability Zones

| AZ | Status |
|----|--------|
| az1 | 🔜 Planned |
| az2 | 🔜 Planned |
| az3 | 🔜 Planned |

## To Activate an AZ

1. Copy the structure from `region-usa/az1/` to the target AZ directory
2. Update all `flux-ks.yaml` files to reference `region-india/az<n>/` paths
3. Update workspace names, cluster names, and other region-specific values
4. Update sealed secrets with India-specific credentials
5. Add references to root `kustomization.yaml`

