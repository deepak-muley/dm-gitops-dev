# Scripts

Utility scripts for managing the NKP GitOps infrastructure.

## Quick Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `bootstrap-capk.sh` | Install CAPK for Kubemark clusters | `./scripts/bootstrap-capk.sh mgmt` |
| `check-violations.sh` | Check Gatekeeper policy violations | `./scripts/check-violations.sh mgmt` |
| `migrate-to-new-structure.sh` | Migrate repo structure safely | `./scripts/migrate-to-new-structure.sh` |

---

## bootstrap-capk.sh

Install Cluster API Provider Kubemark (CAPK) for creating hollow node clusters for scale testing.

### What is Kubemark?

Kubemark creates "hollow" nodes that simulate real Kubernetes nodes without actual compute resources. Each hollow node runs as a pod (~50Mi memory) inside the management cluster. This allows testing at scale (100s-1000s of nodes) without provisioning real infrastructure.

**Use Cases:**
- Scale testing (simulate 100-1000+ nodes)
- Performance benchmarking
- Testing cluster autoscaler behavior
- Validating controllers at scale
- Cost-effective load testing

### Usage

```bash
# Install CAPK on management cluster (default)
./scripts/bootstrap-capk.sh
./scripts/bootstrap-capk.sh mgmt

# Check CAPK installation status
./scripts/bootstrap-capk.sh --status mgmt

# Generate manifests for GitOps deployment (instead of direct install)
./scripts/bootstrap-capk.sh --generate-manifests

# Help
./scripts/bootstrap-capk.sh --help
```

### Installation Options

#### Option 1: Direct Installation (Recommended for first setup)

```bash
./scripts/bootstrap-capk.sh mgmt
```

This runs `clusterctl init --infrastructure kubemark` on your management cluster.

#### Option 2: GitOps Installation

```bash
# Generate manifests
./scripts/bootstrap-capk.sh --generate-manifests

# This creates:
# region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/kubemark-infra/capk-provider/capk-components.yaml

# Then uncomment capk-components.yaml in the kustomization.yaml and push to git
```

### After Installation

Once CAPK is installed, enable Kubemark cluster creation:

1. Edit `clusters/kustomization.yaml` and uncomment:
   ```yaml
   - kubemark-infra
   ```

2. Commit and push to git

3. Monitor cluster creation:
   ```bash
   kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf \
     get clusters -n dm-dev-workspace -w
   ```

### Kubeconfig Shortcuts

| Shortcut | Kubeconfig Path |
|----------|-----------------|
| `mgmt` | `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf` |
| `workload1` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig` |
| `workload2` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig` |

---

## check-violations.sh

Check Gatekeeper policy violations across your NKP clusters with color-coded output.

### Usage

```bash
# Management cluster (default)
./scripts/check-violations.sh
./scripts/check-violations.sh mgmt

# Workload clusters
./scripts/check-violations.sh workload1
./scripts/check-violations.sh workload2

# Custom kubeconfig
./scripts/check-violations.sh /path/to/kubeconfig

# Summary only (no details)
./scripts/check-violations.sh --summary mgmt

# Filter by namespace
./scripts/check-violations.sh -n kube-system mgmt
./scripts/check-violations.sh --namespace kommander mgmt
./scripts/check-violations.sh -n flux-system workload1

# Combine options
./scripts/check-violations.sh --summary -n kommander mgmt

# Export to JSON file
./scripts/check-violations.sh --export mgmt

# Export violations for a specific namespace
./scripts/check-violations.sh --export -n dm-dev-workspace mgmt

# Help
./scripts/check-violations.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `--summary` | Show only violation counts, skip detailed violations |
| `-n, --namespace NS` | Filter violations for a specific namespace |
| `--export` | Export violations to a JSON file |
| `--help` | Show help message |

### Output Sections

1. **Violations Summary** - All constraints with violation counts and severity
2. **By Namespace** - Which namespaces have the most violations (skipped when using `-n`)
3. **By Category** - Violations grouped by policy category (pod-security, rbac, etc.)
4. **Detailed Violations** - Specific resources violating each constraint (unless `--summary`)
5. **Quick Actions** - Helpful kubectl commands

### Understanding Detailed Violations

The detailed violations section shows exactly which resources are violating policies:

```
▶ block-privileged-containers                    ← Constraint name (policy violated)
  - kommander/Pod/rook-ceph-osd-3-64c56f849c-dd5p8    ← namespace/kind/resource-name
    → Privileged init container not allowed: activate  ← Why it's violating
```

| Component | Meaning |
|-----------|---------|
| **Constraint name** | The Gatekeeper policy that was violated |
| **Namespace** | Where the resource lives |
| **Kind** | The Kubernetes resource type (Pod, Deployment, Ingress, etc.) |
| **Resource name** | The specific resource violating the policy |
| **Message (→)** | The actual problem to fix |

### Sample Output

```
════════════════════════════════════════════════════════════════
  GATEKEEPER VIOLATIONS SUMMARY (namespace: kommander)
════════════════════════════════════════════════════════════════

Constraint                              | Violations | Severity
----------------------------------------|------------|----------
block-privileged-containers             | 20         | 🔴 CRITICAL
block-host-namespace                    | 18         | 🔴 CRITICAL
require-ingress-tls                     | 16         | 🟠 HIGH
...
----------------------------------------|------------|----------
TOTAL VIOLATIONS: 112
```

### Kubeconfig Shortcuts

The script knows your NKP kubeconfig locations:

| Shortcut | Kubeconfig Path |
|----------|-----------------|
| `mgmt` | `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf` |
| `workload1` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig` |
| `workload2` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig` |

### Export to JSON

Generate a JSON report for further analysis or Jira tickets:

```bash
./scripts/check-violations.sh --export mgmt
# Creates: violations-report-20241214-200000.json

./scripts/check-violations.sh --export -n kommander mgmt
# Creates: violations-report-kommander-20241214-200000.json
```

### Advanced: Filter by Specific Component

For more granular filtering (specific pod, deployment, or resource), use kubectl + jq directly:

```bash
# Set kubeconfig first
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# Violations for resources containing "rook-ceph" in kommander namespace
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $constraint |
  .status.violations[]? |
  select(.namespace == "kommander" and (.name | contains("rook-ceph"))) |
  "[\($constraint)] \(.namespace)/\(.kind)/\(.name)\n  → \(.message)\n"
'

# Violations for a specific pod
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $c |
  .status.violations[]? |
  select(.name == "my-pod-name-xyz") |
  "[\($c)] \(.kind)/\(.name): \(.message)"
'

# Only Ingress violations in a namespace
kubectl get constraints -o json | jq -r '
  .items[].status.violations[]? |
  select(.namespace == "kommander" and .kind == "Ingress") |
  "\(.kind)/\(.name): \(.message)"
'

# Violations for grafana components
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $c |
  .status.violations[]? |
  select(.namespace == "kommander" and (.name | contains("grafana"))) |
  "[\($c)] \(.kind)/\(.name)\n  → \(.message)\n"
'

# Violations for prometheus node-exporter
kubectl get constraints -o json | jq -r '
  .items[] |
  .metadata.name as $c |
  .status.violations[]? |
  select((.name | contains("node-exporter"))) |
  "[\($c)] \(.namespace)/\(.kind)/\(.name)\n  → \(.message)\n"
'
```

### jq Filter Quick Reference

| Filter By | jq Selection |
|-----------|--------------|
| Namespace | `select(.namespace == "kommander")` |
| Resource name contains | `select(.name \| contains("grafana"))` |
| Exact resource name | `select(.name == "my-pod-xyz")` |
| Resource kind | `select(.kind == "Ingress")` |
| Combine filters | `select(.namespace == "X" and .kind == "Y")` |

---

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
