# Security Fix Validation Guide

## Overview

This guide explains how to determine if security fixes will break a pod before applying them. It covers:
- How to analyze what a pod actually needs
- How to test fixes safely
- Common patterns and red flags
- Step-by-step validation process

## Quick Answer: How Do I Know If Fixes Will Work?

Use the **`validate-security-fixes.sh`** script:

```bash
./scripts/validate-security-fixes.sh --namespace <namespace> --pod <pod-name>
```

This script analyzes:
1. **Current security configuration** - What the pod is using now
2. **Runtime requirements** - What the pod actually needs at runtime
3. **Documentation/annotations** - Any hints about requirements
4. **Dry-run validation** - Tests if fixes are syntactically valid
5. **Recommendations** - Specific guidance based on the analysis

## Understanding Pod Requirements

### How I Knew Cilium Requires Root Privileges

I determined this by analyzing:

1. **Current Configuration**:
   ```bash
   kubectl get daemonset cilium -n kube-system -o json | jq '.spec.template.spec.containers[0].securityContext'
   ```
   - Shows: `privileged: true`, `hostNetwork: true`, multiple capabilities

2. **Runtime Analysis**:
   ```bash
   kubectl exec cilium-xxx -n kube-system -- id -u
   # Returns: 0 (root)
   ```

3. **Application Type**:
   - Cilium is a **CNI (Container Network Interface) plugin**
   - CNI plugins require:
     - `hostNetwork: true` (to manage host networking)
     - `NET_ADMIN` capability (to configure network interfaces)
     - Often `privileged: true` (for eBPF programs, kernel modules)

4. **Documentation**:
   - Cilium documentation explicitly states it requires privileged access
   - It's a system-level component, not a user application

### How to Determine Requirements for Any Pod

#### Step 1: Check Current Configuration

```bash
# Get full security context
kubectl get pod <pod-name> -n <namespace> -o json | jq '.spec | {
  hostNetwork: .hostNetwork,
  hostPID: .hostPID,
  hostIPC: .hostIPC,
  securityContext: .securityContext,
  containers: [.containers[] | {
    name: .name,
    securityContext: .securityContext
  }]
}'
```

**Key Questions:**
- Is `privileged: true`? → **CRITICAL**: Likely needs it
- Is `hostNetwork: true`? → Check if it's a network/system pod
- What capabilities are added? → Each one may be required

#### Step 2: Analyze Runtime Behavior

```bash
# Check what user it's running as
kubectl exec <pod-name> -n <namespace> -- id -u

# Check what capabilities are actually in use
kubectl exec <pod-name> -n <namespace> -- cat /proc/self/status | grep CapEff

# Check if it writes to root filesystem
kubectl exec <pod-name> -n <namespace> -- test -w /tmp && echo "writable" || echo "readonly"
```

**What to Look For:**
- **UID 0 (root)**: App may require root privileges
- **Non-zero UID**: Safe to set `runAsUser` to that UID
- **Capabilities in use**: If present, they may be required
- **Writable filesystem**: May need `readOnlyRootFilesystem: false`

#### Step 3: Check Application Type

**System/Infrastructure Pods** (usually need relaxed security):
- CNI plugins: `cilium`, `calico`, `flannel`, `weave`, `kube-proxy`
- Node exporters: `node-exporter`, `prometheus-node-exporter`
- Storage drivers: `csi-*`, `storage-*`
- System daemons: `kubelet`, `kube-proxy`

**Application Pods** (usually safe to harden):
- Web applications
- APIs
- Databases (with some exceptions)
- Controllers/operators (usually safe)

**Pattern Recognition:**
```bash
# Check labels/annotations
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.labels}'

# Common patterns:
# - app.kubernetes.io/name: cilium → Network plugin
# - app.kubernetes.io/component: node → System component
# - app.kubernetes.io/name: node-exporter → Monitoring
```

#### Step 4: Check Documentation

1. **Kubernetes Annotations**:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.annotations}' | jq
   ```
   Look for:
   - `security.alpha.kubernetes.io/required-*`
   - `pod-security.kubernetes.io/*`
   - Any security-related notes

2. **Application Documentation**:
   - Check the application's official docs
   - Look for "Security Context" or "Privileges" sections
   - Search for known issues with non-root execution

3. **GitHub/Issues**:
   - Search for "non-root", "privileged", "capabilities"
   - Check if others have tried similar hardening

#### Step 5: Test Safely

**Option 1: Test in a Separate Namespace**

```bash
# Create a test namespace
kubectl create namespace test-security

# Copy the deployment
kubectl get deployment <deployment-name> -n <namespace> -o yaml | \
  sed "s/namespace: <namespace>/namespace: test-security/" | \
  kubectl apply -f -

# Apply security fixes to the test deployment
# Monitor logs and behavior
kubectl logs -f deployment/<deployment-name> -n test-security

# If it works, apply to production
# If it fails, rollback immediately
```

**Option 2: Use Dry-Run**

```bash
# Apply fixes with --dry-run=server
kubectl apply --dry-run=server -f fixed-deployment.yaml

# This validates:
# - YAML syntax
# - Kubernetes API validation
# - Policy enforcement (if enabled)
```

**Option 3: Gradual Rollout**

```bash
# Use canary deployment
# 1. Apply to 10% of pods
# 2. Monitor for issues
# 3. Gradually increase to 100%
```

## Common Red Flags

### ⚠️ DO NOT Apply These Fixes If:

1. **`hostNetwork: true`** + Network/System Pod:
   - CNI plugins, node exporters, kube-proxy
   - **Why**: They need direct access to host network stack
   - **Action**: Leave `hostNetwork: true`

2. **`privileged: true`**:
   - **Why**: Full host access - usually means the app needs it
   - **Action**: Only remove if you're 100% certain it's not needed
   - **Test**: Try `privileged: false` in test environment first

3. **Multiple Capabilities** (especially `SYS_ADMIN`, `NET_ADMIN`):
   - **Why**: Each capability may be required for specific functionality
   - **Action**: Test dropping capabilities one at a time

4. **Running as Root (UID 0)**:
   - **Why**: App may require root for:
     - Binding to ports < 1024
     - Accessing system files
     - Kernel operations
   - **Action**: Check if app supports non-root (many modern apps do)

## Safe Fixes (Usually Won't Break)

These fixes are generally safe to apply:

1. **`allowPrivilegeEscalation: false`**:
   - Prevents privilege escalation
   - Rarely breaks applications
   - **Exception**: Some security tools need it

2. **`seccompProfile: RuntimeDefault`**:
   - Standard seccomp profile
   - Most apps work fine with it
   - **Exception**: Some legacy apps may fail

3. **`runAsNonRoot: true`** (if already running as non-root):
   - If pod already runs as UID != 0, this is safe
   - **Exception**: If pod needs to switch to root

4. **`readOnlyRootFilesystem: true`** (with proper volumes):
   - Safe if app uses volumes for writes
   - **Exception**: Apps that write to `/` (use emptyDir for `/tmp`)

## Step-by-Step Validation Process

### For kommander-appmanagement Pod:

```bash
# 1. Run validation script
./scripts/validate-security-fixes.sh \
  --namespace kommander \
  --pod kommander-appmanagement-xxx

# 2. Check current user
kubectl exec kommander-appmanagement-xxx -n kommander -- id -u
# If returns non-zero → Safe to set runAsUser

# 3. Check if it writes to root filesystem
kubectl exec kommander-appmanagement-xxx -n kommander -- \
  sh -c 'test -w /tmp && echo "needs writable /tmp" || echo "readonly OK"'

# 4. Check application type
kubectl get pod kommander-appmanagement-xxx -n kommander \
  -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}'
# Returns: kommander-appmanagement → Application pod (usually safe)

# 5. Test with dry-run
kubectl apply --dry-run=server -f fixed-deployment.yaml

# 6. Apply to test namespace first
# (see "Test Safely" section above)
```

## Example: Cilium vs kommander-appmanagement

### Cilium (Network Plugin):
```
✅ hostNetwork: true → REQUIRED (manages host networking)
✅ privileged: true → REQUIRED (eBPF programs, kernel modules)
✅ NET_ADMIN capability → REQUIRED (network configuration)
❌ runAsUser: 0 → May be required (some kernel operations)
❌ readOnlyRootFilesystem: false → May be required (writes to /var/run/cilium)

Recommendation: DO NOT apply strict security fixes
```

### kommander-appmanagement (Application):
```
✅ runAsUser: 65532 → Already non-root (safe to enforce)
✅ No privileged mode → Safe to keep false
✅ No hostNetwork → Safe to keep false
⚠️ readOnlyRootFilesystem: false → May be safe to set true (test first)
✅ No dangerous capabilities → Safe to drop ALL

Recommendation: SAFE to apply most security fixes
```

## Tools and Scripts

### 1. validate-security-fixes.sh

Comprehensive analysis script:

```bash
./scripts/validate-security-fixes.sh \
  --namespace <namespace> \
  --pod <pod-name> \
  [--kubeconfig <path>] \
  [--export <report-file>]
```

**Output includes:**
- Current security configuration
- Runtime requirements analysis
- Documentation/annotations check
- Dry-run validation
- Specific recommendations

### 2. pod-security-audit.sh

Security audit with export:

```bash
./scripts/pod-security-audit.sh \
  --namespace <namespace> \
  --pod <pod-name> \
  --test-type all \
  --export fixed-pod.yaml \
  [--kubeconfig <path>]
```

**Output includes:**
- Security context analysis
- Hardening checks
- Escape attempt tests
- Exported YAML with suggested fixes
- Before/after Kubesec scores

## Best Practices

1. **Always Test First**:
   - Use test namespace
   - Monitor logs and metrics
   - Test all functionality

2. **Start Conservative**:
   - Apply one fix at a time
   - Test each change
   - Document what works

3. **Have a Rollback Plan**:
   - Keep original YAML
   - Know how to revert quickly
   - Test rollback procedure

4. **Monitor After Applying**:
   - Watch pod logs
   - Check metrics
   - Verify functionality
   - Monitor for 24-48 hours

5. **Document Decisions**:
   - Why certain fixes can't be applied
   - What was tested
   - What works and what doesn't

## Common Questions

### Q: How do I know if a pod needs root?

**A:** Check:
1. Current user: `kubectl exec <pod> -- id -u`
2. If UID = 0 and pod works, it may need root
3. Check if it binds to ports < 1024
4. Check documentation for root requirements

### Q: Can I make Cilium run as non-root?

**A:** Generally **NO**. Cilium requires:
- Privileged mode for eBPF
- Host network for CNI functionality
- Root or specific capabilities for kernel operations

### Q: How do I test if readOnlyRootFilesystem will work?

**A:**
1. Check what directories the app writes to
2. Add emptyDir volumes for writable paths (e.g., `/tmp`)
3. Test in a separate namespace
4. Monitor for write errors in logs

### Q: What if the pod fails after applying fixes?

**A:**
1. **Immediately rollback**: `kubectl rollout undo deployment/<name>`
2. Check logs: `kubectl logs <pod>`
3. Identify which fix caused the issue
4. Test that specific fix in isolation
5. Document the limitation

## Summary

**To know if fixes will work:**

1. ✅ Use `validate-security-fixes.sh` for automated analysis
2. ✅ Check current configuration and runtime behavior
3. ✅ Identify application type (system vs application)
4. ✅ Test in a safe environment first
5. ✅ Monitor closely after applying
6. ✅ Have a rollback plan ready

**Remember**: When in doubt, test first! It's better to be cautious than to break production workloads.

