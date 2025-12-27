# Kubesec Security Guide - Achieving Perfect 9/9 Score

This guide explains how to implement all 9 kubesec security recommendations to achieve a perfect security score.

## Understanding Kubesec Scoring

Kubesec evaluates Kubernetes resources against 9 security checks. Each check is worth 1 point, for a maximum score of 9/9.

## The 9 Security Checks

1. **AppArmor Profile** - Runtime security profiles
2. **Automount Service Account Token** - Disable automatic token mounting
3. **Host Users** - Use user namespaces
4. **Seccomp Profile** - System call filtering
5. **Run as High UID Group** - Use high-UID groups (>10000)
6. **Run as Non-Root** - Force non-root execution
7. **Drop Capabilities** - Remove kernel capabilities
8. **Drop ALL Capabilities** - Drop all capabilities explicitly
9. **Read-Only Root Filesystem** - Immutable filesystem

---

## Implementation Guide

### 1. AppArmor Profile

**What is AppArmor?**
AppArmor is a Linux security module that restricts programs' capabilities with per-program profiles. It provides mandatory access control (MAC) to limit what applications can do.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    metadata:
      annotations:
        # Use RuntimeDefault AppArmor profile (recommended)
        container.apparmor.security.beta.kubernetes.io/<container-name>: runtime/default
    spec:
      securityContext:
        # Pod-level AppArmor (optional, container-level is preferred)
        appArmorProfile:
          type: RuntimeDefault
      containers:
      - name: my-container
        securityContext:
          # Container-level AppArmor
          appArmorProfile:
            type: RuntimeDefault
```

**Note:** `RuntimeDefault` uses the container runtime's default AppArmor profile. For custom profiles, you need to:
1. Create AppArmor profiles on each node
2. Load them into the kernel
3. Reference them in the annotation

**Example with custom profile:**
```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/my-container: localhost/my-custom-profile
```

---

### 2. Automount Service Account Token

**What is it?**
By default, Kubernetes automatically mounts a ServiceAccount token into pods. Disabling this reduces the attack surface if the pod doesn't need to call the Kubernetes API.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      # Disable automatic ServiceAccount token mounting
      automountServiceAccountToken: false
```

**When to use:**
- ✅ Pods that don't need Kubernetes API access
- ✅ Pods using external authentication
- ❌ Pods that need to call Kubernetes API (keep `true` or omit)

---

### 3. Host Users (User Namespaces)

**What is it?**
User namespaces isolate the user ID space, preventing UID conflicts between containers and the host. This is a newer Kubernetes feature (v1.25+).

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      # Enable user namespace (isolates UIDs from host)
      hostUsers: false
```

**Note:** This requires:
- Kubernetes 1.25+ (alpha in 1.25, beta in 1.28)
- Container runtime support (containerd 1.7+, CRI-O 1.25+)
- Feature gate enabled (if using alpha)

**Benefits:**
- Prevents UID conflicts with host
- Additional isolation layer
- Helps prevent certain container escape attacks

---

### 4. Seccomp Profile

**What is Seccomp?**
Seccomp (Secure Computing Mode) restricts the system calls a process can make, reducing the attack surface.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      securityContext:
        # Pod-level seccomp profile
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: my-container
        securityContext:
          # Container-level seccomp (overrides pod-level)
          seccompProfile:
            type: RuntimeDefault
```

**Profile types:**
- `RuntimeDefault` - Uses container runtime's default profile (recommended)
- `Unconfined` - No restrictions (not recommended)
- `Localhost/<profile-name>` - Custom profile from node

**Custom seccomp profile example:**
```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: my-custom-profile.json
```

---

### 5. Run as High UID Group

**What is it?**
Running containers with high UID groups (>10000) avoids conflicts with system groups on the host.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      securityContext:
        # Use high UID group (>10000)
        runAsGroup: 65534  # or any number > 10000
        fsGroup: 65534
      containers:
      - name: my-container
        securityContext:
          # Container-level group (overrides pod-level)
          runAsGroup: 65534
```

**Common high UIDs:**
- `65534` - Traditional "nobody" group (standard Linux convention)
- `65532` - Alpine Linux "nobody" group (Alpine convention)
- `10000-65533` - Any number > 10000

**Note:** Kubesec only checks that `runAsGroup > 10000`. Both 65532 and 65534 satisfy this requirement and get the same score. The preference for 65534 is about:
- **Standardization**: 65534 is the traditional Unix/Linux "nobody" user/group
- **Host compatibility**: More likely to exist on host systems if mounting volumes
- **Documentation consistency**: Most security docs reference 65534

However, if your image already uses 65532 (common in Alpine-based images), you don't need to change it - both work equally well for kubesec scoring!

---

### 6. Run as Non-Root

**What is it?**
Forces containers to run as non-root users, following the principle of least privilege.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      securityContext:
        # Pod-level: force non-root
        runAsNonRoot: true
        runAsUser: 65532  # non-root UID
      containers:
      - name: my-container
        securityContext:
          # Container-level: force non-root
          runAsNonRoot: true
          runAsUser: 65532
```

**Note:** The container image must support running as non-root. Some images require modifications.

---

### 7. Drop Capabilities

**What are Capabilities?**
Linux capabilities divide root privileges into smaller units. Dropping unnecessary capabilities reduces attack surface.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-container
        securityContext:
          capabilities:
            # Drop specific capabilities
            drop:
              - NET_RAW
              - SYS_ADMIN
              - SYS_TIME
            # Or drop all and add only what's needed
            drop:
              - ALL
            add:
              - NET_BIND_SERVICE  # Only if needed
```

---

### 8. Drop ALL Capabilities

**What is it?**
Explicitly drop ALL capabilities, then add back only what's absolutely necessary.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-container
        securityContext:
          capabilities:
            # Drop ALL capabilities first
            drop:
              - ALL
            # Add back only what's needed (if any)
            add:
              - NET_BIND_SERVICE  # Example: needed for binding to port < 1024
```

**Best practice:** Start with dropping ALL, then add back only what's proven necessary.

---

### 9. Read-Only Root Filesystem

**What is it?**
Makes the root filesystem read-only, preventing malicious binaries from being added to PATH.

**How to implement:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-container
        securityContext:
          # Make root filesystem read-only
          readOnlyRootFilesystem: true
        volumeMounts:
        # Mount writable directories for temp files, logs, etc.
        - name: tmp
          mountPath: /tmp
        - name: var-run
          mountPath: /var/run
        - name: var-log
          mountPath: /var/log
      volumes:
      - name: tmp
        emptyDir: {}
      - name: var-run
        emptyDir: {}
      - name: var-log
        emptyDir: {}
```

**Important:** If your app writes to filesystem, you must:
1. Mount writable volumes for directories that need writes
2. Configure app to write to mounted volumes, not root filesystem
3. Test thoroughly - some apps may fail with read-only root

---

## Complete Example: Perfect 9/9 Score

Here's a complete Deployment with all 9 recommendations implemented:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  namespace: default
  annotations:
    # AppArmor annotation (recommendation #1)
    container.apparmor.security.beta.kubernetes.io/my-container: runtime/default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
      annotations:
        # AppArmor for each container
        container.apparmor.security.beta.kubernetes.io/my-container: runtime/default
    spec:
      # Recommendation #2: Disable automount ServiceAccount token
      automountServiceAccountToken: false

      # Recommendation #3: Use user namespaces
      hostUsers: false

      securityContext:
        # Recommendation #4: Seccomp profile
        seccompProfile:
          type: RuntimeDefault

        # Recommendation #5: High UID group
        runAsGroup: 65534
        fsGroup: 65534

        # Recommendation #6: Run as non-root
        runAsNonRoot: true
        runAsUser: 65532

        # Recommendation #1: AppArmor (pod-level, optional)
        appArmorProfile:
          type: RuntimeDefault

      containers:
      - name: my-container
        image: my-app:latest
        imagePullPolicy: IfNotPresent

        securityContext:
          # Recommendation #1: AppArmor (container-level)
          appArmorProfile:
            type: RuntimeDefault

          # Recommendation #4: Seccomp (container-level)
          seccompProfile:
            type: RuntimeDefault

          # Recommendation #5: High UID group (container-level)
          runAsGroup: 65534

          # Recommendation #6: Run as non-root (container-level)
          runAsNonRoot: true
          runAsUser: 65532

          # Recommendations #7 & #8: Drop ALL capabilities
          capabilities:
            drop:
              - ALL
            # Add back only if absolutely necessary
            # add:
            #   - NET_BIND_SERVICE

          # Recommendation #9: Read-only root filesystem
          readOnlyRootFilesystem: true

          # Additional security
          allowPrivilegeEscalation: false
          privileged: false

        # Volume mounts for writable directories (needed for readOnlyRootFilesystem)
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: var-run
          mountPath: /var/run
        - name: var-log
          mountPath: /var/log
        - name: var-cache
          mountPath: /var/cache

        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"

      volumes:
      - name: tmp
        emptyDir: {}
      - name: var-run
        emptyDir: {}
      - name: var-log
        emptyDir: {}
      - name: var-cache
        emptyDir: {}
```

---

## Step-by-Step Implementation

### Step 1: Start with Basic Security Context

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65534
        fsGroup: 65534
      containers:
      - name: my-container
        securityContext:
          runAsNonRoot: true
          runAsUser: 65532
          runAsGroup: 65534
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
```

**Score so far: ~6/9**

### Step 2: Add Seccomp and Read-Only Root

```yaml
spec:
  template:
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: my-container
        securityContext:
          seccompProfile:
            type: RuntimeDefault
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
```

**Score so far: ~8/9**

### Step 3: Add AppArmor, Disable Token, Add User Namespaces

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/my-container: runtime/default
spec:
  template:
    metadata:
      annotations:
        container.apparmor.security.beta.kubernetes.io/my-container: runtime/default
    spec:
      automountServiceAccountToken: false
      hostUsers: false
      securityContext:
        appArmorProfile:
          type: RuntimeDefault
      containers:
      - name: my-container
        securityContext:
          appArmorProfile:
            type: RuntimeDefault
```

**Score: 9/9** ✅

---

## Common Issues and Solutions

### Issue 1: App Crashes with Read-Only Root Filesystem

**Solution:** Mount writable volumes for directories the app needs to write to:

```yaml
volumeMounts:
- name: tmp
  mountPath: /tmp
- name: app-data
  mountPath: /app/data
volumes:
- name: tmp
  emptyDir: {}
- name: app-data
  emptyDir: {}
```

### Issue 2: App Needs Specific Capabilities

**Solution:** Add back only what's needed:

```yaml
capabilities:
  drop:
    - ALL
  add:
    - NET_BIND_SERVICE  # Only if binding to port < 1024
```

### Issue 3: hostUsers Not Supported

**Solution:** This requires Kubernetes 1.25+ and runtime support. If not available:
- Skip this recommendation (score will be 8/9)
- Or upgrade Kubernetes/runtime

### Issue 4: App Needs ServiceAccount Token

**Solution:** Keep `automountServiceAccountToken: true` if app needs Kubernetes API access:

```yaml
spec:
  automountServiceAccountToken: true  # Required for API access
  serviceAccountName: my-service-account
```

---

## Testing Your Configuration

Use the pod-security-audit script to verify:

```bash
# Export and scan
./scripts/pod-security-audit.sh \
  --namespace default \
  --pod my-pod \
  --export fixed-deployment.yaml

# Check kubesec score in output
```

Or scan directly:

```bash
kubectl kubesec_scan deployment my-app -n default
```

---

## Summary Checklist

- [ ] ✅ AppArmor profile set (annotation + securityContext)
- [ ] ✅ `automountServiceAccountToken: false` (if not needed)
- [ ] ✅ `hostUsers: false` (Kubernetes 1.25+)
- [ ] ✅ Seccomp profile: `RuntimeDefault`
- [ ] ✅ `runAsGroup: >10000` (e.g., 65534)
- [ ] ✅ `runAsNonRoot: true` + `runAsUser: non-root`
- [ ] ✅ `capabilities.drop` configured
- [ ] ✅ `capabilities.drop: ["ALL"]` explicitly set
- [ ] ✅ `readOnlyRootFilesystem: true` + writable volumes

**Result: Perfect 9/9 kubesec score!** 🎉

---

## Additional Resources

- [Kubernetes Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [AppArmor Documentation](https://kubernetes.io/docs/tutorials/security/apparmor/)
- [Seccomp Documentation](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

