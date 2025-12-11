# CAREN Workarounds

⚠️ **These are manual workaround tools, NOT part of the GitOps workflow.**

## Background

During cluster provisioning, CAREN (Cluster API Runtime Extensions Nutanix) is responsible for deploying cluster addons like Cilium CNI and Nutanix CCM via the `AfterControlPlaneInitialized` runtime hook.

However, the webhook timeout (10 seconds) can sometimes be too short, causing the hook to fail with:
```
context deadline exceeded
```

When this happens, critical addons like Cilium and CCM are never deployed, leaving workload clusters in a broken state with:
- Nodes stuck in `NotReady` status
- No CNI networking
- Pods stuck in `Pending` state

## When to Use These Tools

**Only use these if:**
1. Workload cluster nodes are `NotReady` for extended periods
2. Cilium pods don't exist on the workload cluster
3. CCM pods don't exist on the workload cluster
4. Cluster topology shows `TopologyReconcileFailed` with timeout errors

## Files

| File | Purpose |
|------|---------|
| `cilium-helmchartproxy.yaml` | Creates Cilium CNI HelmChartProxy for workload clusters |
| `nutanix-ccm-helmchartproxy.yaml` | Creates Nutanix CCM HelmChartProxy for workload clusters |

## Usage

### 1. Apply Cilium HelmChartProxy

```bash
# Apply to management cluster
kubectl apply -f tools/caren-workarounds/cilium-helmchartproxy.yaml
```

### 2. Create CCM Credentials Secret

Before applying CCM, create the credentials secret on each workload cluster:

```bash
# Get credentials from management cluster
CREDS=$(kubectl get secret dm-nkp-workload-1-pc-credentials -n dm-dev-workspace -o jsonpath='{.data.credentials}')

# Create on workload cluster
cat << EOF | kubectl apply --kubeconfig=/path/to/workload-1.kubeconfig -f -
apiVersion: v1
kind: Secret
metadata:
  name: nutanix-ccm-credentials
  namespace: kube-system
type: Opaque
data:
  credentials: $CREDS
EOF
```

### 3. Apply CCM HelmChartProxy

```bash
# Apply to management cluster
kubectl apply -f tools/caren-workarounds/nutanix-ccm-helmchartproxy.yaml
```

### 4. Verify

```bash
# Check nodes become Ready
kubectl get nodes --kubeconfig=/path/to/workload.kubeconfig

# Check Cilium pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium --kubeconfig=/path/to/workload.kubeconfig

# Check CCM pods
kubectl get pods -n kube-system | grep nutanix-cloud --kubeconfig=/path/to/workload.kubeconfig
```

## Customization

When adding new workload clusters, update the YAML files:

### Cilium
- Add new `HelmChartProxy` resource
- Update `clusterSelector.matchLabels` with cluster name
- Update `k8sServiceHost` with control plane VIP

### CCM
- Add new `HelmChartProxy` resource
- Update `clusterSelector.matchLabels` with cluster name
- Update `ignoredNodeIPs` with control plane VIP

## Reporting the Issue

If you consistently experience CAREN timeout issues, consider reporting to the NKP team with:
1. CAREN pod logs: `kubectl logs -n caren-system -l app.kubernetes.io/name=cluster-api-runtime-extensions-nutanix`
2. Cluster topology status: `kubectl get cluster <name> -n <namespace> -o yaml`
3. Time taken for cluster provisioning
