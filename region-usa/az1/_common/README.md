# Common / Shared Resources

This folder contains resources that are **shared across multiple clusters** (management and workload clusters).

## Structure

```
_common/
└── policies/
    └── gatekeeper/
        ├── constraint-templates/    # Policy logic (Rego)
        ├── constraints/             # Policy instances
        ├── network-tests/           # Connectivity testing
        ├── README.md                # Policy documentation
        ├── FIREWALL-REQUIREMENTS.md # Firewall port documentation
        ├── SECURITY-ROADMAP.md      # Security roadmap (local only)
        └── VIOLATIONS-REPORT.md     # Violations report (local only)
```

## How It Works

### Single Source of Truth

All Gatekeeper policies are defined **once** in `_common/policies/gatekeeper/`.

Both management and workload clusters reference these shared policies:

```
┌─────────────────────────────────────────────────────────────────┐
│                    _common/policies/gatekeeper/                 │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │ constraint-templates │    │     constraints     │            │
│  │  (Policy Logic)      │    │  (Policy Instances) │            │
│  └──────────┬──────────┘    └──────────┬──────────┘            │
└─────────────┼──────────────────────────┼────────────────────────┘
              │                          │
     ┌────────┴────────┐        ┌────────┴────────┐
     ▼                 ▼        ▼                 ▼
┌─────────┐    ┌─────────────┐  ┌─────────────┐
│  Mgmt   │    │ Workload-1  │  │ Workload-2  │
│ Cluster │    │   Cluster   │  │   Cluster   │
└─────────┘    └─────────────┘  └─────────────┘
```

### Management Cluster

References via Flux Kustomization in:
`management-cluster/global/policies/flux-ks-gatekeeper.yaml`

### Workload Clusters

References via Flux Kustomization in each cluster's `bootstrap.yaml`:
- `workload-clusters/dm-nkp-workload-1/bootstrap.yaml`
- `workload-clusters/dm-nkp-workload-2/bootstrap.yaml`

## Benefits

1. **No Duplication** - Single copy of all policies
2. **Consistency** - All clusters get the same security policies
3. **Easy Updates** - Change once, applies everywhere
4. **Clear Ownership** - `_common` indicates shared resources

## Customization

If a cluster needs different settings:

1. **Option A: Namespace Exclusions** - The shared constraints already have configurable `excludedNamespaces`
2. **Option B: Kustomize Patches** - Create overlays in cluster-specific folders to patch constraints
3. **Option C: Separate Constraint** - Create cluster-specific constraint files alongside shared ones

## Adding New Policies

1. Add ConstraintTemplate to `_common/policies/gatekeeper/constraint-templates/<category>/`
2. Add Constraint to `_common/policies/gatekeeper/constraints/<category>/`
3. Update the kustomization.yaml files in those directories
4. Commit and push - all clusters will receive the new policy

