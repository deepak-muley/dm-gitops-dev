# Kubesec Score Improvement: Before vs After

This document shows the specific changes needed to improve the kommander-appmanagement deployment from 8/9 to 9/9 kubesec score.

## Current State (8/9 Score)

The exported YAML already has most security features, but is missing:
1. **AppArmor profiles** (annotation + securityContext)
2. **automountServiceAccountToken: false** (if not needed)
3. **hostUsers: false** (Kubernetes 1.25+)

## Changes Needed

### Change 1: Add AppArmor Annotations

**Add to Deployment metadata:**
```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/manager: runtime/default
    container.apparmor.security.beta.kubernetes.io/kube-rbac-proxy: runtime/default
```

**Add to Pod template metadata:**
```yaml
spec:
  template:
    metadata:
      annotations:
        container.apparmor.security.beta.kubernetes.io/manager: runtime/default
        container.apparmor.security.beta.kubernetes.io/kube-rbac-proxy: runtime/default
```

**Add to securityContext (pod and container level):**
```yaml
spec:
  template:
    spec:
      securityContext:
        appArmorProfile:
          type: RuntimeDefault
      containers:
      - name: manager
        securityContext:
          appArmorProfile:
            type: RuntimeDefault
```

### Change 2: Disable ServiceAccount Token Automount

**Add to pod spec:**
```yaml
spec:
  template:
    spec:
      automountServiceAccountToken: false
```

**⚠️ Important:** Only set this to `false` if the pod doesn't need Kubernetes API access. If `kommander-appmanagement` needs to call the Kubernetes API, keep this as `true` or omit it.

### Change 3: Enable User Namespaces

**Add to pod spec:**
```yaml
spec:
  template:
    spec:
      hostUsers: false
```

**⚠️ Requirements:**
- Kubernetes 1.25+ (alpha in 1.25, beta in 1.28)
- Container runtime support (containerd 1.7+, CRI-O 1.25+)
- Feature gate enabled (if using alpha)

### Change 4: Update Group IDs to >10000

**Current:**
```yaml
runAsGroup: 65532
fsGroup: 65532
```

**Optional change to:**
```yaml
runAsGroup: 65534  # Traditional "nobody" group
fsGroup: 65534
```

**Note:**
- Both 65532 and 65534 satisfy kubesec's requirement (`>10000`) and get the same score
- 65534 is the traditional Linux "nobody" group (standard convention)
- 65532 is Alpine Linux's "nobody" group
- **You don't need to change from 65532 to 65534** - both work! The change is optional and mainly for standardization

## Complete Diff

```diff
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kommander-appmanagement
+  annotations:
+    container.apparmor.security.beta.kubernetes.io/manager: runtime/default
+    container.apparmor.security.beta.kubernetes.io/kube-rbac-proxy: runtime/default
spec:
  template:
    metadata:
+      annotations:
+        container.apparmor.security.beta.kubernetes.io/manager: runtime/default
+        container.apparmor.security.beta.kubernetes.io/kube-rbac-proxy: runtime/default
    spec:
+      automountServiceAccountToken: false  # Only if not needed
+      hostUsers: false  # Requires K8s 1.25+
      securityContext:
+        appArmorProfile:
+          type: RuntimeDefault
        seccompProfile:
          type: RuntimeDefault
-        runAsGroup: 65532
-        fsGroup: 65532
+        runAsGroup: 65534
+        fsGroup: 65534
        runAsNonRoot: true
        runAsUser: 65532
      containers:
      - name: manager
        securityContext:
+          appArmorProfile:
+            type: RuntimeDefault
          seccompProfile:
            type: RuntimeDefault
+          runAsGroup: 65534
          runAsNonRoot: true
          runAsUser: 65532
          capabilities:
            drop:
              - ALL
          readOnlyRootFilesystem: true
```

## Testing

After making these changes:

```bash
# Scan the updated deployment
kubectl kubesec_scan deployment kommander-appmanagement -n kommander

# Expected output:
# kubesec.io score: 9
```

## Quick Reference: What Each Recommendation Does

| # | Recommendation | What It Does | Impact |
|---|----------------|--------------|--------|
| 1 | AppArmor Profile | Restricts what programs can do at runtime | High - Prevents unknown threats |
| 2 | Disable SA Token | Reduces API server attack surface | Medium - Only if API access not needed |
| 3 | hostUsers: false | Isolates UIDs from host | Medium - Requires K8s 1.25+ |
| 4 | Seccomp Profile | Filters system calls | High - Reduces attack surface |
| 5 | High UID Group | Avoids host group conflicts | Low - Good practice |
| 6 | Run as Non-Root | Least privilege | High - Critical security |
| 7 | Drop Capabilities | Removes kernel capabilities | High - Reduces attack surface |
| 8 | Drop ALL | Explicitly drops all capabilities | High - Maximum security |
| 9 | Read-Only Root FS | Immutable filesystem | High - Prevents binary injection |

## Notes

1. **AppArmor** is the most important missing piece - it provides runtime protection
2. **hostUsers** requires Kubernetes 1.25+ - check your cluster version
3. **automountServiceAccountToken** should only be `false` if the pod doesn't need API access
4. All other recommendations are already implemented in the exported YAML

