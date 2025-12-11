# CAREN Workarounds

⚠️ **These are manual workaround tools, NOT part of the GitOps workflow.**

## Background

During cluster provisioning, CAREN (Cluster API Runtime Extensions Nutanix) is responsible for deploying cluster addons like Cilium CNI, Nutanix CCM, and CSI via the `AfterControlPlaneInitialized` runtime hook.

However, the webhook timeout (10 seconds) can sometimes be too short, causing the hook to fail with:
```
context deadline exceeded
```

When this happens, critical addons are never deployed, leaving workload clusters in a broken state with:
- Nodes stuck in `NotReady` status (no CNI)
- Nodes with `uninitialized` taints (no CCM)
- No persistent storage (no CSI)
- Pods stuck in `Pending` state

## When to Use These Tools

**Only use these if:**
1. Workload cluster nodes are `NotReady` for extended periods
2. Cilium pods don't exist on the workload cluster
3. CCM pods don't exist on the workload cluster
4. CSI pods don't exist on the workload cluster
5. Cluster topology shows `TopologyReconcileFailed` with timeout errors

## Files

| File | Purpose | Order |
|------|---------|-------|
| `cilium-helmchartproxy.yaml` | Cilium CNI for networking | 1st |
| `nutanix-ccm-helmchartproxy.yaml` | Nutanix CCM for node management | 2nd |
| `snapshot-controller-helmchartproxy.yaml` | VolumeSnapshot CRDs (required by CSI) | 3rd |
| `nutanix-csi-helmchartproxy.yaml` | Nutanix CSI for persistent storage | 4th |

## Deployment Order

**IMPORTANT:** Deploy in this order:
1. Cilium (CNI) - enables pod networking
2. CCM - removes node taints, enables scheduling
3. Snapshot Controller - installs VolumeSnapshot CRDs
4. CSI - enables persistent storage

## Usage

### 1. Apply Cilium HelmChartProxy

```bash
kubectl apply -f tools/caren-workarounds/cilium-helmchartproxy.yaml
```

### 2. Create CCM Credentials & Apply HelmChartProxy

```bash
# Get credentials from management cluster
CREDS=$(kubectl get secret dm-nkp-workload-1-pc-credentials -n dm-dev-workspace -o jsonpath='{.data.credentials}')

# Create on workload cluster
cat << EOF | kubectl apply --kubeconfig=/path/to/workload.kubeconfig -f -
apiVersion: v1
kind: Secret
metadata:
  name: nutanix-ccm-credentials
  namespace: kube-system
type: Opaque
data:
  credentials: $CREDS
EOF

# Apply CCM HelmChartProxy
kubectl apply -f tools/caren-workarounds/nutanix-ccm-helmchartproxy.yaml
```

### 3. Apply Snapshot Controller

```bash
kubectl apply -f tools/caren-workarounds/snapshot-controller-helmchartproxy.yaml
```

### 4. Create CSI Credentials & Apply HelmChartProxy

```bash
# Get CSI credentials (different format than CCM!)
CSI_KEY=$(kubectl get secret nutanix-csi-credentials -n ntnx-system -o jsonpath='{.data.key}')

# Create namespace and secret on workload cluster
kubectl create namespace ntnx-system --kubeconfig=/path/to/workload.kubeconfig

cat << EOF | kubectl apply --kubeconfig=/path/to/workload.kubeconfig -f -
apiVersion: v1
kind: Secret
metadata:
  name: nutanix-csi-credentials
  namespace: ntnx-system
type: Opaque
data:
  key: $CSI_KEY
EOF

# Apply CSI HelmChartProxy
kubectl apply -f tools/caren-workarounds/nutanix-csi-helmchartproxy.yaml
```

### 5. Verify

```bash
# Check nodes become Ready
kubectl get nodes --kubeconfig=/path/to/workload.kubeconfig

# Check Cilium pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium --kubeconfig=/path/to/workload.kubeconfig

# Check CCM pods
kubectl get pods -n kube-system | grep nutanix-cloud --kubeconfig=/path/to/workload.kubeconfig

# Check Snapshot Controller
kubectl get pods -n kube-system | grep snapshot --kubeconfig=/path/to/workload.kubeconfig

# Check CSI pods
kubectl get pods -n ntnx-system --kubeconfig=/path/to/workload.kubeconfig
```

## Credential Formats

### CCM Credentials
- Secret name: `nutanix-ccm-credentials`
- Namespace: `kube-system`
- Key: `credentials`
- Format: JSON with Prism Central auth

### CSI Credentials
- Secret name: `nutanix-csi-credentials`
- Namespace: `ntnx-system`
- Key: `key`
- Format: `<prism-central-host>:<port>:<username>:<password>`

## Customization

When adding new workload clusters, update each YAML file:

1. Add new `HelmChartProxy` resource
2. Update `clusterSelector.matchLabels` with cluster name
3. For Cilium: Update `k8sServiceHost` with control plane VIP
4. For CCM: Update `ignoredNodeIPs` with control plane VIP

## Reporting the Issue

If you consistently experience CAREN timeout issues, consider reporting to the NKP team with:
1. CAREN pod logs: `kubectl logs -n caren-system -l app.kubernetes.io/name=cluster-api-runtime-extensions-nutanix`
2. Cluster topology status: `kubectl get cluster <name> -n <namespace> -o yaml`
3. Time taken for cluster provisioning
