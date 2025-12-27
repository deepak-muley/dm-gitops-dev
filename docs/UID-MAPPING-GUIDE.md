# UID Mapping Between Containers and Host

## Understanding UID Mapping

### Key Finding

**Container UIDs map directly to host UIDs** - there's no automatic translation!

When you set `runAsUser: 65532` in a container:
- Container sees: UID 65532
- Host sees: UID 65532 (same number)
- **No mapping/translation occurs**

### UID Mapping Explained

The `/proc/self/uid_map` file shows how container UIDs map to host UIDs:

```
0          0 4294967295
```

This means:
- Container UID 0 → Host UID 0
- Container UID 1 → Host UID 1
- Container UID 65532 → Host UID 65532
- Container UID 65534 → Host UID 65534
- **No translation** - they're the same!

### Does the UID Need to Match a Host User?

**Short answer: It depends on whether you mount hostPath volumes.**

#### Scenario 1: No hostPath Volumes (Most Common)

**You don't need the UID to exist on the host!**

```yaml
# No hostPath volumes
volumes:
- name: tmp
  emptyDir: {}
```

**Why it works:**
- Container filesystem is isolated
- emptyDir, configMap, secret volumes work fine
- No host filesystem interaction
- UID 65532 or 65534 both work equally well

**Example:** Your `kommander-appmanagement` pod works fine with UID 65532 even if that user doesn't exist on the host.

#### Scenario 2: With hostPath Volumes (Less Common, Higher Risk)

**You should match a host user IF you need proper file permissions!**

```yaml
volumes:
- name: host-data
  hostPath:
    path: /var/data/my-app
```

**Why matching matters:**
- Files created in hostPath volumes are owned by the container's UID
- If UID 65532 doesn't exist on host, files show as numeric UID
- If UID 65534 exists on host (nobody), files show as "nobody" user
- **File permissions matter for host processes accessing the data**

**Best practice:**
1. **Avoid hostPath volumes** (security risk - use PVs instead)
2. If you must use hostPath:
   - Use UID 65534 (more likely to exist on host as "nobody")
   - Or create a dedicated user on the host
   - Set proper permissions on hostPath directory

### What Your Container Shows

From the kommander-appmanagement pod:

```
Container UID: 65532
Container GID: 0 (root)
Container user: unknown uid 65532
```

**Observations:**
1. Container runs as UID 65532
2. Container's `/etc/passwd` shows "nobody" as UID 65534 (not 65532)
3. Container doesn't have a user entry for 65532
4. **This is fine!** The container works without a matching user entry

### When UID Matching Matters

#### ✅ Matching NOT Required When:
- No hostPath volumes
- Using emptyDir, configMap, secret volumes
- Container doesn't interact with host filesystem
- Standard Kubernetes deployments

#### ⚠️ Matching Recommended When:
- Using hostPath volumes
- Need host processes to access container-created files
- Want readable usernames instead of numeric UIDs
- Sharing data between host and container

### Practical Examples

#### Example 1: No hostPath (Your Current Setup)

```yaml
spec:
  securityContext:
    runAsUser: 65532  # Works fine!
  volumes:
  - name: tmp
    emptyDir: {}  # No host interaction
```

**Result:** ✅ Works perfectly. UID 65532 doesn't need to exist on host.

#### Example 2: With hostPath (Should Match)

```yaml
spec:
  securityContext:
    runAsUser: 65534  # Better choice for hostPath
  volumes:
  - name: host-data
    hostPath:
      path: /var/data
```

**Why 65534 is better:**
- More likely to exist on host as "nobody" user
- Files show as "nobody" instead of numeric "65534"
- Better compatibility with host tools

#### Example 3: Custom Host User (Best for hostPath)

```yaml
# On host node:
sudo useradd -r -u 10001 -g 10001 -s /sbin/nologin myapp

# In pod:
spec:
  securityContext:
    runAsUser: 10001
    runAsGroup: 10001
  volumes:
  - name: host-data
    hostPath:
      path: /var/data/myapp
```

**Result:** Files owned by "myapp" user on host, proper permissions.

### Recommendations

#### For Your kommander-appmanagement Pod

**Current setup (UID 65532):**
- ✅ **No changes needed** if no hostPath volumes
- ✅ Works perfectly with emptyDir, configMap, secret volumes
- ✅ No security impact
- ✅ Kubesec score is the same (both > 10000)

**If you add hostPath volumes:**
- Consider changing to 65534 for better host compatibility
- Or create a dedicated user on each node
- Or use PersistentVolumes instead (recommended)

#### General Best Practices

1. **Avoid hostPath volumes** - Use PersistentVolumes instead
2. **Use high UIDs (>10000)** - Avoids conflicts with system users
3. **65532 vs 65534** - Both work, 65534 is more "standard"
4. **Don't worry about matching** - Unless using hostPath volumes

### Summary

| Scenario | Need Host User? | Recommended UID |
|----------|----------------|-----------------|
| No hostPath volumes | ❌ No | 65532 or 65534 (both work) |
| With hostPath volumes | ✅ Yes (recommended) | 65534 (nobody) or custom user |
| Standard deployments | ❌ No | 65532 or 65534 (both work) |

**For your kommander-appmanagement pod:**
- Current UID 65532 is **perfectly fine**
- No need to change to 65534 unless you add hostPath volumes
- Both get the same kubesec score
- No security impact

### Testing UID Mapping

You can check the mapping in your pod:

```bash
# Check container UID
kubectl exec -n kommander kommander-appmanagement-xxx -- id

# Check UID mapping
kubectl exec -n kommander kommander-appmanagement-xxx -- cat /proc/self/uid_map

# Check if user exists in container
kubectl exec -n kommander kommander-appmanagement-xxx -- cat /etc/passwd | grep 65532
```

The mapping `0 0 4294967295` means:
- Container UID = Host UID (no translation)
- UID 65532 in container = UID 65532 on host
- Whether that user exists on host depends on the host's `/etc/passwd`

