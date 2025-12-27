# Scripts

Utility scripts for managing the NKP GitOps infrastructure.

## Quick Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `sealed-secrets.sh` | Unified sealed-secrets management (backup, restore, encrypt, decrypt, re-encrypt, status) | `./scripts/sealed-secrets.sh <command>` |
| `bootstrap-capk.sh` | Install CAPK for Kubemark clusters | `./scripts/bootstrap-capk.sh mgmt` |
| `bootstrap-sealed-secrets-key-crs.sh` | Deploy sealed-secrets key via ClusterResourceSet | `./scripts/bootstrap-sealed-secrets-key-crs.sh` |
| `check-cluster-health.sh` | Check health of all NKP clusters | `./scripts/check-cluster-health.sh` |
| `check-violations.sh` | Check Gatekeeper policy violations | `./scripts/check-violations.sh mgmt` |
| `get-kubescape-cves.sh` | Get CVEs from kubescape scans with severity filtering | `./scripts/get-kubescape-cves.sh [severity] [cluster]` |
| `list-clusterapps-and-apps.sh` | List all ClusterApp and App CRs grouped by type | `./scripts/list-clusterapps-and-apps.sh [--generate-block-diagram]` |
| `migrate-to-new-structure.sh` | Migrate repo structure safely | `./scripts/migrate-to-new-structure.sh` |
| `pod-security-audit.sh` | Comprehensive pod security testing (escape, hardening, context) | `./scripts/pod-security-audit.sh --namespace <ns> --pod <pod> [options]` |
| `validate-security-fixes.sh` | Validate if security fixes will break a pod before applying | `./scripts/validate-security-fixes.sh --namespace <ns> --pod <pod> [options]` |
| `nkp-pentest-suite.sh` | Comprehensive penetration testing suite for NKP clusters | `./scripts/nkp-pentest-suite.sh [--kubeconfig <path>] [--namespace <ns>] [--output <dir>]` |
| `run-pentest-tools.sh` | Install and run individual penetration testing tools (kubescape, kubeaudit, trivy, etc.) | `./scripts/run-pentest-tools.sh <tool> [--namespace <ns>] [--cluster <name>]` |

---

## validate-security-fixes.sh

Validates if security fixes will break a pod before applying them. This script helps answer the critical question: "Will my pod work after applying security fixes?"

### Why Is This Needed?

Applying security fixes blindly can break applications. This script analyzes:
- Current security configuration
- Runtime requirements (what the pod actually uses)
- Application type and patterns
- Documentation and annotations
- Dry-run validation

### Usage

```bash
# Basic usage
./scripts/validate-security-fixes.sh --namespace <namespace> --pod <pod-name>

# With kubeconfig
./scripts/validate-security-fixes.sh \
  --namespace kube-system \
  --pod cilium-xxx \
  --kubeconfig /path/to/kubeconfig

# Export analysis report
./scripts/validate-security-fixes.sh \
  --namespace kommander \
  --pod kommander-appmanagement-xxx \
  --export analysis-report.txt
```

### What It Analyzes

1. **Current Security Configuration**
   - Pod-level: hostNetwork, hostPID, hostIPC, runAsUser
   - Container-level: privileged, capabilities, readOnlyRootFilesystem

2. **Runtime Requirements**
   - What user the pod is actually running as
   - What capabilities are in use
   - Whether filesystem writes are needed

3. **Documentation and Annotations**
   - Security-related annotations
   - Application type detection (CNI, monitoring, etc.)
   - Pattern recognition for common pod types

4. **Dry-Run Validation**
   - Tests if fixes are syntactically valid
   - Validates against Kubernetes API

5. **Recommendations**
   - Specific guidance based on analysis
   - Risk assessment for each fix
   - Testing strategy

### Example Output

```
═══════════════════════════════════════════════════════════════
Security Fix Validation Analysis
═══════════════════════════════════════════════════════════════

1. Current Security Configuration
   ⚠ hostNetwork: true (required for CNI/network plugins)
   ✗ Currently running as root (UID: 0)
   ⚠ Container has effective capabilities

2. Runtime Requirements Analysis
   → Fix: Set runAsUser to non-root (e.g., 65532)
   → Risk: HIGH - May break if app requires root privileges

3. Documentation and Annotations
   ⚠ This appears to be a CNI/network plugin
   → Recommendation: DO NOT apply strict security fixes

4. Recommendations
   ⚠ Pod uses hostNetwork
   → This is a network plugin - hostNetwork is REQUIRED
   → DO NOT change hostNetwork: false
```

### Common Patterns Detected

- **CNI/Network Plugins** (cilium, calico, etc.):
  - Require: hostNetwork, privileged, NET_ADMIN
  - Recommendation: DO NOT apply strict fixes

- **Monitoring Pods** (node-exporter, prometheus):
  - May require: hostPID, hostNetwork
  - Recommendation: Test carefully

- **Application Pods**:
  - Usually safe to harden
  - Recommendation: Apply fixes with testing

### See Also

- `docs/SECURITY-FIX-VALIDATION-GUIDE.md` - Comprehensive guide on validating security fixes
- `pod-security-audit.sh` - Security audit with fix export

---

---

## bootstrap-sealed-secrets-key-crs.sh

Create a ClusterResourceSet to automatically deploy the sealed-secrets private key to all workload clusters.

### Why Is This Needed?

For SealedSecrets to work across multiple clusters, all clusters must share the same private key. This script:

1. **Reads** the sealed-secrets private key from a local file (NEVER stored in git!)
2. **Creates** a Kubernetes Secret in the management cluster containing the key
3. **Creates** a ClusterResourceSet that deploys the key to all matching workload clusters

### Security

⚠️ **IMPORTANT**: The private key is NEVER stored in git. The script reads it from:
```
/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml
```

This location is protected by `.gitignore` patterns to prevent accidental commits.

### Usage

```bash
# Apply to management cluster (uses default kubeconfig context)
./scripts/bootstrap-sealed-secrets-key-crs.sh

# Specify management cluster kubeconfig
./scripts/bootstrap-sealed-secrets-key-crs.sh -k /Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# Dry run (show what would be created without applying)
./scripts/bootstrap-sealed-secrets-key-crs.sh --dry-run

# Use a different key file location
./scripts/bootstrap-sealed-secrets-key-crs.sh -f /path/to/my-sealed-secrets-key.yaml

# Cleanup (remove the ClusterResourceSet and Secret)
./scripts/bootstrap-sealed-secrets-key-crs.sh --cleanup

# Help
./scripts/bootstrap-sealed-secrets-key-crs.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `-k, --kubeconfig PATH` | Path to kubeconfig file |
| `-f, --key-file PATH` | Path to sealed-secrets key backup (default: `/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml`) |
| `-n, --namespace NS` | Namespace for ClusterResourceSet (default: `dm-dev-workspace`) |
| `-d, --dry-run` | Show what would be created without applying |
| `-c, --cleanup` | Remove the ClusterResourceSet and Secret |
| `-h, --help` | Show help message |

### What Gets Created

The script creates two resources in the management cluster:

1. **Secret** (`sealed-secrets-key-resources`): Contains the sealed-secrets private key as YAML data
2. **ClusterResourceSet** (`sealed-secrets-key-crs`): Deploys the Secret content to matching clusters

### Cluster Selector

The ClusterResourceSet selects clusters with label:
```yaml
matchLabels:
  konvoy.d2iq.io/provider: nutanix
```

This automatically targets all Nutanix workload clusters.

### Verifying Deployment

After running the script:

```bash
# Check ClusterResourceSet status
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf \
  get clusterresourceset -n dm-dev-workspace

# Check ClusterResourceSetBindings (one per matching cluster)
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf \
  get clusterresourcesetbinding -n dm-dev-workspace

# Verify key was deployed to a workload cluster
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig \
  get secrets -n sealed-secrets-system -l sealedsecrets.bitnami.com/sealed-secrets-key
```

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
# region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/kubemark-hollow-machines/capk-components.yaml

# Then uncomment capk-components.yaml in the kustomization.yaml and push to git
```

### After Installation

Once CAPK is installed, enable Kubemark cluster creation:

1. Edit `clusters/kustomization.yaml` and uncomment:
   ```yaml
   - kubemark-hollow-machines
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

## check-cluster-health.sh

Comprehensive health check for all NKP clusters (management and workload). Checks:
- Node status (Ready/NotReady)
- Pod health (Failed, Pending, CrashLoopBackOff, ImagePullBackOff)
- Flux Kustomizations status
- Flux HelmReleases status
- Flux GitRepositories status

### Usage

```bash
# Check all clusters (mgmt, workload1, workload2)
./scripts/check-cluster-health.sh

# Check specific cluster(s)
./scripts/check-cluster-health.sh mgmt
./scripts/check-cluster-health.sh workload1 workload2

# Summary only (no detailed problem lists)
./scripts/check-cluster-health.sh --summary

# Watch mode (refresh every 30 seconds)
./scripts/check-cluster-health.sh --watch

# Watch with custom interval
./scripts/check-cluster-health.sh --watch --interval 60

# Combine options
./scripts/check-cluster-health.sh --summary mgmt workload1

# Help
./scripts/check-cluster-health.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `--summary, -s` | Show only summary table (no detailed problem lists) |
| `--watch, -w` | Continuously monitor (refreshes every 30s) |
| `--interval, -i N` | Set watch interval to N seconds (default: 30) |
| `--help, -h` | Show help message |

### Sample Output

```
╔══════════════════════════════════════════════════════════════════╗
║           NKP CLUSTER HEALTH CHECK                               ║
║           2024-12-17 10:30:45                                    ║
╚══════════════════════════════════════════════════════════════════╝

════════════════════════════════════════════════════════════════
  OVERALL HEALTH SUMMARY
════════════════════════════════════════════════════════════════

Cluster      | Nodes  | Pods   | KS   | HR   | GR   | HCP  | HRP  | AD   | ADI
-------------|--------|--------|------|------|------|------|------|------|-----
mgmt         | ✓      | ✓      | ✓    | ✓    | ✓    | ✓    | ✓    | ✓    | ✓
workload1    | ✓      | ✗      | ✓    | ✓    | ✓    | -    | -    | -    | -
workload2    | ✓      | ✓      | ✗    | ✓    | ✓    | -    | -    | -    | -

Legend: ✓ = Healthy, ✗ = Issues, - = N/A or Not Installed

Columns: KS=Kustomizations, HR=HelmReleases, GR=GitRepos, HCP=HelmChartProxies, HRP=HelmReleaseProxies,
         AD=AppDeployments, ADI=AppDeploymentInstances (HCP, HRP, AD, ADI are management cluster only)
```

### What It Checks

| Category | What's Checked | Clusters |
|----------|----------------|----------|
| **Nodes** | All nodes should be in Ready state | All |
| **Pods** | No Failed, Error, Pending, CrashLoopBackOff, or ImagePullBackOff pods | All |
| **Kustomizations (KS)** | All Flux Kustomizations should have Ready=True | All |
| **HelmReleases (HR)** | All Flux HelmReleases should have Ready=True | All |
| **GitRepositories (GR)** | All Flux GitRepositories should have Ready=True | All |
| **HelmChartProxies (HCP)** | All CAPI HelmChartProxies should have Ready=True | mgmt only |
| **HelmReleaseProxies (HRP)** | All CAPI HelmReleaseProxies should have Ready=True | mgmt only |
| **AppDeployments (AD)** | All Kommander AppDeployments should be synced to target clusters | mgmt only |
| **AppDeploymentInstances (ADI)** | All Kommander AppDeploymentInstances should have KustomizationReady=True and KustomizationHealthy=True | mgmt only |

### Kubeconfig Locations

| Cluster | Kubeconfig Path |
|---------|-----------------|
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

## list-clusterapps-and-apps.sh

List all ClusterApp and App custom resources from the management cluster, grouped by type with display names and scope information. Features beautiful colored terminal output and powerful filtering options.

### Usage

```bash
# Set kubeconfig to management cluster
export KUBECONFIG=/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# List all resources
./scripts/list-clusterapps-and-apps.sh

# Filter by kind
./scripts/list-clusterapps-and-apps.sh --kind ClusterApp
./scripts/list-clusterapps-and-apps.sh --kind App

# Filter by scope
./scripts/list-clusterapps-and-apps.sh --scope workspace
./scripts/list-clusterapps-and-apps.sh --scope project

# Search by name (partial match, case-insensitive)
./scripts/list-clusterapps-and-apps.sh --name insights
./scripts/list-clusterapps-and-apps.sh --name kserve

# Filter by namespace (for App resources)
./scripts/list-clusterapps-and-apps.sh --namespace kommander-default-workspace

  # Filter by type
  ./scripts/list-clusterapps-and-apps.sh --type nkp-core-platform
  ./scripts/list-clusterapps-and-apps.sh --type custom

  # Filter by licensing
  ./scripts/list-clusterapps-and-apps.sh --licensing ultimate
  ./scripts/list-clusterapps-and-apps.sh --licensing pro

  # Filter by dependencies
  ./scripts/list-clusterapps-and-apps.sh --dependencies cert-manager
  ./scripts/list-clusterapps-and-apps.sh --dependencies traefik

  # Check deployment status (AppDeployment and AppDeploymentInstance)
  ./scripts/list-clusterapps-and-apps.sh --check-deployments
  ./scripts/list-clusterapps-and-apps.sh --check-deployments --name cert-manager
  ./scripts/list-clusterapps-and-apps.sh --check-deployments --kind ClusterApp

  # Generate block diagram of ClusterApp dependencies
  ./scripts/list-clusterapps-and-apps.sh --generate-block-diagram

  # Combine multiple filters
  ./scripts/list-clusterapps-and-apps.sh --kind App --scope workspace --name kserve
  ./scripts/list-clusterapps-and-apps.sh --kind ClusterApp --type nkp-core-platform --scope workspace
  ./scripts/list-clusterapps-and-apps.sh --licensing ultimate --dependencies cert-manager
  ./scripts/list-clusterapps-and-apps.sh --check-deployments --name cert-manager --scope workspace

  # Show only summary statistics
  ./scripts/list-clusterapps-and-apps.sh --summary

  # Disable colored output
  ./scripts/list-clusterapps-and-apps.sh --no-color

  # Show help
  ./scripts/list-clusterapps-and-apps.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `--kind KIND` | Filter by kind (ClusterApp or App) |
| `--scope SCOPE` | Filter by scope (workspace or project) |
| `--name PATTERN` | Filter by name (partial match, case-insensitive) |
| `--namespace NS` | Filter by namespace (for App resources) |
| `--type TYPE` | Filter by type (custom, internal, nkp-catalog, nkp-core-platform) |
| `--licensing PATTERN` | Filter by licensing (partial match, e.g., "pro", "ultimate") |
| `--dependencies PATTERN` | Filter by dependencies (partial match, e.g., "cert-manager") |
| `--check-deployments` | Show AppDeployment status and cluster deployment information |
| `--generate-block-diagram` | Generate block diagram of ClusterApp dependencies |
| `--no-color` | Disable colored output |
| `--summary` | Show only summary statistics (no detailed tables) |
| `-h, --help` | Show help message |

### Requirements

- `kubectl` - Must be installed and configured
- `jq` - JSON processor (install via `brew install jq` on macOS)
- `KUBECONFIG` environment variable set to management cluster kubeconfig

### Output

The script generates beautifully formatted tables with color-coded output:

- **Blue** - ClusterApp resources
- **Green** - App resources
- **Yellow** - Workspace scope
- **Magenta** - Project scope
- **Cyan** - Section headers

Tables are grouped by application type:

- **custom** - Custom applications
- **internal** - Internal Kommander applications
- **nkp-catalog** - Applications from NKP catalog
- **nkp-core-platform** - Core NKP platform applications

Each table includes:
- **Kind** - ClusterApp or App (color-coded)
- **Name** - Resource name
- **Version** - Application version
- **Display Name** - Human-readable name from annotations
- **Scope** - Workspace or project scope (color-coded)
- **Type** - Application type (custom, internal, nkp-catalog, nkp-core-platform)
- **Licensing** - Required licensing tiers (e.g., "pro,ultimate,essential,enterprise")
- **Dependencies** - Required dependencies (e.g., "cert-manager", "traefik")

When using `--check-deployments`, additional deployment information is shown:
- **Enabled Status** - Whether an AppDeployment exists (✓ Enabled or ○ Not enabled)
- **Target Clusters** - List of clusters where the app is configured to be deployed
- **Deployment Status** - Summary of healthy/total instances (e.g., "2/2 Healthy")
- **Instance Details** - Per-cluster status showing which clusters have successfully deployed instances (✓ = healthy, ○ = not healthy)

The output also includes a summary section with statistics:
- Total resource count
- Breakdown by type
- Breakdown by kind
- Breakdown by scope

### Sample Output

```
════════════════════════════════════════════════════════════════
  ClusterApp and App Resources
════════════════════════════════════════════════════════════════

Active Filters:
  Kind: App
  Scope: workspace
  Type: nkp-catalog

════════════════════════════════════════════════════════════════
  Type: nkp-catalog | Kind: App | Count: 5
════════════════════════════════════════════════════════════════

┌─────────────┬──────────────────────────────────────────┬─────────────┬──────────────────────────────────────┬────────────┬──────────────────────────────────────┬──────────────────────────────────────┐
│ Kind        │ Name                                     │ Version     │ Display Name                         │ Scope      │ Licensing                            │ Dependencies                         │
├─────────────┼──────────────────────────────────────────┼─────────────┼──────────────────────────────────────┼────────────┼──────────────────────────────────────┼──────────────────────────────────────┤
│ App         │ envoy-gateway-1.5.0                      │ 1.5.0       │ Envoy Gateway                        │ workspace  │ pro,ultimate,Essential,Enterprise    │ cert-manager                         │
│ App         │ kserve-0.15.0                            │ 0.15.0      │ Kserve                               │ workspace  │ pro,ultimate,Essential,Enterprise    │ cert-manager                         │
...
└─────────────┴──────────────────────────────────────────┴─────────────┴──────────────────────────────────────┴────────────┴──────────────────────────────────────┴──────────────────────────────────────┘

════════════════════════════════════════════════════════════════
  Summary Statistics
════════════════════════════════════════════════════════════════

Total Resources: 5

By Type:
  nkp-catalog         :   5

By Kind:
  App                 :   5

By Scope:
  workspace           :   5
```

### Use Cases

- **Audit applications** - See all available ClusterApps and Apps with beautiful formatting
- **Version tracking** - Check versions of deployed applications
- **Scope analysis** - Understand which apps are workspace vs project scoped
- **Type categorization** - Group applications by their type (custom, internal, catalog, platform)
- **Quick searches** - Find specific applications by name pattern
- **Namespace filtering** - See which Apps are in specific namespaces
- **Licensing analysis** - Find apps by required licensing tiers
- **Dependency tracking** - Identify apps that require specific dependencies (e.g., cert-manager, traefik)
- **Reporting** - Generate summary statistics for documentation
- **Block diagram generation** - Visualize ClusterApp dependencies with `--generate-block-diagram`

### See Also

- `docs/DEBUGGING-GITOPS.md` - GitOps debugging guide
- `docs/NKP-RBAC-GUIDE.md` - RBAC guide for NKP
- `docs/internal/CLUSTERAPP-BLOCK-DIAGRAM.md` - Generated block diagram output (not tracked in git)

---

## generate-clusterapp-block-diagram.py

Generates a visual block diagram showing ClusterApp dependencies. Each app appears once as a block with its dependencies (parents) and dependents (children). Root nodes (apps with no dependencies) start their own chains.

**Note**: This script is integrated into `list-clusterapps-and-apps.sh`. Use `--generate-block-diagram` flag with that script for convenience.

### Usage

```bash
# Recommended: Use via list-clusterapps-and-apps.sh
./scripts/list-clusterapps-and-apps.sh --generate-block-diagram

# Or run directly
python3 scripts/generate-clusterapp-block-diagram.py
```

The script will:
1. Fetch all ClusterApps from the management cluster
2. Parse dependency annotations (`apps.kommander.d2iq.io/dependencies` or `apps.kommander.d2iq.io/required-dependencies`)
3. Build dependency relationships
4. Generate a block diagram showing each app with its parents and children
5. Save output to `docs/internal/CLUSTERAPP-BLOCK-DIAGRAM.md` (not tracked in git)

### Output

The generated diagram shows:
- **Root chains**: Each root (app with no dependencies) starts its own chain
- **App blocks**: Each app appears once showing:
  - Parents (dependencies) above the block
  - Children (dependents) below the block
- **Visual structure**: ASCII art blocks with clear parent-child relationships

### Requirements

- Python 3.x
- kubectl configured with access to management cluster
- Kubeconfig file at: `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf`

### Use Cases

- **Release planning**: Understand dependency chains before upgrades
- **Troubleshooting**: Identify which apps depend on a failing component
- **Documentation**: Visual representation of ClusterApp relationships
- **Impact analysis**: See what apps are affected by changes to a dependency

### Example Output

The diagram organizes apps by root chains. For example:
- `cert-manager-1.18.2` [ROOT] → `traefik-37.1.2` → `traefik-forward-auth-0.3.16`
- `kube-prometheus-stack-78.4.0` [ROOT] → `istio-helm-1.23.6` → `jaeger-2.57.3`

### See Also

- `docs/CLUSTERAPP-DEPENDENCY-TREE.md` - Inverted dependency tree diagram
- `docs/internal/CLUSTERAPP-BLOCK-DIAGRAM.md` - Generated block diagram output (not tracked in git)
- `list-clusterapps-and-apps.sh` - List all ClusterApps and Apps

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

---

## sealed-secrets.sh

Unified script for managing sealed-secrets operations: backup, restore, encrypt, decrypt, re-encrypt, and status checking.

### Why Is This Needed?

Sealed-secrets keys are critical for decrypting sealed secrets. This unified script provides all necessary operations:
- **Backup**: Save keys for disaster recovery
- **Restore**: Restore keys from backup
- **Encrypt**: Create new sealed secrets
- **Decrypt**: View plaintext secrets (requires keys)
- **Re-encrypt**: Fix decryption failures by re-encrypting with current keys
- **Status**: Check sealed secret sync status

### Security

⚠️ **IMPORTANT**: Both public and private keys are stored locally and NEVER committed to git. They are stored in:
```
/Users/deepak.muley/ws/nkp/sealed-secrets-key-backup.yaml (private keys)
/Users/deepak.muley/ws/nkp/sealed-secrets-public-key.pem (public key)
```

These locations are protected by `.gitignore` patterns.

### Usage

```bash
# Show help
./scripts/sealed-secrets.sh --help

# Backup keys
./scripts/sealed-secrets.sh backup

# Restore keys
./scripts/sealed-secrets.sh restore

# Encrypt a secret
./scripts/sealed-secrets.sh encrypt -f secret.yaml -o sealed-secret.yaml

# Decrypt a sealed secret (requires keys)
./scripts/sealed-secrets.sh decrypt -f sealed-secret.yaml -o secret.yaml

# Re-encrypt secrets with current credentials
./scripts/sealed-secrets.sh re-encrypt

# Check status of sealed secrets
./scripts/sealed-secrets.sh status
```

### Commands

#### Backup

Backup sealed-secrets controller keys (public & private):

```bash
./scripts/sealed-secrets.sh backup
./scripts/sealed-secrets.sh backup -k /path/to/kubeconfig
./scripts/sealed-secrets.sh backup --help
```

#### Restore

Restore sealed-secrets keys from backup:

```bash
./scripts/sealed-secrets.sh restore
./scripts/sealed-secrets.sh restore -b /path/to/backup.yaml
./scripts/sealed-secrets.sh restore --force
./scripts/sealed-secrets.sh restore --help
```

#### Encrypt

Encrypt a plaintext Kubernetes Secret:

```bash
./scripts/sealed-secrets.sh encrypt -f secret.yaml -o sealed-secret.yaml
./scripts/sealed-secrets.sh encrypt -f secret.yaml -n my-namespace -o sealed-secret.yaml
./scripts/sealed-secrets.sh encrypt --help
```

#### Decrypt

Decrypt a SealedSecret (requires private keys):

```bash
./scripts/sealed-secrets.sh decrypt -f sealed-secret.yaml -o secret.yaml
./scripts/sealed-secrets.sh decrypt -f sealed-secret.yaml -b /path/to/backup.yaml -o secret.yaml
./scripts/sealed-secrets.sh decrypt --help
```

#### Re-encrypt

Re-encrypt secrets with new credentials. Automatically reads credentials from:
- PC credentials: `/Users/deepak.muley/ws/nkp/pc-creds.sh`
- DockerHub credentials: `/Users/deepak.muley/ws/nkp/nkp-mgmt-clusterctl.sh`

```bash
./scripts/sealed-secrets.sh re-encrypt
./scripts/sealed-secrets.sh re-encrypt -n dm-dev-workspace
./scripts/sealed-secrets.sh re-encrypt --help
```

This command:
1. Reads PC and DockerHub credentials from local files
2. Re-encrypts all 4 secrets using the current controller's public key:
   - `dm-dev-pc-credentials` (Prism Central JSON format)
   - `dm-dev-image-registry-credentials` (DockerHub)
   - `dm-dev-pc-credentials-for-csi` (Prism Central for CSI)
   - `dm-dev-pc-credentials-for-konnector-agent` (Prism Central for Konnector)
3. Applies the re-encrypted secrets to the cluster
4. Verifies they can be decrypted
5. Updates the sealed secrets file in git

#### Status

Check the sync status of sealed secrets:

```bash
./scripts/sealed-secrets.sh status
./scripts/sealed-secrets.sh status -n dm-dev-workspace
./scripts/sealed-secrets.sh status --help
```

---

## get-kubescape-cves.sh

Generate CVE reports from kubescape scans on management and workload clusters. Extracts vulnerabilities with severity filtering and generates Jira-friendly markdown reports.

### Usage

```bash
# Get all CVEs from management cluster (default)
./scripts/get-kubescape-cves.sh
./scripts/get-kubescape-cves.sh all mgmt

# Get critical CVEs from management cluster
./scripts/get-kubescape-cves.sh critical mgmt

# Get high severity CVEs from workload cluster 1
./scripts/get-kubescape-cves.sh high workload1

# Get critical CVEs from specific namespace(s)
./scripts/get-kubescape-cves.sh critical mgmt --namespace kommander
./scripts/get-kubescape-cves.sh high workload1 --namespace default,kube-system

# Get all CVEs from multiple namespaces
./scripts/get-kubescape-cves.sh all workload2 --namespace dm-dev-workspace,kommander

# Combine severity and namespace filters
./scripts/get-kubescape-cves.sh critical mgmt --namespace kommander,default
```

### Command Parameters

| Parameter | Options | Description | Default |
|-----------|---------|-------------|---------|
| `severity` | `all`, `critical`, `high`, `medium`, `low` | Filter CVEs by severity level | `all` |
| `cluster` | `mgmt`, `workload1`, `workload2` | Target cluster to scan | `mgmt` |
| `--namespace` | Comma-separated namespace list | Filter CVEs by namespace(s) | None (all namespaces) |

### What It Does

1. **Detects kubescape**: Checks for kubescape CLI or operator installation
2. **Scans cluster**: Runs kubescape scan or queries operator CRDs
3. **Filters by severity**: Extracts CVEs matching the specified severity level
4. **Filters by namespace**: Optionally filters CVEs by one or more namespaces
5. **Displays report**: Shows formatted CVE report in terminal
6. **Generates Jira report**: Creates markdown file ready for Jira upload

### Output

The script generates two outputs:

1. **Terminal Display**: Color-coded CVE report with:
   - Summary counts by severity
   - Detailed findings grouped by severity
   - Component information (namespace, kind, name, image)
   - CVE descriptions

2. **Jira Report File**: Markdown file named:
   ```
   kubescape-cve-report-{cluster}-{severity}-{timestamp}.md
   kubescape-cve-report-{cluster}-{severity}-ns-{namespaces}-{timestamp}.md  # When namespace filter is used
   ```

### Sample Output

```
════════════════════════════════════════════════════════════════
  CVE Report - Management Cluster (dm-nkp-mgmt-1) (Severity: CRITICAL)
════════════════════════════════════════════════════════════════

Summary:
  Critical: 5
  High: 12
  Medium: 8
  Low: 3

────────────────────────────────────────────────────────────────
🔴 CRITICAL
────────────────────────────────────────────────────────────────

CVE: CVE-2024-12345
Severity: critical
Component: nginx
Namespace: default
Kind: Pod
Image: nginx:1.21.0
Description: Remote code execution vulnerability in nginx
────────────────────────────────────────────────────────────────
```

### Jira Report Format

The generated markdown report includes:

- **Summary table** with CVE counts by severity
- **Detailed findings** in table format with:
  - CVE ID
  - Component name
  - Namespace
  - Resource kind
  - Container image
  - Description

### Requirements

- `kubectl` - Must be installed and configured
- `jq` - JSON processor (install via `brew install jq` on macOS)
- `kubescape` CLI (optional) - If not installed, script will try to use kubescape operator CRDs
- Access to cluster kubeconfig files

### Kubeconfig Locations

The script automatically uses the correct kubeconfig:

| Cluster | Kubeconfig Path |
|---------|-----------------|
| `mgmt` | `/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf` |
| `workload1` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig` |
| `workload2` | `/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig` |

### Installation

If kubescape CLI is not installed:

```bash
# macOS
brew install kubescape

# Linux
curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash

# Or visit: https://kubescape.io/docs/install-cli/
```

### Use Cases

- **Security audits**: Identify all critical CVEs across clusters
- **Namespace-specific scans**: Focus on CVEs in specific namespaces (e.g., production workloads)
- **Compliance reporting**: Generate CVE reports for compliance requirements
- **Jira tickets**: Upload markdown reports directly to Jira issues
- **Remediation planning**: Prioritize fixes based on severity and namespace
- **Component tracking**: Identify which components need updates
- **Multi-namespace analysis**: Compare CVEs across multiple namespaces

### Tips

- Run with `all` severity first to get a complete picture
- Use `critical` and `high` for immediate action items
- The Jira report can be copied directly into Jira markdown fields
- Reports are timestamped for tracking changes over time

---

## pod-security-audit.sh

Comprehensive pod security testing tool that performs container escape attempts, security hardening checks, and security context analysis. Generates detailed reports with security recommendations.

### Usage

```bash
# Run all tests (default)
./scripts/pod-security-audit.sh --namespace <ns> --pod <pod-name>
./scripts/pod-security-audit.sh -n kommander -p kommander-appmanagement-8cfbc8f4f-bs9fl

# Run specific test type
./scripts/pod-security-audit.sh --namespace default --pod my-pod --test-type escape
./scripts/pod-security-audit.sh -n kommander -p my-pod -t hardening
./scripts/pod-security-audit.sh --namespace default --pod my-pod --test-type context

# Specify kubeconfig
./scripts/pod-security-audit.sh --namespace default --pod my-pod --kubeconfig /path/to/kubeconfig
./scripts/pod-security-audit.sh -n kommander -p my-pod -k /Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf

# Export fixed YAML
./scripts/pod-security-audit.sh --namespace kommander --pod my-pod --export fixed-deployment.yaml
./scripts/pod-security-audit.sh -n default -p my-pod -o pod-fixed.yaml -k /path/to/kubeconfig

# Examples
./scripts/pod-security-audit.sh --namespace kommander --pod kommander-appmanagement-xxx --test-type all
./scripts/pod-security-audit.sh -n default -p test-pod -t escape -k /Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf
./scripts/pod-security-audit.sh -n kommander -p my-pod --export fixed.yaml
```

### Command Options

| Option | Short | Description | Required |
|--------|-------|-------------|----------|
| `--namespace` | `-n` | Kubernetes namespace | Yes |
| `--pod` | `-p` | Name of the pod to test | Yes |
| `--test-type` | `-t` | Type of test to run (escape, hardening, context, all) | No (default: all) |
| `--kubeconfig` | `-k` | Path to kubeconfig file | No |
| `--help` | `-h` | Show help message | No |

### Test Types

| Test Type | Description |
|-----------|-------------|
| `escape` | Attempts container escape techniques (nsenter, unshare, host filesystem access, etc.) |
| `hardening` | Checks security hardening (non-root, capabilities, seccomp, dangerous binaries) |
| `context` | Analyzes security context configuration (pod and container level) |
| `all` | Runs all tests plus generates security recommendations (default) |

### What It Tests

#### Escape Tests
- **Host namespace access**: Checks if pod can access host PID/IPC/network namespaces
- **nsenter escape**: Attempts to escape to host namespace using `nsenter`
- **User namespace privilege escalation**: Tests `unshare` for privilege escalation
- **Host filesystem access**: Checks access to host filesystem via `/proc/1/root`
- **Overlay filesystem inspection**: Examines overlay filesystem paths
- **Container runtime socket access**: Checks for Docker/containerd socket access
- **HostPath volume mounts**: Identifies hostPath volumes

#### Hardening Checks
- **Root execution**: Verifies container runs as non-root
- **Capabilities**: Checks if all capabilities are dropped
- **Dangerous binaries**: Identifies availability of `nsenter`, `chroot`, `mount`, `unshare`, etc.
- **Seccomp**: Verifies seccomp profile is enabled
- **NoNewPrivs**: Checks if NoNewPrivs is enabled

#### Security Context Analysis
- **Pod-level**: `runAsUser`, `runAsNonRoot`, `hostPID`, `hostIPC`, `hostNetwork`, `seccompProfile`
- **Container-level**: `privileged`, `allowPrivilegeEscalation`, `readOnlyRootFilesystem`, `capabilities`
- **Recommendations**: Generates YAML with recommended security context configuration

### Output

The script provides color-coded output:

- ✓ **Green (PASS)**: Security check passed
- ✗ **Red (FAIL)**: Security issue found
- ⚠ **Yellow (WARN)**: Potential security concern
- ℹ **Cyan (INFO)**: Informational message

### Sample Output

```
═══════════════════════════════════════════════════════════════
Security Context Analysis
═══════════════════════════════════════════════════════════════

Pod-Level Security Context:
✓ Pod runs as non-root (UID: 65532)
✓ hostPID is disabled
✓ hostIPC is disabled
✓ hostNetwork is disabled

Container-Level Security Context:
  Container: manager
✓ Container is not privileged
✓ Privilege escalation disabled
⚠ Root filesystem is writable
✓ Container drops 0 capabilities

═══════════════════════════════════════════════════════════════
Container Escape Attempts
═══════════════════════════════════════════════════════════════

Test 1: Host Namespace Access
✓ Cannot read host namespace symlinks (Permission denied)

Test 2: nsenter to Host Namespace
✓ nsenter escape blocked (Operation not permitted)

Test 3: User Namespace Privilege Escalation
⚠ Can create user namespace with root (UID 0) - partial privilege escalation
⚠ Can mount tmpfs in user namespace

Test 4: Host Filesystem Access
✓ Host filesystem access via /proc blocked

═══════════════════════════════════════════════════════════════
Security Recommendations
═══════════════════════════════════════════════════════════════

Recommended Security Context Configuration:

apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: default
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    ...
```

### Requirements

- `kubectl` - Must be installed and configured
- `jq` - JSON processor (install via `brew install jq` on macOS)
- Access to the target cluster

### Export Feature

The `--export` or `-o` option generates a YAML file with security fixes applied:

```bash
# Export fixed Deployment YAML
./scripts/pod-security-audit.sh -n kommander -p my-pod --export fixed-deployment.yaml

# Export fixed Pod YAML
./scripts/pod-security-audit.sh -n default -p my-pod -o pod-fixed.yaml
```

**What gets exported:**
- Automatically detects if pod is managed by Deployment, StatefulSet, or DaemonSet
- Applies security context fixes to both pod and container levels
- Removes runtime metadata (status, uid, resourceVersion, etc.)
- Ready to check in to GitOps repository after review

**Security fixes applied:**
- `runAsNonRoot: true` and appropriate `runAsUser`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true` (may need manual adjustment)
- `capabilities.drop: ["ALL"]`
- `seccompProfile.type: RuntimeDefault`
- `hostPID`, `hostIPC`, `hostNetwork: false`

**Note:** Review the exported YAML before applying, especially:
- `readOnlyRootFilesystem` may need to be `false` if the app requires writes
- Some apps may need specific capabilities (rare)
- Volume mounts and other configurations are preserved

### Use Cases

- **Security audits**: Comprehensive security assessment of pods
- **Compliance checks**: Verify pods meet security standards
- **Pre-deployment validation**: Test pods before production deployment
- **Incident response**: Investigate potential security breaches
- **Security training**: Understand container security boundaries
- **CI/CD integration**: Automate security checks in pipelines
- **GitOps integration**: Export fixed YAML for check-in to repository

### Tips

- Run with `all` first to get a complete security picture
- Use `escape` to test container isolation
- Use `hardening` for quick security posture check
- Use `context` to analyze and improve security configurations
- The recommendations section provides ready-to-use YAML for security improvements
- Use `--export` to generate fixed YAML ready for GitOps check-in
- All tests are non-destructive (read-only operations)
- Review exported YAML before applying, especially `readOnlyRootFilesystem`

---

## nkp-pentest-suite.sh

Comprehensive penetration testing suite for NKP Kubernetes clusters. Performs automated security testing across multiple phases including discovery, credential extraction, RBAC testing, security context analysis, network security, and Nutanix component-specific tests.

### Why Is This Needed?

Regular security testing is critical for maintaining a secure Kubernetes platform. This script automates:
- Discovery of all cluster resources and components
- Identification of security misconfigurations
- Testing of RBAC permissions
- Analysis of security contexts
- Network security assessment
- Nutanix component-specific security testing

### Usage

```bash
# Run full pentest suite (uses default kubeconfig)
./scripts/nkp-pentest-suite.sh

# Test specific namespace
./scripts/nkp-pentest-suite.sh --namespace dm-dev-workspace

# Use specific kubeconfig
./scripts/nkp-pentest-suite.sh --kubeconfig /path/to/kubeconfig

# Custom output directory
./scripts/nkp-pentest-suite.sh --output ./my-pentest-results

# Verbose output
./scripts/nkp-pentest-suite.sh --verbose

# Combine options
./scripts/nkp-pentest-suite.sh \
  --kubeconfig /Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf \
  --namespace kommander \
  --output ./kommander-pentest \
  --verbose

# Help
./scripts/nkp-pentest-suite.sh --help
```

### Command Options

| Option | Description |
|--------|-------------|
| `--kubeconfig <path>` | Path to kubeconfig file |
| `--namespace <ns>` | Target specific namespace (default: all namespaces) |
| `--output <dir>` | Output directory for results (default: `./pentest-results-YYYYMMDD-HHMMSS`) |
| `--verbose, -v` | Enable verbose output |
| `--help, -h` | Show help message |

### Testing Phases

The script runs 6 comprehensive testing phases:

#### Phase 1: Discovery
- Cluster information and node enumeration
- Namespace discovery
- Pod and service enumeration
- Service account discovery
- Nutanix component identification (Kommander, CAPX, CAREN, etc.)

#### Phase 2: Credential Extraction
- Secret enumeration across all namespaces
- Nutanix-specific credential discovery (Prism Central, CCM, CSI)
- Service account token extraction
- Sealed secrets identification

#### Phase 3: RBAC Testing
- Cluster role and role binding analysis
- Cluster-admin binding identification
- Wildcard permission detection
- Service account permission testing
- Cross-namespace access testing

#### Phase 4: Security Context Testing
- Privileged container identification
- Host network pod discovery
- Host path volume enumeration
- Dangerous capability detection
- Root container identification

#### Phase 5: Network Security Testing
- Network policy analysis
- Exposed service identification (LoadBalancer, NodePort)
- External IP detection
- Ingress resource analysis

#### Phase 6: Nutanix Component-Specific Tests
- Kommander security analysis
- CAPX (Cluster API Provider) testing
- CAREN (Runtime Extensions) webhook analysis
- Nutanix CCM credential testing
- Nutanix CSI security assessment

### Output

The script generates comprehensive reports in the output directory:

```
pentest-results-20250127-143022/
├── pentest.log                    # Full execution log
├── SUMMARY.txt                    # Executive summary
├── cluster-info.txt               # Cluster information
├── nodes.txt                      # Node details
├── namespaces.json                # All namespaces
├── pods.json                      # All pods (JSON)
├── pods.txt                       # All pods (readable)
├── services.json                  # All services
├── services.txt                   # All services (readable)
├── serviceaccounts.json           # All service accounts
├── secrets.json                   # All secrets
├── secrets.txt                    # All secrets (readable)
├── nutanix-components.txt         # Nutanix component inventory
├── nutanix-secrets.txt            # Nutanix credential locations
├── sa-tokens.txt                  # Service account tokens
├── clusterroles.json              # Cluster roles
├── clusterrolebindings.json       # Cluster role bindings
├── rbac-analysis.txt              # RBAC findings
├── sa-permissions.txt             # Service account permissions
├── privileged-pods.txt            # Privileged containers
├── hostnetwork-pods.txt           # Host network pods
├── hostpath-volumes.txt           # Host path volumes
├── dangerous-capabilities.txt      # Dangerous capabilities
├── root-containers.txt            # Root containers
├── security-context-summary.txt   # Security context summary
├── networkpolicies.json           # Network policies
├── networkpolicies.txt            # Network policies (readable)
├── exposed-services.txt           # Exposed services
├── ingress.json                   # Ingress resources
├── ingress.txt                   # Ingress resources (readable)
├── kommander-analysis.txt         # Kommander security analysis
├── capx-analysis.txt             # CAPX security analysis
├── caren-analysis.txt            # CAREN security analysis
├── ccm-analysis.txt              # CCM security analysis
└── csi-analysis.txt              # CSI security analysis
```

### Sample Output

```
[INFO] Starting NKP Penetration Testing Suite
[INFO] Output directory: ./pentest-results-20250127-143022
[SUCCESS] Prerequisites check passed
[INFO] === Phase 1: Discovery ===
[INFO] Collecting cluster information...
[INFO] Enumerating namespaces...
[SUCCESS] Discovery phase complete
[INFO] === Phase 2: Credential Extraction ===
[INFO] Enumerating secrets...
[INFO] Searching for Nutanix credentials...
[SUCCESS] Credential extraction phase complete
...
[SUCCESS] Penetration testing suite complete!
[INFO] Results available in: ./pentest-results-20250127-143022
[WARN] Review findings and remediate security issues
```

### Summary Report

The `SUMMARY.txt` file provides an executive overview:

```
=== NKP Penetration Testing Summary ===
Date: 2025-01-27 14:30:22
Cluster: dm-nkp-mgmt-1

=== Findings Summary ===

Discovery:
  - Namespaces: 25
  - Pods: 156
  - Services: 89

Security Issues:
  - Privileged Pods: 12
  - Host Network Pods: 8
  - Root Containers: 45
  - Dangerous Capabilities: 23

RBAC:
  - Cluster Admin Bindings: 3

Network:
  - LoadBalancer Services: 5
  - NodePort Services: 2
```

### Requirements

- `kubectl` - Must be installed and configured
- `jq` - JSON processor (install via `brew install jq` on macOS)
- Access to target cluster via kubeconfig

### Use Cases

- **Security audits**: Comprehensive security assessment of NKP clusters
- **Compliance checks**: Verify clusters meet security standards
- **Pre-deployment validation**: Test clusters before production
- **Incident response**: Investigate potential security breaches
- **Regular security reviews**: Scheduled security assessments
- **Nutanix component security**: Focused testing on NKP components

### Integration with Other Tools

The pentest suite complements other security tools:

```bash
# Run pentest suite
./scripts/nkp-pentest-suite.sh

# Then run kubescape for CVE scanning
kubescape scan framework nsa

# Run kubeaudit for additional checks
kubeaudit all

# Check policy violations
./scripts/check-violations.sh mgmt
```

### Tips

- Run regularly (e.g., monthly) to track security posture over time
- Compare results across clusters to identify patterns
- Focus on critical findings first (privileged pods, cluster-admin bindings)
- Use namespace filtering for targeted testing
- Review Nutanix component-specific findings carefully
- Integrate into CI/CD pipelines for automated security testing

### See Also

- `docs/BLACK-HAT-PENETRATION-TESTING-GUIDE.md` - Comprehensive penetration testing guide
- `docs/PENTEST-QUICK-REFERENCE.md` - Quick reference for common tests
- `docs/SECURITY-FIX-VALIDATION-GUIDE.md` - Guide on validating security fixes
- `check-violations.sh` - Check Gatekeeper policy violations
- `pod-security-audit.sh` - Individual pod security testing

---

## Legal Disclaimer

⚠️ **IMPORTANT**: The penetration testing suite (`nkp-pentest-suite.sh`) is for authorized security testing only. Unauthorized access to computer systems is illegal and may result in criminal prosecution. Always obtain written authorization before performing penetration testing.
