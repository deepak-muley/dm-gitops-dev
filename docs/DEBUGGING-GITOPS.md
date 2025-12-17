# GitOps Debugging Guide

Comprehensive guide for debugging Flux GitOps issues, Kustomization dependencies, and common problems.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Flux Kustomization Status](#flux-kustomization-status)
- [Dependency Debugging](#dependency-debugging)
- [Kustomize Build Issues](#kustomize-build-issues)
- [Sealed Secrets Issues](#sealed-secrets-issues)
- [CAPI Cluster Issues](#capi-cluster-issues)
- [Git Repository Issues](#git-repository-issues)
- [Common Errors and Solutions](#common-errors-and-solutions)
- [Advanced Debugging](#advanced-debugging)

---

## Quick Diagnostics

### One-liner Health Check

```bash
# Management cluster quick status
export KUBECONFIG=/path/to/mgmt-cluster.conf
kubectl get kustomization -n dm-nkp-gitops-infra -o wide && \
kubectl get gitrepository -n kommander && \
kubectl get sealedsecrets -n dm-dev-workspace
```

### Full System Check Script

```bash
#!/bin/bash
export KUBECONFIG=/path/to/mgmt-cluster.conf

echo "=== GitRepository Status ==="
kubectl get gitrepository -n kommander -o wide

echo -e "\n=== Kustomization Status ==="
kubectl get kustomization -n dm-nkp-gitops-infra -o wide

echo -e "\n=== Failed Kustomizations ==="
kubectl get kustomization -n dm-nkp-gitops-infra -o json | \
  jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="False")) | .metadata.name'

echo -e "\n=== Sealed Secrets Status ==="
kubectl get sealedsecrets -n dm-dev-workspace

echo -e "\n=== CAPI Clusters ==="
kubectl get clusters -A

echo -e "\n=== Recent Events ==="
kubectl get events -n dm-nkp-gitops-infra --sort-by='.lastTimestamp' | tail -20
```

---

## Flux Kustomization Status

### List All Kustomizations with Status

```bash
# Basic status
kubectl get kustomization -n dm-nkp-gitops-infra

# Detailed status with conditions
kubectl get kustomization -n dm-nkp-gitops-infra -o wide

# JSON output for scripting
kubectl get kustomization -n dm-nkp-gitops-infra -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.status.conditions[] | select(.type=="Ready") | .status) - \(.status.conditions[] | select(.type=="Ready") | .reason)"'
```

### Check Specific Kustomization

```bash
# Full YAML status
kubectl get kustomization clusterops-clusters -n dm-nkp-gitops-infra -o yaml

# Just the status message
kubectl get kustomization clusterops-clusters -n dm-nkp-gitops-infra \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'

# Check last applied revision
kubectl get kustomization clusterops-clusters -n dm-nkp-gitops-infra \
  -o jsonpath='{.status.lastAppliedRevision}'
```

### Check Kustomization Events

```bash
kubectl describe kustomization clusterops-clusters -n dm-nkp-gitops-infra | tail -30
```

### Force Reconciliation

```bash
# Using flux CLI
flux reconcile kustomization clusterops-clusters -n dm-nkp-gitops-infra

# Using kubectl annotation (if flux CLI not available)
kubectl annotate kustomization clusterops-clusters -n dm-nkp-gitops-infra \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite

# Reconcile the source first, then kustomization
flux reconcile source git gitops-usa-az1 -n kommander
flux reconcile kustomization clusterops-clusters -n dm-nkp-gitops-infra
```

---

## Dependency Debugging

### View Dependency Graph

```bash
# List all kustomizations with their dependencies
kubectl get kustomization -n dm-nkp-gitops-infra \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.dependsOn}{"\n"}{end}'

# Pretty print dependencies
kubectl get kustomization -n dm-nkp-gitops-infra -o json | \
  jq -r '.items[] | "\(.metadata.name) depends on: \(.spec.dependsOn // [] | map(.name) | join(", "))"'
```

### Find Blocked Kustomizations

```bash
# Find kustomizations waiting on dependencies
kubectl get kustomization -n dm-nkp-gitops-infra -o json | \
  jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .reason=="DependencyNotReady")) | "\(.metadata.name): \(.status.conditions[] | select(.type=="Ready") | .message)"'
```

### Check Dependency Chain

```bash
# Check if a specific dependency is ready
DEPENDENCY="clusterops-sealed-secrets"
kubectl get kustomization $DEPENDENCY -n dm-nkp-gitops-infra \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Recursively check all dependencies for a kustomization
check_deps() {
  local ks=$1
  echo "Checking: $ks"
  deps=$(kubectl get kustomization $ks -n dm-nkp-gitops-infra \
    -o jsonpath='{.spec.dependsOn[*].name}')
  for dep in $deps; do
    status=$(kubectl get kustomization $dep -n dm-nkp-gitops-infra \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    echo "  $dep: $status"
    check_deps $dep
  done
}
check_deps clusterops-clusters
```

---

## Kustomize Build Issues

### Local Kustomize Build Test

```bash
# Build and check output
cd /path/to/dm-nkp-gitops-infra
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0

# Build and validate against cluster (dry-run)
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0 | \
  kubectl apply --dry-run=server -f -

# Build specific resource and check
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0 | \
  yq 'select(.metadata.name == "dm-nkp-workload-1" and .kind == "Cluster")'
```

### Debug Kustomize Patches

```bash
# Show what patches are being applied
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0 --enable-alpha-plugins 2>&1 | head -100

# Compare base vs overlay output
echo "=== BASE ===" && \
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/bases | \
  yq 'select(.kind == "Cluster")' | head -50

echo "=== OVERLAY ===" && \
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0 | \
  yq 'select(.kind == "Cluster")' | head -50
```

### Validate YAML Syntax

```bash
# Check YAML syntax
yamllint region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/bases/*.yaml

# Validate Kubernetes manifests
kustomize build . | kubeval --strict

# Check for common issues
kustomize build . | kubectl apply --dry-run=client -f - 2>&1 | grep -i error
```

### Check Field Retention (JSON Patch vs Strategic Merge)

```bash
# Verify specific fields are preserved after patch
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0 | \
  yq 'select(.metadata.name == "dm-nkp-workload-1" and .kind == "Cluster") | .spec.topology.variables[0].value.imageRegistries'
```

---

## Sealed Secrets Issues

### Check Sealed Secrets Controller

```bash
# Controller status
kubectl get pods -n sealed-secrets-system
kubectl logs -n sealed-secrets-system -l app.kubernetes.io/name=sealed-secrets --tail=50

# Check controller keys
kubectl get secrets -n sealed-secrets-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active
```

### Check SealedSecret Decryption Status

```bash
# List all sealed secrets with sync status
kubectl get sealedsecrets -n dm-dev-workspace

# Check specific sealed secret
kubectl get sealedsecret dm-nkp-workload-1-pc-credentials -n dm-dev-workspace -o yaml

# Check if corresponding secret exists
kubectl get secret dm-nkp-workload-1-pc-credentials -n dm-dev-workspace
```

### Debug Decryption Failures

```bash
# Check sealed secret events
kubectl describe sealedsecret dm-nkp-workload-1-pc-credentials -n dm-dev-workspace

# Common error: "no key could decrypt secret"
# This means the controller's key doesn't match the key used to encrypt

# Solution: Restore the original key
kubectl apply -f /path/to/sealed-secrets-key-backup.yaml
kubectl rollout restart deployment -n sealed-secrets-system sealed-secrets-controller
```

### Re-seal Secrets with Current Controller Key

```bash
# Fetch current public key
kubeseal --fetch-cert > sealed-secrets-cert.pem

# Re-seal a secret
kubectl create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=secret \
  --dry-run=client -o yaml | \
  kubeseal --cert sealed-secrets-cert.pem -o yaml > my-sealed-secret.yaml
```

---

## CAPI Cluster Issues

### Check CAPI Cluster Status

```bash
# List all clusters
kubectl get clusters -A

# Detailed cluster status
kubectl get cluster dm-nkp-workload-1 -n dm-dev-workspace -o yaml

# Check cluster conditions
kubectl get cluster dm-nkp-workload-1 -n dm-dev-workspace \
  -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}'
```

### Debug Preflight Webhook Failures

```bash
# Test cluster creation with dry-run
kustomize build region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/nutanix-infra/overlays/2.17.0 | \
  yq 'select(.metadata.name == "dm-nkp-workload-1" and .kind == "Cluster")' | \
  kubectl apply --dry-run=server -f -

# Check CAREN logs for preflight errors
kubectl logs -n caren-system -l app.kubernetes.io/name=caren --tail=100 | \
  grep -i "preflight\|error\|failed"

# Common preflight errors:
# - "invalid Nutanix credentials" - check pc-credentials secret
# - "CSI providers required" - check CSI configuration in cluster spec
```

### Check CAPI Provider Status

```bash
# Nutanix provider (CAPX)
kubectl get pods -n capx-system
kubectl logs -n capx-system -l cluster.x-k8s.io/provider=infrastructure-nutanix --tail=50

# Docker provider (CAPD)
kubectl get pods -n capd-system
kubectl logs -n capd-system -l cluster.x-k8s.io/provider=infrastructure-docker --tail=50

# Kubemark provider (CAPK)
kubectl get pods -n capk-system
kubectl logs -n capk-system -l control-plane=controller-manager --tail=50
```

### Check Machine Status

```bash
# List machines for a cluster
kubectl get machines -n dm-dev-workspace -l cluster.x-k8s.io/cluster-name=dm-nkp-workload-1

# Check machine deployment
kubectl get machinedeployment -n dm-dev-workspace

# Check machine health
kubectl get machinehealthcheck -n dm-dev-workspace
```

---

## Git Repository Issues

### Check GitRepository Status

```bash
# List git repositories
kubectl get gitrepository -n kommander

# Check specific repository
kubectl get gitrepository gitops-usa-az1 -n kommander -o yaml

# Check last fetched revision
kubectl get gitrepository gitops-usa-az1 -n kommander \
  -o jsonpath='{.status.artifact.revision}'
```

### Force Git Fetch

```bash
# Reconcile git source
flux reconcile source git gitops-usa-az1 -n kommander

# Or using annotation
kubectl annotate gitrepository gitops-usa-az1 -n kommander \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

### Debug Git Authentication Issues

```bash
# Check source controller logs
kubectl logs -n kommander-flux deploy/source-controller --tail=50

# Common errors:
# - "authentication required" - check deploy key or credentials
# - "repository not found" - check URL
# - "permission denied" - check SSH key permissions
```

---

## Common Errors and Solutions

### Error: "dependency 'X' is not ready"

```bash
# Diagnosis
kubectl get kustomization X -n dm-nkp-gitops-infra -o yaml | grep -A 20 "status:"

# Solutions:
# 1. Check if dependency exists
kubectl get kustomization X -n dm-nkp-gitops-infra

# 2. Force reconcile the dependency
flux reconcile kustomization X -n dm-nkp-gitops-infra

# 3. Check for circular dependencies
kubectl get kustomization -n dm-nkp-gitops-infra -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.spec.dependsOn)"'
```

### Error: "dry-run failed" / "preflight checks failed"

```bash
# Get full error message
kubectl get kustomization clusterops-clusters -n dm-nkp-gitops-infra \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'

# Test locally
kustomize build <path> | kubectl apply --dry-run=server -f - 2>&1

# Common causes:
# - Invalid credentials (sealed secrets issue)
# - Missing required fields (check ClusterClass requirements)
# - CRD not installed
```

### Error: "no key could decrypt secret"

```bash
# Check current controller keys
kubectl get secrets -n sealed-secrets-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active

# Restore backup key
kubectl apply -f /path/to/sealed-secrets-key-backup.yaml --force
kubectl rollout restart deployment -n sealed-secrets-system sealed-secrets-controller

# Wait for controller restart
kubectl rollout status deployment -n sealed-secrets-system sealed-secrets-controller
```

### Error: "invalid Nutanix credentials"

```bash
# Check the decrypted secret
kubectl get secret dm-nkp-workload-1-pc-credentials -n dm-dev-workspace \
  -o jsonpath='{.data.credentials}' | base64 -d | jq .

# Re-seal with correct credentials
cat > /tmp/pc-creds.json << 'EOF'
[{"type":"basic_auth","data":{"prismCentral":{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD"}}}]
EOF

kubectl create secret generic dm-nkp-workload-1-pc-credentials \
  --from-file=credentials=/tmp/pc-creds.json \
  --dry-run=client -o yaml | \
  kubeseal --cert sealed-secrets-cert.pem -o yaml > new-sealed-secret.yaml
```

### Error: "path not found" in Kustomization

```bash
# Check the path exists in the repo
ls -la region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/

# Check gitrepository is up to date
kubectl get gitrepository gitops-usa-az1 -n kommander \
  -o jsonpath='{.status.artifact.revision}'

# Compare with actual git HEAD
git rev-parse HEAD
```

---

## Advanced Debugging

### Watch Flux Events in Real-time

```bash
# Watch all flux events
kubectl get events -n dm-nkp-gitops-infra --watch

# Watch kustomization changes
watch -n 5 'kubectl get kustomization -n dm-nkp-gitops-infra -o wide'
```

### Check Flux Controller Logs

```bash
# Source controller (git operations)
kubectl logs -n kommander-flux deploy/source-controller -f --tail=100

# Kustomize controller (reconciliation)
kubectl logs -n kommander-flux deploy/kustomize-controller -f --tail=100

# Filter for errors
kubectl logs -n kommander-flux deploy/kustomize-controller --tail=500 | grep -i error
```

### Export Full Flux State

```bash
# Export all flux resources
kubectl get gitrepository,kustomization -A -o yaml > flux-state.yaml

# Export with status
flux export all > flux-export.yaml
```

### Trace Reconciliation

```bash
# Enable debug logging (temporarily)
kubectl patch deployment kustomize-controller -n kommander-flux \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--log-level=debug"}]'

# Watch logs
kubectl logs -n kommander-flux deploy/kustomize-controller -f | grep "dm-nkp-workload"
```

### Suspend/Resume Reconciliation

```bash
# Suspend (stop reconciliation)
flux suspend kustomization clusterops-clusters -n dm-nkp-gitops-infra

# Resume
flux resume kustomization clusterops-clusters -n dm-nkp-gitops-infra

# Suspend all
flux suspend kustomization --all -n dm-nkp-gitops-infra
```

### Compare Desired vs Actual State

```bash
# Show what would be applied
kustomize build <path> > desired.yaml

# Show what's currently applied
kubectl get -f desired.yaml -o yaml > actual.yaml

# Diff
diff -u actual.yaml desired.yaml
```

---

## Useful Aliases

Add these to your `.bashrc` or `.zshrc`:

```bash
# Flux shortcuts
alias fks='kubectl get kustomization -n dm-nkp-gitops-infra'
alias fgr='kubectl get gitrepository -n kommander'
alias fss='kubectl get sealedsecrets -n dm-dev-workspace'
alias fcl='kubectl get clusters -A'

# Reconcile shortcuts
alias frks='flux reconcile kustomization -n dm-nkp-gitops-infra'
alias frgr='flux reconcile source git gitops-usa-az1 -n kommander'

# Debug shortcuts
alias flog='kubectl logs -n kommander-flux deploy/kustomize-controller --tail=100'
alias ferr='kubectl get kustomization -n dm-nkp-gitops-infra -o json | jq -r ".items[] | select(.status.conditions[] | select(.type==\"Ready\" and .status==\"False\")) | .metadata.name"'
```

---

## Quick Reference Card

| Task | Command |
|------|---------|
| Check all kustomizations | `kubectl get ks -n dm-nkp-gitops-infra` |
| Force reconcile | `flux reconcile ks <name> -n dm-nkp-gitops-infra` |
| Check git source | `kubectl get gitrepo -n kommander` |
| Force git fetch | `flux reconcile source git gitops-usa-az1 -n kommander` |
| Check sealed secrets | `kubectl get sealedsecrets -n dm-dev-workspace` |
| Check clusters | `kubectl get clusters -A` |
| View kustomize output | `kustomize build <path>` |
| Dry-run apply | `kustomize build <path> \| kubectl apply --dry-run=server -f -` |
| Check flux logs | `kubectl logs -n kommander-flux deploy/kustomize-controller` |
| Watch reconciliation | `watch kubectl get ks -n dm-nkp-gitops-infra` |

