# Gatekeeper Security Policies

This directory contains OPA Gatekeeper policies for enforcing security standards across the Kubernetes cluster.

## Directory Structure

```
gatekeeper/
├── kustomization.yaml           # Main kustomization
├── README.md                    # This file
├── constraint-templates/        # Policy logic (Rego)
│   ├── pod-security/           # Pod security context policies
│   ├── image-security/         # Container image policies
│   ├── resource-management/    # Resource limits/labels policies
│   ├── network-security/       # Network exposure policies
│   └── rbac/                   # RBAC and ServiceAccount policies
└── constraints/                # Policy instances with parameters
    ├── pod-security/
    ├── image-security/
    ├── resource-management/
    ├── network-security/
    └── rbac/
```

## Policy Categories

### 🔒 Pod Security (Critical)
| Policy | Description | Severity |
|--------|-------------|----------|
| `block-privileged-containers` | Blocks privileged container mode | 🔴 Critical |
| `block-privilege-escalation` | Prevents privilege escalation | 🟠 High |
| `require-run-as-nonroot` | Requires non-root user | 🟠 High |
| `block-host-namespace` | Blocks host PID/IPC/Network | 🔴 Critical |
| `disallowed-dangerous-capabilities` | Blocks dangerous Linux capabilities | 🔴 Critical |
| `require-readonly-rootfs` | Requires read-only root filesystem | 🟡 Medium |

### 🖼️ Image Security (Critical)
| Policy | Description | Severity |
|--------|-------------|----------|
| `allowed-container-repos` | Whitelist of allowed registries | 🔴 Critical |
| `block-latest-tag` | Blocks `:latest` tag usage | 🟠 High |
| `require-image-digest` | Requires image digests (strict) | 🟡 Medium |

### 📋 Resource Management (High)
| Policy | Description | Severity |
|--------|-------------|----------|
| `require-resource-requests-limits` | Requires CPU/memory limits | 🔴 Critical |
| `require-standard-labels` | Requires standard Kubernetes labels | 🟠 High |
| `require-health-probes` | Requires liveness/readiness probes | 🟡 Medium |
| `enforce-max-container-limits` | Enforces maximum resource limits | 🟡 Medium |

### 🌐 Network Security (High)
| Policy | Description | Severity |
|--------|-------------|----------|
| `block-nodeport-services` | Blocks NodePort services | 🟡 Medium |
| `block-loadbalancer-services` | Blocks LoadBalancer services | 🟡 Medium |
| `require-ingress-tls` | Requires TLS on Ingress | 🟠 High |
| `block-host-ports` | Blocks host port bindings | 🟠 High |

### 🔐 RBAC (Critical)
| Policy | Description | Severity |
|--------|-------------|----------|
| `block-default-serviceaccount` | Blocks use of default SA | 🟠 High |
| `block-wildcard-rbac` | Blocks wildcard (*) in RBAC | 🔴 Critical |
| `restrict-cluster-admin` | Restricts cluster-admin bindings | 🔴 Critical |
| `require-explicit-automount` | Requires explicit SA token mount | 🟡 Medium |

## Enforcement Actions

All policies support three enforcement modes:

| Mode | Description | Use Case |
|------|-------------|----------|
| `deny` | Blocks non-compliant resources | Production enforcement |
| `warn` | Allows but logs violations | Rollout/testing phase |
| `dryrun` | Only audits existing resources | Initial assessment |

## Rollout Strategy

### Current Configuration: Full Assessment Mode

All policies are currently configured with:
- **`enforcementAction: warn`** - Logs violations without blocking
- **No namespace exclusions** - All namespaces are evaluated for complete visibility

This allows you to see the **full security posture** of your platform before making decisions about exclusions.

### Phase 1: Assessment (Week 1-2)
1. Deploy all constraints (current state)
2. Run audit: `kubectl get constraints -o wide`
3. Review all violations across ALL namespaces
4. Identify which violations are:
   - **Legitimate issues** to fix
   - **Expected exceptions** (system components that need elevated permissions)

### Phase 2: Add Selective Exclusions (Week 3)
Based on assessment, add `excludedNamespaces` for legitimate exceptions:

```yaml
spec:
  match:
    excludedNamespaces:
      - kube-system          # Core K8s components
      - gatekeeper-system    # Gatekeeper itself
      - kommander            # NKP management plane
      - kommander-flux       # Flux GitOps components
      - cert-manager         # Certificate management
      - capi-system          # Cluster API
      - capx-system          # Cluster API providers
```

### Phase 3: Enforcement (Week 4+)
1. Change critical policies to `deny`
2. Continue monitoring for new violations
3. Adjust exclusions as platform evolves

## Customization

### Adding Namespace Exclusions
Edit the constraint to add namespaces that need exceptions:

```yaml
spec:
  match:
    excludedNamespaces:
      - kube-system
      - your-exception-namespace
```

### Changing Allowed Registries
Edit `constraints/image-security/allowed-repos.yaml`:

```yaml
parameters:
  repos:
    - "your-private-registry.com/"
    - "gcr.io/your-project/"
```

### Adjusting Resource Limits
Edit `constraints/resource-management/container-limits.yaml`:

```yaml
parameters:
  maxCpu: "16000m"    # 16 cores
  maxMemory: "64Gi"   # 64 GB
```

### Airgapped / Disconnected Environments

For airgapped environments where all images are mirrored to an internal registry:

1. **Edit** `constraints/image-security/allowed-repos.yaml`
2. **Remove** all public registries (docker.io, gcr.io, quay.io, etc.)
3. **Add** only your internal registry:

```yaml
parameters:
  repos:
    # AIRGAPPED: Only internal registry
    - "harbor.internal.company.com/"
    # Or with project structure:
    # - "registry.company.com/nkp/"
    # - "registry.company.com/platform/"
```

**Important**: Ensure ALL NKP images are mirrored to your internal registry before enabling enforcement.

## Monitoring

### Check Constraint Status
```bash
kubectl get constraints
```

### View Violations
```bash
kubectl get constraints -o json | jq '.items[] | {name: .metadata.name, violations: .status.totalViolations}'
```

### Audit All Resources
```bash
# Trigger a full audit
kubectl annotate constraint --all gatekeeper.sh/audit-timestamp=$(date +%s) --overwrite
```

## Troubleshooting

### Policy Not Enforcing
1. Check ConstraintTemplate exists: `kubectl get constrainttemplates`
2. Check Constraint status: `kubectl describe constraint <name>`
3. Verify namespace is not excluded

### Too Many Violations
1. Start with `warn` mode
2. Add legitimate exceptions to excludedNamespaces
3. Work with teams to remediate

### Template Errors
Check Gatekeeper audit pod logs:
```bash
kubectl logs -n gatekeeper-system -l control-plane=audit-controller
```

## Pre-built Policy Libraries

Instead of writing all policies from scratch, consider these well-maintained policy libraries:

| Library | Description | Link |
|---------|-------------|------|
| **Gatekeeper Library** | Official OPA Gatekeeper policy library with ready-to-use templates | [GitHub](https://github.com/open-policy-agent/gatekeeper-library) |
| **Kyverno Policies** | If using Kyverno instead of Gatekeeper | [kyverno.io/policies](https://kyverno.io/policies/) |
| **Pod Security Standards** | Kubernetes native pod security (Baseline, Restricted, Privileged) | [K8s Docs](https://kubernetes.io/docs/concepts/security/pod-security-standards/) |
| **Ratify** | Supply chain security - verify container signatures and SBOMs | [GitHub](https://github.com/ratify-project/ratify) |
| **Polaris** | Best practices validation for Kubernetes workloads | [GitHub](https://github.com/FairwindsOps/polaris) |

### Security Frameworks & Guidelines

| Framework | Description | Link |
|-----------|-------------|------|
| **CIS Kubernetes Benchmark** | Industry-standard security configuration guidelines | [CIS](https://www.cisecurity.org/benchmark/kubernetes) |
| **NSA/CISA Kubernetes Hardening Guide** | US Government security recommendations | [NSA](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF) |
| **NIST Container Security Guide** | Application container security guide (SP 800-190) | [NIST](https://csrc.nist.gov/publications/detail/sp/800-190/final) |
| **OWASP Kubernetes Security** | OWASP security cheat sheet for Kubernetes | [OWASP](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html) |

### Additional Tools

| Tool | Purpose | Link |
|------|---------|------|
| **Trivy** | Vulnerability scanning for containers and IaC | [GitHub](https://github.com/aquasecurity/trivy) |
| **Falco** | Runtime security and threat detection | [falco.org](https://falco.org/) |
| **KubeAudit** | Audit Kubernetes clusters for security concerns | [GitHub](https://github.com/Shopify/kubeaudit) |
| **Kubesec** | Security risk analysis for Kubernetes resources | [kubesec.io](https://kubesec.io/) |
| **Datree** | Prevent Kubernetes misconfigurations | [datree.io](https://www.datree.io/) |

## References

- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/)
- [Gatekeeper Policy Library](https://github.com/open-policy-agent/gatekeeper-library)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)

