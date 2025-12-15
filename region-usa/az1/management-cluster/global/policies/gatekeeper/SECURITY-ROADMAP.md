# NKP Cluster Security Roadmap

Beyond Gatekeeper policies, here's a comprehensive security roadmap for your NKP platform.

---

## 1. Supply Chain Security (OpenSSF / SLSA)

### 🔐 Image Signing & Verification

| Tool | Purpose | Status |
|------|---------|--------|
| **Sigstore/Cosign** | Sign container images | ⬜ Not implemented |
| **Ratify** | Verify signatures in Kubernetes | ⬜ Not implemented |
| **Notary v2** | OCI artifact signing | ⬜ Not implemented |

**Implementation:**
```bash
# Sign images with Cosign
cosign sign --key cosign.key your-registry.com/app:v1.0

# Verify in cluster with Ratify + Gatekeeper
# Add constraint to require valid signatures
```

### 📋 SBOM (Software Bill of Materials)

| Tool | Purpose |
|------|---------|
| **Syft** | Generate SBOMs |
| **Grype** | Scan SBOMs for vulnerabilities |
| **GUAC** | Graph for understanding artifact composition |

**Gatekeeper policy idea:**
```yaml
# Require SBOM attestation on images
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireSBOM
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

### 🏗️ SLSA (Supply-chain Levels for Software Artifacts)

Target: **SLSA Level 2+** for all platform images

| Level | Requirements |
|-------|--------------|
| Level 1 | Build process documented |
| Level 2 | Version control + hosted build |
| Level 3 | Hardened build platform |
| Level 4 | Two-person review + hermetic builds |

---

## 2. Runtime Security

### 🔍 Runtime Threat Detection

| Tool | Purpose | Integration |
|------|---------|-------------|
| **Falco** | Runtime anomaly detection | Helm chart available |
| **Tetragon** | eBPF-based observability | Cilium integration |
| **KubeArmor** | Runtime enforcement | LSM-based |

**Falco Rules Example:**
```yaml
- rule: Shell Spawned in Container
  desc: Detect shell in container
  condition: >
    spawned_process and container and
    proc.name in (shell_binaries)
  output: "Shell spawned (user=%user.name container=%container.name)"
  priority: WARNING
```

### 🛡️ Network Policies

**Current Status:** Check if NetworkPolicies exist
```bash
kubectl get networkpolicies --all-namespaces
```

**Recommended:** Default-deny with explicit allows
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

---

## 3. Secrets Management

### 🔑 Current vs Recommended

| Current | Recommended |
|---------|-------------|
| Kubernetes Secrets (base64) | External Secrets Operator |
| Manual secret creation | HashiCorp Vault / AWS Secrets Manager |
| Secrets in Git (sealed) | Secrets never in Git |

**External Secrets Operator:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-secret
  data:
    - secretKey: password
      remoteRef:
        key: secret/data/database
        property: password
```

---

## 4. Vulnerability Scanning

### 📊 Continuous Scanning Pipeline

| Stage | Tool | Action |
|-------|------|--------|
| **Build** | Trivy | Scan images in CI |
| **Registry** | Harbor/Trivy | Scan on push |
| **Admission** | Trivy Operator | Block vulnerable images |
| **Runtime** | Trivy Operator | Continuous scanning |

**Trivy Operator Integration:**
```bash
# Install Trivy Operator
helm install trivy-operator aquasecurity/trivy-operator \
  --namespace trivy-system --create-namespace
```

**Gatekeeper Constraint for CVEs:**
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockCriticalCVE
metadata:
  name: block-critical-cves
spec:
  enforcementAction: deny
  parameters:
    maxSeverity: CRITICAL
```

---

## 5. Audit & Compliance

### 📜 Kubernetes Audit Logging

**Enable enhanced audit logging:**
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
  - level: Metadata
    resources:
      - group: "rbac.authorization.k8s.io"
```

### 🏢 Compliance Frameworks

| Framework | Tool |
|-----------|------|
| **CIS Benchmark** | kube-bench |
| **PCI-DSS** | Custom Gatekeeper policies |
| **SOC 2** | Audit logging + controls |
| **HIPAA** | Encryption + access controls |

**Run CIS Benchmark:**
```bash
# Using kube-bench
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs -l app=kube-bench
```

---

## 6. Identity & Access Management

### 👤 Authentication

| Method | Status | Recommendation |
|--------|--------|----------------|
| X.509 Certs | ✅ Default | Phase out for users |
| OIDC | ⬜ Implement | Integrate with IdP |
| Service Accounts | ✅ In use | Use bound tokens |

**OIDC Integration:**
```yaml
# API Server flags
--oidc-issuer-url=https://your-idp.com
--oidc-client-id=kubernetes
--oidc-username-claim=email
--oidc-groups-claim=groups
```

### 🔒 Authorization

| Current | Recommended |
|---------|-------------|
| cluster-admin for some SAs | Scoped ClusterRoles |
| Manual RBAC | RBAC Manager / automated |
| No namespace isolation | ResourceQuotas per namespace |

---

## 7. Encryption

### 🔐 Data at Rest

```yaml
# Enable etcd encryption
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-key>
      - identity: {}
```

### 🌐 Data in Transit

| Connection | Encryption |
|------------|------------|
| Client → API Server | TLS 1.2+ ✅ |
| Pod → Pod | mTLS (Cilium/Linkerd) |
| etcd | TLS ✅ |

**Enable mTLS with Cilium:**
```yaml
# Cilium config
encryption:
  enabled: true
  type: wireguard
```

---

## 8. OpenSSF Scorecard

Run OpenSSF Scorecard on your repos:
```bash
# Install scorecard
brew install scorecard

# Run against repo
scorecard --repo=github.com/your-org/your-repo
```

### Target Scores

| Check | Target |
|-------|--------|
| Code Review | 10 |
| Branch Protection | 10 |
| Signed Releases | 10 |
| Dependency Update | 8+ |
| SAST | 8+ |
| Token Permissions | 10 |

---

## 9. Implementation Priority

### Phase 1: Foundation (Month 1)
- [ ] Enable Kubernetes audit logging
- [ ] Run CIS benchmark (kube-bench)
- [ ] Deploy Trivy Operator for vulnerability scanning
- [ ] Implement default-deny NetworkPolicies

### Phase 2: Supply Chain (Month 2)
- [ ] Implement image signing with Cosign
- [ ] Deploy Ratify for signature verification
- [ ] Generate SBOMs for all custom images
- [ ] Set up container registry scanning

### Phase 3: Runtime (Month 3)
- [ ] Deploy Falco for runtime detection
- [ ] Enable mTLS between pods (Cilium WireGuard)
- [ ] Integrate with SIEM for alert correlation
- [ ] Implement External Secrets Operator

### Phase 4: Compliance (Month 4+)
- [ ] OIDC integration for user authentication
- [ ] etcd encryption at rest
- [ ] Automated compliance reporting
- [ ] Red team / penetration testing

---

## 10. Useful Commands

```bash
# Check current security posture
kubectl get constraints                          # Gatekeeper violations
kubectl get networkpolicies -A                   # Network policies
kubectl get psp                                  # Pod Security Policies (deprecated)
kubectl get podsecuritypolicies                  # PSP status
kubectl auth can-i --list                        # Current user permissions

# Run security scans
trivy k8s --report summary cluster               # Cluster scan
kube-bench run --targets node,master             # CIS benchmark
kubeaudit all                                    # Security audit

# Check for vulnerable images
kubectl get vulnerabilityreports -A              # If Trivy Operator installed
```

---

## References

### OpenSSF Resources
- [OpenSSF Scorecard](https://securityscorecards.dev/)
- [SLSA Framework](https://slsa.dev/)
- [Sigstore](https://www.sigstore.dev/)
- [OpenSSF Best Practices](https://bestpractices.coreinfrastructure.org/)

### Kubernetes Security
- [Kubernetes Security Checklist](https://kubernetes.io/docs/concepts/security/security-checklist/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)

### Tools Documentation
- [Trivy](https://aquasecurity.github.io/trivy/)
- [Falco](https://falco.org/docs/)
- [Ratify](https://ratify.dev/)
- [External Secrets Operator](https://external-secrets.io/)

