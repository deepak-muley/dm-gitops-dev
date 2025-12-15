# NKP Platform Security Violations Report

**Generated:** December 2024  
**Cluster:** dm-nkp-mgmt-1 (Management Cluster)  
**Total Violations:** 2,945

---

## Executive Summary

| Severity | Count | Constraints |
|----------|-------|-------------|
| 🔴 **Critical** | 1,086 | 5 policies |
| 🟠 **High** | 900 | 5 policies |
| 🟡 **Medium** | 765 | 2 policies |

---

## Violations by Constraint (For Jira Tickets)

### 🔴 CRITICAL SEVERITY

#### JIRA-001: Missing Resource Requests/Limits
- **Constraint:** `require-resource-requests-limits`
- **Violations:** 686
- **Category:** Resource Management
- **Impact:** Pods without limits can cause node resource exhaustion, affecting cluster stability
- **Recommendation:** Add CPU/memory requests and limits to all workloads
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-002: Dangerous Linux Capabilities
- **Constraint:** `disallowed-dangerous-capabilities`
- **Violations:** 194
- **Category:** Pod Security
- **Impact:** Containers with SYS_ADMIN, NET_ADMIN, etc. can escape container isolation
- **Recommendation:** Remove dangerous capabilities or document justification
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-003: Wildcard RBAC Permissions
- **Constraint:** `block-wildcard-rbac`
- **Violations:** 150
- **Category:** RBAC
- **Impact:** Wildcard (*) permissions grant excessive access, violating least-privilege
- **Recommendation:** Replace wildcards with explicit resource/verb lists
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-004: Host Namespace Access
- **Constraint:** `block-host-namespace`
- **Violations:** 74
- **Category:** Pod Security
- **Impact:** hostNetwork/hostPID/hostIPC allows container escape to host
- **Affected Components:**
  - `kommander/kube-prometheus-stack-prometheus-node-exporter` - hostPID + hostNetwork
  - `kube-system/cilium-*` - hostNetwork (expected for CNI)
- **Recommendation:** Document exceptions for legitimate use (CNI, node-exporter)
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-005: Privileged Containers
- **Constraint:** `block-privileged-containers`
- **Violations:** 47
- **Category:** Pod Security
- **Impact:** Privileged containers have full host access - highest risk
- **Recommendation:** Remove privileged mode or document security controls
- **Owner:** NKP Platform Team / Nutanix

---

### 🟠 HIGH SEVERITY

#### JIRA-006: Privilege Escalation Allowed
- **Constraint:** `block-privilege-escalation`
- **Violations:** 391
- **Category:** Pod Security
- **Impact:** Processes can gain more privileges than parent
- **Recommendation:** Set `allowPrivilegeEscalation: false` in securityContext
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-007: Running as Root
- **Constraint:** `require-run-as-nonroot`
- **Violations:** 381
- **Category:** Pod Security
- **Impact:** Root containers have elevated host access if container escapes
- **Recommendation:** Set `runAsNonRoot: true` and specify `runAsUser`
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-008: Missing Standard Labels
- **Constraint:** `require-standard-labels`
- **Violations:** 130
- **Category:** Resource Management
- **Impact:** Missing labels hurt observability, cost allocation, and operations
- **Recommendation:** Add app.kubernetes.io labels to all Deployments
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-009: Host Port Bindings
- **Constraint:** `block-host-ports`
- **Violations:** 79
- **Category:** Network Security
- **Impact:** Host ports bypass network policies and expose services directly
- **Affected Components:**
  - `kube-system/cilium-envoy` - port 9964
  - Various node-level components
- **Recommendation:** Use ClusterIP/NodePort services instead where possible
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-010: Default ServiceAccount Usage
- **Constraint:** `block-default-serviceaccount`
- **Violations:** 20
- **Category:** RBAC
- **Impact:** Default SA may have excessive permissions in some clusters
- **Affected Components:**
  - `kommander-flux/flux-oci-mirror`
  - `kommander/kubernetes-dashboard-auth`
  - `git-operator-system/git-operator-git`
  - `caren-system/helm-repository`
- **Recommendation:** Create dedicated ServiceAccounts with minimal RBAC
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-011: Missing Ingress TLS
- **Constraint:** `require-ingress-tls`
- **Violations:** 19
- **Category:** Network Security
- **Impact:** Unencrypted traffic can be intercepted
- **Recommendation:** Enable TLS on all Ingress resources
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-012: Cluster-Admin Bindings
- **Constraint:** `restrict-cluster-admin`
- **Violations:** 9
- **Category:** RBAC
- **Impact:** Excessive cluster-wide admin access
- **Affected Subjects:**
  - `ServiceAccount/velero-server` (kommander)
  - `ServiceAccount/kommander-self-attach` (kommander)
  - `ServiceAccount/kustomize-controller` (kommander-flux)
  - `ServiceAccount/helm-controller` (kommander-flux)
  - `Group/kubeadm:cluster-admins`
- **Recommendation:** Review if cluster-admin is truly needed; create scoped roles
- **Owner:** NKP Platform Team / Nutanix (needs investigation)

---

### 🟡 MEDIUM SEVERITY

#### JIRA-013: Missing Read-Only Root Filesystem
- **Constraint:** `require-readonly-rootfs`
- **Violations:** 408
- **Category:** Pod Security
- **Impact:** Writable root allows malware persistence
- **Recommendation:** Set `readOnlyRootFilesystem: true`, use emptyDir for writes
- **Owner:** NKP Platform Team / Nutanix

#### JIRA-014: Missing Health Probes
- **Constraint:** `require-health-probes`
- **Violations:** 357
- **Category:** Resource Management
- **Impact:** Unhealthy pods may continue receiving traffic
- **Recommendation:** Add liveness and readiness probes
- **Owner:** NKP Platform Team / Nutanix

---

## Violations by Namespace

| Namespace | Violations | Owner |
|-----------|------------|-------|
| `kommander` | 101 | Nutanix NKP |
| `kube-system` | 33 | Kubernetes (excluded from policies) |
| (cluster-scoped) | 29 | Various |
| `git-operator-system` | 21 | Nutanix NKP |
| `cert-manager` | 15 | Jetstack/Nutanix |
| `caren-system` | 14 | Nutanix NKP |
| `dm-dev-workspace` | 10 | Customer workload |
| `capx-system` | 5 | Nutanix NKP |
| `container-object-storage-system` | 5 | Nutanix NKP |

---

## Recommended Actions

### Immediate (Week 1)
1. ✅ Document exceptions for CNI (Cilium) requiring hostNetwork
2. ✅ Document exceptions for node-exporter requiring hostPID
3. Review cluster-admin bindings - create scoped alternatives if possible

### Short-term (Week 2-4)
4. File Jira tickets with Nutanix for NKP component violations
5. Add missing labels to NKP deployments
6. Enable TLS on internal Ingress resources

### Medium-term (Month 2-3)
7. Work with Nutanix to add resource limits to all pods
8. Implement Pod Security Standards (PSS) at namespace level
9. Set up continuous policy monitoring dashboards

---

## Files for Reference

All constraint files are in:
```
region-usa/az1/management-cluster/global/policies/gatekeeper/constraints/
├── pod-security/
├── image-security/
├── resource-management/
├── network-security/
└── rbac/
```

