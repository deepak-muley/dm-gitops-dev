# NKP RBAC Complete Guide for Beginners

## Table of Contents
1. [What is NKP RBAC?](#what-is-nkp-rbac)
2. [The Three Levels of Access](#the-three-levels-of-access)
3. [Understanding Super Admin](#understanding-super-admin)
4. [Creating Kubernetes Users (Without IDP)](#creating-kubernetes-users-without-idp)
5. [Key Concepts](#key-concepts)
6. [NKP RBAC CRDs Reference](#nkp-rbac-crds-reference)
7. [Exploring RBAC with kubectl Commands](#exploring-rbac-with-kubectl-commands)
8. [Practical Examples](#practical-examples)
9. [Troubleshooting](#troubleshooting)

---

## What is NKP RBAC?

**NKP (Nutanix Kubernetes Platform)** uses a hierarchical RBAC (Role-Based Access Control) system built on top of Kubernetes RBAC. It provides three levels of access control:

```
┌──────────────────────────────────────────────────────────────┐
│                    🌐 GLOBAL LEVEL                           │
│    Full access to ALL workspaces, projects, and clusters     │
│    Example: Platform Admin, SRE Team Lead                    │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                  🏢 WORKSPACE LEVEL                          │
│    Access to ONE workspace and ALL its projects/clusters     │
│    Example: Team Lead, DevOps Engineer                       │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                   📁 PROJECT LEVEL                           │
│    Access to ONLY ONE project within a workspace             │
│    Example: Developer, Application Team Member               │
└──────────────────────────────────────────────────────────────┘
```

---

## The Three Levels of Access

### 1. Global Level 🌐
- **Scope**: Entire NKP platform
- **Access**: All workspaces, all projects, all clusters, all applications
- **Use Case**: Platform administrators who need full control
- **Namespace**: Cluster-scoped (no namespace)

### 2. Workspace Level 🏢
- **Scope**: Single workspace and everything inside it
- **Access**: One workspace, all projects within it, all clusters attached to it
- **Use Case**: Team leads who manage a specific team's resources
- **Namespace**: Workspace namespace (e.g., `dm-dev-workspace`)

### 3. Project Level 📁
- **Scope**: Single project only
- **Access**: Only resources within one project
- **Use Case**: Developers who only need access to their application
- **Namespace**: Project namespace (e.g., `dm-dev-project`)

---

## Understanding Super Admin

### What Makes a "Super Admin"?

A true **Super Admin** in NKP needs **BOTH** Kubernetes and NKP/Kommander permissions:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                        🔐 SUPER ADMIN = BOTH                              │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│   ┌─────────────────────────┐      ┌─────────────────────────────────┐   │
│   │   cluster-admin         │  +   │   kommander-admin               │   │
│   │   (Kubernetes native)   │      │   (NKP/Kommander specific)      │   │
│   ├─────────────────────────┤      ├─────────────────────────────────┤   │
│   │ ✓ All namespaces        │      │ ✓ Workspaces                    │   │
│   │ ✓ All K8s resources     │      │ ✓ Projects                      │   │
│   │ ✓ Nodes, PVs, CRDs      │      │ ✓ Application deployments       │   │
│   │ ✓ System components     │      │ ✓ VirtualGroups                 │   │
│   │ ✓ RBAC management       │      │ ✓ Cluster attachments           │   │
│   │ ✓ Secrets (all)         │      │ ✓ Catalog management            │   │
│   └─────────────────────────┘      └─────────────────────────────────┘   │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### Role Comparison

| Role | What It Controls | Is Super Admin? |
|------|-----------------|-----------------|
| `cluster-admin` | All native Kubernetes resources | ❌ No NKP access |
| `kommander-admin` | All NKP/Kommander CRDs (workspaces, projects, apps) | ❌ No K8s system access |
| `cluster-admin` + `kommander-admin` | **Everything** | ✅ **Yes - True Super Admin** |

### Why Both Are Needed

**With only `kommander-admin`:**
```bash
# CAN do:
kubectl get workspaces              # ✅ Works
kubectl get projects -A             # ✅ Works
kubectl get appdeployments -A       # ✅ Works

# CANNOT do:
kubectl get nodes                   # ❌ Forbidden
kubectl get secrets -n kube-system  # ❌ Forbidden
kubectl get pv                      # ❌ Forbidden
```

**With only `cluster-admin`:**
```bash
# CAN do:
kubectl get nodes                   # ✅ Works
kubectl get secrets -A              # ✅ Works
kubectl get pods -A                 # ✅ Works

# CANNOT do (in NKP UI):
# - Create/manage workspaces in DKP UI
# - Deploy apps through Kommander
# - Manage workspace role bindings
```

**With BOTH (Super Admin):**
```bash
# Everything works:
kubectl get nodes                   # ✅ Works
kubectl get workspaces              # ✅ Works
kubectl get secrets -A              # ✅ Works
kubectl get appdeployments -A       # ✅ Works
# DKP UI fully accessible           # ✅ Works
```

---

## Creating Kubernetes Users (Without IDP)

### How Kubernetes User Authentication Works

Kubernetes doesn't store user accounts. Instead, it uses **X.509 certificates** for authentication:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Certificate-Based Authentication                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   User Certificate                    Kubernetes API Server              │
│   ┌─────────────────┐                 ┌──────────────────┐              │
│   │ CN=dm-k8s-admin │ ───────────────►│ Validates cert   │              │
│   │ (Common Name)   │                 │ against CA       │              │
│   └─────────────────┘                 │                  │              │
│           │                           │ Extracts CN as   │              │
│           │                           │ username         │              │
│           ▼                           └──────────────────┘              │
│   Username in K8s = "dm-k8s-admin"            │                         │
│                                               │                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ VirtualGroup                                                     │   │
│   │ spec.subjects:                                                   │   │
│   │   - kind: User                                                   │   │
│   │     name: dm-k8s-admin  ◄── MUST MATCH certificate CN            │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Step-by-Step: Create a Kubernetes User

#### Option 1: Use the Automated Script (Recommended)

```bash
# Navigate to scripts directory
cd scripts/

# Create the super admin user
./create-k8s-user.sh dm-k8s-admin

# Create workspace admin user
./create-k8s-user.sh dm-dev-workspace-admin

# Create project admin user
./create-k8s-user.sh dm-dev-project-admin

# With custom validity (365 days) and group
./create-k8s-user.sh myuser 365 mygroup
```

**Output:**
```
============================================
  Creating Kubernetes User: dm-k8s-admin
============================================

[1/6] Generating private key...
      Created: ./generated-kubeconfigs/dm-k8s-admin.key
[2/6] Creating CSR...
      Created: ./generated-kubeconfigs/dm-k8s-admin.csr
[3/6] Submitting CSR to Kubernetes...
      Submitted CSR: dm-k8s-admin-csr-1702900000
[4/6] Approving CSR...
      CSR approved
[5/6] Saving signed certificate...
      Created: ./generated-kubeconfigs/dm-k8s-admin.crt
[6/6] Creating kubeconfig...
      Created: ./generated-kubeconfigs/dm-k8s-admin.kubeconfig

============================================
  User Created Successfully!
============================================

Files generated:
  - Private Key:  ./generated-kubeconfigs/dm-k8s-admin.key
  - Certificate:  ./generated-kubeconfigs/dm-k8s-admin.crt
  - Kubeconfig:   ./generated-kubeconfigs/dm-k8s-admin.kubeconfig
```

#### Option 2: Manual Steps

```bash
# Set variables
USERNAME="dm-k8s-admin"
CLUSTER_NAME="dm-nkp-mgmt-1"

# Step 1: Generate private key
openssl genrsa -out ${USERNAME}.key 2048

# Step 2: Create CSR (Certificate Signing Request)
# CN (Common Name) becomes the Kubernetes username
openssl req -new -key ${USERNAME}.key -out ${USERNAME}.csr -subj "/CN=${USERNAME}"

# Step 3: Create CSR in Kubernetes
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}-csr
spec:
  request: $(cat ${USERNAME}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
    - client auth
EOF

# Step 4: Approve the CSR
kubectl certificate approve ${USERNAME}-csr

# Step 5: Get the signed certificate
kubectl get csr ${USERNAME}-csr -o jsonpath='{.status.certificate}' | base64 -d > ${USERNAME}.crt

# Step 6: Get cluster CA certificate
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt

# Step 7: Get API server URL
API_SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')

# Step 8: Create kubeconfig
kubectl config set-cluster ${CLUSTER_NAME} \
    --kubeconfig=${USERNAME}.kubeconfig \
    --server=${API_SERVER} \
    --certificate-authority=ca.crt \
    --embed-certs=true

kubectl config set-credentials ${USERNAME} \
    --kubeconfig=${USERNAME}.kubeconfig \
    --client-certificate=${USERNAME}.crt \
    --client-key=${USERNAME}.key \
    --embed-certs=true

kubectl config set-context ${USERNAME}@${CLUSTER_NAME} \
    --kubeconfig=${USERNAME}.kubeconfig \
    --cluster=${CLUSTER_NAME} \
    --user=${USERNAME}

kubectl config use-context ${USERNAME}@${CLUSTER_NAME} --kubeconfig=${USERNAME}.kubeconfig

echo "Kubeconfig created: ${USERNAME}.kubeconfig"
```

### Using the Generated Kubeconfig

```bash
# Option 1: Set as environment variable
export KUBECONFIG=./generated-kubeconfigs/dm-k8s-admin.kubeconfig
kubectl get pods

# Option 2: Use inline
kubectl --kubeconfig=./generated-kubeconfigs/dm-k8s-admin.kubeconfig get pods

# Test authentication (K8s 1.24+)
kubectl --kubeconfig=./generated-kubeconfigs/dm-k8s-admin.kubeconfig auth whoami
```

**Expected output for `auth whoami`:**
```yaml
ATTRIBUTE   VALUE
Username    dm-k8s-admin
Groups      [system:authenticated]
```

### Verifying User Permissions

```bash
# Check what the user can do
kubectl --kubeconfig=./generated-kubeconfigs/dm-k8s-admin.kubeconfig auth can-i --list

# Check specific permission
kubectl --kubeconfig=./generated-kubeconfigs/dm-k8s-admin.kubeconfig auth can-i get pods -A
kubectl --kubeconfig=./generated-kubeconfigs/dm-k8s-admin.kubeconfig auth can-i get workspaces
kubectl --kubeconfig=./generated-kubeconfigs/dm-k8s-admin.kubeconfig auth can-i '*' '*'
```

### Important Notes

1. **Username Matching**: The certificate CN **MUST** exactly match the `name` in VirtualGroup subjects
   ```yaml
   # Certificate: CN=dm-k8s-admin
   # VirtualGroup must have:
   spec:
     subjects:
       - kind: User
         name: dm-k8s-admin  # Must match exactly!
   ```

2. **Certificate Expiry**: Certificates have a validity period. Plan for renewal.

3. **Security**:
   - Keep private keys secure (`.key` files)
   - Don't commit kubeconfigs to git
   - Use short-lived certificates in production
   - Consider using OIDC/IDP for production environments

4. **Groups via Certificates**: You can also specify groups using the O (Organization) field:
   ```bash
   # CN=username, O=groupname
   openssl req -new -key user.key -out user.csr -subj "/CN=myuser/O=developers"
   ```
   This user will be in the `developers` group in Kubernetes.

---

## Key Concepts

### VirtualGroup
A **VirtualGroup** is NKP's way of mapping external identity provider (IdP) users or groups to NKP roles.

Think of it as a "bridge" between:
- **Your IdP** (OIDC, LDAP, SAML) → Users/Groups
- **NKP Roles** → Permissions

```yaml
# Example: VirtualGroup maps OIDC group to NKP
apiVersion: kommander.mesosphere.io/v1beta1
kind: VirtualGroup
metadata:
  name: my-team
spec:
  subjects:
    - apiGroup: rbac.authorization.k8s.io
      kind: Group
      name: oidc:my-team-group  # From your IdP
```

### Roles vs Role Bindings

| Concept | What It Is | Analogy |
|---------|-----------|---------|
| **Role** | A set of permissions (what can be done) | Job description |
| **RoleBinding** | Links a user/group to a role | Hiring someone for that job |
| **VirtualGroup** | A group of users from IdP | A team of people |

### Built-in Role Types

NKP provides these pre-configured roles at each level:

| Permission Level | Global | Workspace | Project |
|-----------------|--------|-----------|---------|
| **Admin** | `kommander-admin` | `workspace-admin` | `project-app-deployer` + `project-config-manager` |
| **Edit** | `kommander-edit` | `workspace-edit` | `project-app-deployer` |
| **View** | `kommander-view` | `workspace-view` | `project-auditor` |

---

## NKP RBAC CRDs Reference

### Complete CRD List

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ LEVEL      │ IDENTITY CRD      │ ROLE CRD                │ BINDING CRD           │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Global     │ VirtualGroup      │ ClusterRole             │ VirtualGroupKommander │
│            │                   │ (kommander-admin, etc.) │ ClusterRoleBinding    │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Workspace  │ VirtualGroup      │ WorkspaceRole           │ VirtualGroupWorkspace │
│            │                   │ KommanderWorkspaceRole  │ RoleBinding           │
│            │                   │                         │ VirtualGroupKommander │
│            │                   │                         │ WorkspaceRoleBinding  │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Project    │ VirtualGroup      │ ProjectRole             │ VirtualGroupProject   │
│            │                   │ KommanderProjectRole    │ RoleBinding           │
│            │                   │                         │ VirtualGroupKommander │
│            │                   │                         │ ProjectRoleBinding    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### CRD Descriptions

| CRD | Full Name | Scope | Purpose |
|-----|-----------|-------|---------|
| `VirtualGroup` | `kommander.mesosphere.io/v1beta1` | Cluster | Maps IdP users/groups to NKP |
| `VirtualGroupKommanderClusterRoleBinding` | `workspaces.kommander.mesosphere.io/v1alpha1` | Cluster | Binds VirtualGroup to global ClusterRole |
| `WorkspaceRole` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Defines workspace permissions |
| `KommanderWorkspaceRole` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Defines Kommander-specific workspace permissions |
| `VirtualGroupWorkspaceRoleBinding` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Binds VirtualGroup to WorkspaceRole |
| `VirtualGroupKommanderWorkspaceRoleBinding` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Binds VirtualGroup to KommanderWorkspaceRole |
| `ProjectRole` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Defines project permissions |
| `KommanderProjectRole` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Defines Kommander-specific project permissions |
| `VirtualGroupProjectRoleBinding` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Binds VirtualGroup to ProjectRole |
| `VirtualGroupKommanderProjectRoleBinding` | `workspaces.kommander.mesosphere.io/v1alpha1` | Namespaced | Binds VirtualGroup to KommanderProjectRole |

---

## Exploring RBAC with kubectl Commands

### Prerequisites

```bash
# Set your kubeconfig to the NKP management cluster
export KUBECONFIG=/path/to/mgmt-cluster.kubeconfig

# Verify connection
kubectl cluster-info
```

### 1. List All RBAC-Related API Resources

```bash
# See all RBAC CRDs available in NKP
kubectl api-resources | grep -iE "role|workspace|project|virtualgroup"
```

**What this shows**: All the Custom Resource Definitions (CRDs) related to RBAC in your NKP cluster.

**Example output**:
```
NAME                                      SHORTNAMES   APIVERSION                                       NAMESPACED   KIND
virtualgroups                                          kommander.mesosphere.io/v1beta1                  false        VirtualGroup
virtualgroupkommanderclusterrolebindings               workspaces.kommander.mesosphere.io/v1alpha1      false        VirtualGroupKommanderClusterRoleBinding
workspaceroles                                         workspaces.kommander.mesosphere.io/v1alpha1      true         WorkspaceRole
projectroles                                           workspaces.kommander.mesosphere.io/v1alpha1      true         ProjectRole
```

---

### 2. Explore VirtualGroups (Identity Mappings)

```bash
# List all VirtualGroups
kubectl get virtualgroups

# Get detailed info about a VirtualGroup
kubectl get virtualgroup <name> -o yaml

# See which users/groups are in a VirtualGroup
kubectl describe virtualgroup <name>
```

**What this shows**: Which IdP users/groups are mapped to NKP.

**Example**:
```bash
kubectl get virtualgroups
```
```
NAME                      AGE
dm-k8s-admins            1h
dm-dev-workspace-admins  1h
dm-dev-project-admins    1h
```

```bash
kubectl get virtualgroup dm-k8s-admins -o yaml
```
```yaml
apiVersion: kommander.mesosphere.io/v1beta1
kind: VirtualGroup
metadata:
  name: dm-k8s-admins
spec:
  subjects:
    - apiGroup: rbac.authorization.k8s.io
      kind: User
      name: dm-k8s-admin
```

---

### 3. Explore Global-Level Permissions

#### List Global ClusterRoles (Built-in)

```bash
# List all Kommander-related ClusterRoles
kubectl get clusterroles | grep -E "kommander|dkp-kommander"

# See what permissions a ClusterRole has
kubectl describe clusterrole kommander-admin

# See detailed permissions in YAML format
kubectl get clusterrole kommander-admin -o yaml
```

**What this shows**: The built-in global roles and their permissions.

**Key roles to know**:
| Role | Permissions |
|------|-------------|
| `kommander-admin` | Full admin access to all Kommander resources |
| `kommander-edit` | Can modify Kommander resources |
| `kommander-view` | Read-only access to Kommander resources |
| `dkp-kommander-admin` | Full DKP UI access |

#### List Global Role Bindings

```bash
# List VirtualGroupKommanderClusterRoleBindings
kubectl get virtualgroupkommanderclusterrolebindings

# Get details of a specific binding
kubectl get virtualgroupkommanderclusterrolebinding <name> -o yaml

# See which VirtualGroup is bound to which ClusterRole
kubectl describe virtualgroupkommanderclusterrolebinding <name>
```

**What this shows**: Which VirtualGroups have global-level access.

---

### 4. Explore Workspaces

```bash
# List all workspaces
kubectl get workspaces

# Get workspace details
kubectl get workspace <name> -o yaml

# Short alias
kubectl get ws
```

**What this shows**: All workspaces defined in NKP.

**Example**:
```bash
kubectl get workspaces
```
```
NAME                        DISPLAY NAME                 AGE
kommander                   Default Workspace            7d
kommander-default-workspace kommander-default-workspace  7d
dm-dev-workspace           dm-dev-workspace              1d
```

---

### 5. Explore Workspace-Level Roles

```bash
# List all WorkspaceRoles in a specific workspace
kubectl get workspaceroles -n <workspace-namespace>

# Example for dm-dev-workspace
kubectl get workspaceroles -n dm-dev-workspace

# Get detailed permissions of a WorkspaceRole
kubectl describe workspacerole workspace-admin -n dm-dev-workspace

# List KommanderWorkspaceRoles
kubectl get kommanderworkspaceroles -n dm-dev-workspace
```

**What this shows**: Available roles within a specific workspace.

**Key WorkspaceRoles**:
| Role | Description |
|------|-------------|
| `workspace-admin` | Full admin within the workspace |
| `workspace-edit` | Can modify workspace resources |
| `workspace-view` | Read-only access to workspace |
| `workspace-cluster-admin` | Full admin on clusters in workspace |

---

### 6. Explore Workspace Role Bindings

```bash
# List VirtualGroupWorkspaceRoleBindings in a workspace
kubectl get virtualgroupworkspacerolebindings -n <workspace-namespace>

# List VirtualGroupKommanderWorkspaceRoleBindings
kubectl get virtualgroupkommanderworkspacerolebindings -n <workspace-namespace>

# Get details of a binding
kubectl get virtualgroupworkspacerolebinding <name> -n <namespace> -o yaml
```

**What this shows**: Which VirtualGroups have access to which workspace roles.

**Example**:
```bash
kubectl get virtualgroupworkspacerolebindings -n dm-dev-workspace
```
```
NAME                                        AGE
dm-dev-workspace-admins-workspace-admin    1h
superheros-workspace-admin                  1d
```

---

### 7. Explore Projects

```bash
# List all projects in all namespaces
kubectl get projects -A

# List projects in a specific workspace
kubectl get projects -n <workspace-namespace>

# Get project details
kubectl describe project <name> -n <workspace-namespace>
```

**What this shows**: All projects and which workspace they belong to.

**Example**:
```bash
kubectl get projects -A
```
```
NAMESPACE          NAME             DISPLAY NAME     PROJECT NAMESPACE   AGE
dm-dev-workspace   dm-dev-project   dm-dev-project   dm-dev-project      1d
```

---

### 8. Explore Project-Level Roles

```bash
# List ProjectRoles in a project
kubectl get projectroles -n <project-namespace>

# Example
kubectl get projectroles -n dm-dev-project

# List KommanderProjectRoles
kubectl get kommanderprojectroles -n <project-namespace>

# Get details
kubectl describe projectrole project-app-deployer -n dm-dev-project
```

**What this shows**: Available roles within a specific project.

**Key ProjectRoles**:
| Role | Description |
|------|-------------|
| `project-app-deployer` | Can deploy applications |
| `project-config-manager` | Can manage configurations |
| `project-auditor` | Read-only audit access |

---

### 9. Explore Project Role Bindings

```bash
# List VirtualGroupProjectRoleBindings
kubectl get virtualgroupprojectrolebindings -n <project-namespace>

# List VirtualGroupKommanderProjectRoleBindings
kubectl get virtualgroupkommanderprojectrolebindings -n <project-namespace>

# Get details
kubectl get virtualgroupprojectrolebinding <name> -n <namespace> -o yaml
```

**What this shows**: Which VirtualGroups have access to which project roles.

---

### 10. Full RBAC Audit Commands

```bash
# See ALL RBAC resources across all levels
kubectl get virtualgroups,virtualgroupkommanderclusterrolebindings

# See all workspace-level RBAC in a namespace
kubectl get workspaceroles,kommanderworkspaceroles,virtualgroupworkspacerolebindings,virtualgroupkommanderworkspacerolebindings -n dm-dev-workspace

# See all project-level RBAC in a namespace
kubectl get projectroles,kommanderprojectroles,virtualgroupprojectrolebindings,virtualgroupkommanderprojectrolebindings -n dm-dev-project

# Export all RBAC for backup/review
kubectl get virtualgroups -o yaml > virtualgroups-backup.yaml
kubectl get virtualgroupkommanderclusterrolebindings -o yaml > global-bindings-backup.yaml
```

---

### 11. Understanding CRD Schema

```bash
# Get schema/structure for any CRD
kubectl explain virtualgroup
kubectl explain virtualgroup.spec
kubectl explain virtualgroup.spec.subjects

kubectl explain virtualgroupworkspacerolebinding
kubectl explain virtualgroupworkspacerolebinding.spec

kubectl explain virtualgroupprojectrolebinding
kubectl explain virtualgroupprojectrolebinding.spec
```

**What this shows**: The structure and fields of each CRD.

---

## Practical Examples

### Example 1: Create a Super Admin (Global Admin)

A super admin needs **three** bindings for full access:

```yaml
# Step 1: Create VirtualGroup (maps certificate CN to NKP)
apiVersion: kommander.mesosphere.io/v1beta1
kind: VirtualGroup
metadata:
  name: platform-admins
  annotations:
    kommander.mesosphere.io/display-name: Platform Super Admins
spec:
  subjects:
    # For certificate-based auth (CN must be "platform-admin")
    - apiGroup: rbac.authorization.k8s.io
      kind: User
      name: platform-admin
    # For OIDC (uncomment if using IDP):
    # - apiGroup: rbac.authorization.k8s.io
    #   kind: Group
    #   name: oidc:platform-admins
---
# Step 2: Bind to cluster-admin (Kubernetes native super admin)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins-cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: platform-admin  # Must match certificate CN
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
---
# Step 3: Bind to kommander-admin (NKP/Kommander resources)
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupKommanderClusterRoleBinding
metadata:
  name: platform-admins-kommander-admin
spec:
  clusterRoleRef:
    name: kommander-admin
  virtualGroupRef:
    name: platform-admins
---
# Step 4: Bind to dkp-kommander-admin (DKP UI access)
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupKommanderClusterRoleBinding
metadata:
  name: platform-admins-dkp-admin
spec:
  clusterRoleRef:
    name: dkp-kommander-admin
  virtualGroupRef:
    name: platform-admins
```

**Test Super Admin Access:**
```bash
# Create the user first
./scripts/create-k8s-user.sh platform-admin

# Test Kubernetes access
kubectl --kubeconfig=./generated-kubeconfigs/platform-admin.kubeconfig get nodes
kubectl --kubeconfig=./generated-kubeconfigs/platform-admin.kubeconfig get secrets -A

# Test NKP/Kommander access
kubectl --kubeconfig=./generated-kubeconfigs/platform-admin.kubeconfig get workspaces
kubectl --kubeconfig=./generated-kubeconfigs/platform-admin.kubeconfig get projects -A
```

### Example 2: Create a Workspace Admin

```yaml
# VirtualGroup is already created globally (see virtualgroups.yaml)
# This example shows the workspace-level bindings only

# Bind to workspace-admin role
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupWorkspaceRoleBinding
metadata:
  name: dm-dev-workspace-admins-workspace-admin
  namespace: dm-dev-workspace   # Target workspace
spec:
  placement:
    clusterSelector: {}         # Apply to all clusters in workspace
  virtualGroupRef:
    name: dm-dev-workspace-admins  # Reference to VirtualGroup
  workspaceRoleRef:
    name: workspace-admin          # Built-in role
---
# Also bind to kommander-workspace-admin for full NKP workspace features
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupKommanderWorkspaceRoleBinding
metadata:
  name: dm-dev-workspace-admins-kommander-admin
  namespace: dm-dev-workspace
spec:
  placement:
    clusterSelector: {}
  virtualGroupRef:
    name: dm-dev-workspace-admins
  kommanderWorkspaceRoleRef:
    name: kommander-workspace-admin
```

**Test Workspace Admin Access:**
```bash
# Create the user first
./scripts/create-k8s-user.sh dm-dev-workspace-admin

# Test workspace access
kubectl --kubeconfig=./generated-kubeconfigs/dm-dev-workspace-admin.kubeconfig \
    get workspaceroles -n dm-dev-workspace

kubectl --kubeconfig=./generated-kubeconfigs/dm-dev-workspace-admin.kubeconfig \
    get projects -n dm-dev-workspace

# Should FAIL - no access to other workspaces
kubectl --kubeconfig=./generated-kubeconfigs/dm-dev-workspace-admin.kubeconfig \
    get workspaceroles -n kommander
```

### Example 3: Create a Project Admin

```yaml
# VirtualGroup is already created globally (see virtualgroups.yaml)
# This example shows the project-level bindings only

# Bind to project roles for app deployment
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupProjectRoleBinding
metadata:
  name: dm-dev-project-admins-app-deployer
  namespace: dm-dev-project     # Target project namespace
spec:
  virtualGroupRef:
    name: dm-dev-project-admins   # Reference to VirtualGroup
  projectRoleRef:
    name: project-app-deployer    # Built-in role
---
# Bind to project-config-manager for configuration management
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupProjectRoleBinding
metadata:
  name: dm-dev-project-admins-config-manager
  namespace: dm-dev-project
spec:
  virtualGroupRef:
    name: dm-dev-project-admins
  projectRoleRef:
    name: project-config-manager
```

**Test Project Admin Access:**
```bash
# Create the user first
./scripts/create-k8s-user.sh dm-dev-project-admin

# Test project access
kubectl --kubeconfig=./generated-kubeconfigs/dm-dev-project-admin.kubeconfig \
    get projectroles -n dm-dev-project

kubectl --kubeconfig=./generated-kubeconfigs/dm-dev-project-admin.kubeconfig \
    get pods -n dm-dev-project

# Should FAIL - no access to workspace level
kubectl --kubeconfig=./generated-kubeconfigs/dm-dev-project-admin.kubeconfig \
    get workspaceroles -n dm-dev-workspace

# Should FAIL - no access to other namespaces
kubectl --kubeconfig=./generated-kubeconfigs/dm-dev-project-admin.kubeconfig \
    get pods -n default
```

### Quick Summary: User Permissions

| User | Command to Create | Can Access |
|------|-------------------|------------|
| `dm-k8s-admin` | `./scripts/create-k8s-user.sh dm-k8s-admin` | Everything (Super Admin) |
| `dm-dev-workspace-admin` | `./scripts/create-k8s-user.sh dm-dev-workspace-admin` | dm-dev-workspace + its projects |
| `dm-dev-project-admin` | `./scripts/create-k8s-user.sh dm-dev-project-admin` | dm-dev-project only |

---

## Troubleshooting

### Common Issues and Solutions

#### 1. "User cannot access workspace"

```bash
# Check if VirtualGroup exists
kubectl get virtualgroups | grep <expected-group>

# Check if user is in VirtualGroup
kubectl get virtualgroup <name> -o yaml | grep -A 10 subjects

# Check workspace role bindings
kubectl get virtualgroupworkspacerolebindings -n <workspace>
```

#### 2. "User has global access but no workspace access"

```bash
# Global bindings don't automatically give workspace access
# You may need both:
kubectl get virtualgroupkommanderclusterrolebindings | grep <user>
kubectl get virtualgroupworkspacerolebindings -n <workspace> | grep <user>
```

#### 3. "Permission denied on specific resource"

```bash
# Check what permissions the role actually has
kubectl describe workspacerole <role-name> -n <workspace>

# Check if user has the right binding
kubectl get virtualgroupworkspacerolebindings -n <workspace> -o yaml
```

#### 4. "VirtualGroup not syncing"

```bash
# Check VirtualGroup status
kubectl describe virtualgroup <name>

# Check Kommander controller logs
kubectl logs -n kommander -l app=kommander-cm --tail=100
```

### Debug Commands Cheatsheet

```bash
# Who has global admin access?
kubectl get virtualgroupkommanderclusterrolebindings -o custom-columns=NAME:.metadata.name,VIRTUALGROUP:.spec.virtualGroupRef.name,ROLE:.spec.clusterRoleRef.name

# Who has workspace admin access?
kubectl get virtualgroupworkspacerolebindings -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,VIRTUALGROUP:.spec.virtualGroupRef.name,ROLE:.spec.workspaceRoleRef.name

# Who has project access?
kubectl get virtualgroupprojectrolebindings -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,VIRTUALGROUP:.spec.virtualGroupRef.name,ROLE:.spec.projectRoleRef.name

# What users are in a VirtualGroup?
kubectl get virtualgroup <name> -o jsonpath='{.spec.subjects[*].name}'
```

---

## Quick Reference Card

### RBAC Hierarchy

```
Global Admin ──────► All Workspaces ──────► All Projects
                            │
Workspace Admin ───► One Workspace ───────► All Projects in WS
                            │
Project Admin ─────────────────────────────► One Project Only
```

### CRD Quick Reference

| What You Want | CRD to Use |
|--------------|------------|
| Map IdP users to NKP | `VirtualGroup` |
| Give global access | `VirtualGroupKommanderClusterRoleBinding` |
| Give workspace access | `VirtualGroupWorkspaceRoleBinding` |
| Give project access | `VirtualGroupProjectRoleBinding` |
| See workspace roles | `WorkspaceRole` |
| See project roles | `ProjectRole` |

### Essential kubectl Commands

```bash
# List identity mappings
kubectl get virtualgroups

# List global access
kubectl get virtualgroupkommanderclusterrolebindings

# List workspace access
kubectl get virtualgroupworkspacerolebindings -n <workspace>

# List project access
kubectl get virtualgroupprojectrolebindings -n <project>

# Understand a CRD
kubectl explain <crd-name>.spec
```

---

## File Structure in This Repository

```
region-usa/az1/management-cluster/
├── global/
│   └── rbac/
│       ├── virtualgroups.yaml              # All VirtualGroup definitions
│       ├── global-admin-rolebinding.yaml   # Global-level bindings
│       └── kustomization.yaml
│
└── workspaces/
    └── dm-dev-workspace/
        ├── rbac/
        │   ├── dm-dev-workspace-admin-rolebindings.yaml  # Workspace bindings
        │   └── kustomization.yaml
        │
        └── projects/
            └── dm-dev-project/
                └── rbac/
                    ├── dm-dev-project-admin-rolebindings.yaml  # Project bindings
                    └── kustomization.yaml
```

---

## Verification Script & Sample Output

### Running the Verification Script

After creating users with `create-k8s-user.sh`, use the verification script to test permissions:

```bash
# Run verification script
./scripts/verify-rbac-users.sh /Users/deepak.muley/ws/nkp

# Or with default path
./scripts/verify-rbac-users.sh
```

### Sample Output (All Tests Passing)

```
╔═══════════════════════════════════════════════════════════════╗
║          NKP RBAC User Verification Script                    ║
╚═══════════════════════════════════════════════════════════════╝

Kubeconfig Directory: /Users/deepak.muley/ws/nkp

═══════════════════════════════════════════════════════════════
  SUPER ADMIN: dm-k8s-admin
═══════════════════════════════════════════════════════════════
  Authenticated as: dm-k8s-admin

─── Kubernetes Cluster Access (cluster-admin) ───
  ✅ Get nodes                                          (expected: yes, got: yes)
  ✅ Get PVs                                            (expected: yes, got: yes)
  ✅ Get secrets (all namespaces)                       (expected: yes, got: yes)
  ✅ Create namespaces                                  (expected: yes, got: yes)
  ✅ Delete pods (kube-system)                          (expected: yes, got: yes)
  ✅ All permissions (*)                                (expected: yes, got: yes)

─── NKP/Kommander Access (kommander-admin) ───
  ✅ Get workspaces                                     (expected: yes, got: yes)
  ✅ Create workspaces                                  (expected: yes, got: yes)
  ✅ Get projects (all)                                 (expected: yes, got: yes)
  ✅ Get virtualgroups                                  (expected: yes, got: yes)
  ✅ Get appdeployments                                 (expected: yes, got: yes)
  ✅ Get kommanderclusters                              (expected: yes, got: yes)

═══════════════════════════════════════════════════════════════
  WORKSPACE ADMIN: dm-dev-workspace-admin
═══════════════════════════════════════════════════════════════
  Authenticated as: dm-dev-workspace-admin

─── Workspace Access (dm-dev-workspace) - SHOULD HAVE ───
  ✅ Get workspaceroles (dm-dev-workspace)              (expected: yes, got: yes)
  ✅ Get projects (dm-dev-workspace)                    (expected: yes, got: yes)
  ✅ Get pods (dm-dev-workspace)                        (expected: yes, got: yes)
  ✅ Create configmaps (dm-dev-workspace)               (expected: yes, got: yes)
  ✅ Get secrets (dm-dev-workspace)                     (expected: yes, got: yes)

─── Cluster-Level Access - SHOULD NOT HAVE ───
  ✅ Get nodes (cluster-level)                          (expected: no , got: no )
  ✅ Get PVs (cluster-level)                            (expected: no , got: no )
  ✅ Get namespaces (all)                               (expected: no , got: no )
  ✅ Create namespaces                                  (expected: no , got: no )

─── Other Workspaces - SHOULD NOT HAVE ───
  ✅ List workspaces (global)                           (expected: no , got: no )
  ✅ Create workspaces (global)                         (expected: no , got: no )
  ✅ Delete workspaces (global)                         (expected: no , got: no )
  ✅ Get workspaceroles (kommander)                     (expected: no , got: no )
  ✅ Get pods (kommander)                               (expected: no , got: no )
  ✅ Get pods (kommander-default-ws)                    (expected: no , got: no )

─── System Namespaces - SHOULD NOT HAVE ───
  ✅ Get secrets (kube-system)                          (expected: no , got: no )
  ✅ Get pods (kube-system)                             (expected: no , got: no )
  ✅ Get pods (default)                                 (expected: no , got: no )

─── Global Resources - SHOULD NOT HAVE ───
  ✅ Get virtualgroups (global)                         (expected: no , got: no )
  ✅ Create virtualgroups (global)                      (expected: no , got: no )
  ✅ Get clusterroles                                   (expected: no , got: no )

═══════════════════════════════════════════════════════════════
  PROJECT ADMIN: dm-dev-project-admin
═══════════════════════════════════════════════════════════════
  Authenticated as: dm-dev-project-admin

─── Project Access (dm-dev-project) - SHOULD HAVE ───
  ✅ Get pods (dm-dev-project)                          (expected: yes, got: yes)
  ✅ Get projectroles (dm-dev-project)                  (expected: yes, got: yes)
  ✅ Create configmaps (dm-dev-project)                 (expected: yes, got: yes)
  ✅ Get secrets (dm-dev-project)                       (expected: yes, got: yes)
  ✅ Create deployments (dm-dev-project)                (expected: yes, got: yes)

─── Cluster-Level Access - SHOULD NOT HAVE ───
  ✅ Get nodes (cluster-level)                          (expected: no , got: no )
  ✅ Get PVs (cluster-level)                            (expected: no , got: no )
  ✅ Get namespaces (all)                               (expected: no , got: no )
  ✅ Create namespaces                                  (expected: no , got: no )

─── Workspaces - SHOULD NOT HAVE ───
  ✅ List workspaces (global)                           (expected: no , got: no )
  ✅ Create workspaces                                  (expected: no , got: no )
  ✅ Get workspaceroles (dm-dev-workspace)              (expected: no , got: no )

─── Parent Workspace (dm-dev-workspace) - SHOULD NOT HAVE ───
  ✅ Get pods (dm-dev-workspace)                        (expected: no , got: no )
  ✅ Get secrets (dm-dev-workspace)                     (expected: no , got: no )
  ✅ List projects (dm-dev-workspace)                   (expected: no , got: no )
  ✅ Create projects (dm-dev-workspace)                 (expected: no , got: no )

─── Other Workspaces - SHOULD NOT HAVE ───
  ✅ Get pods (kommander)                               (expected: no , got: no )
  ✅ Get pods (kommander-default-ws)                    (expected: no , got: no )

─── System Namespaces - SHOULD NOT HAVE ───
  ✅ Get pods (kube-system)                             (expected: no , got: no )
  ✅ Get secrets (kube-system)                          (expected: no , got: no )
  ✅ Get pods (default)                                 (expected: no , got: no )

─── Global Resources - SHOULD NOT HAVE ───
  ✅ Get virtualgroups (global)                         (expected: no , got: no )
  ✅ Get clusterroles                                   (expected: no , got: no )
  ✅ Get appdeployments (all)                           (expected: no , got: no )

═══════════════════════════════════════════════════════════════
  TEST SUMMARY
═══════════════════════════════════════════════════════════════

  Total Tests:  57
  Passed:       57
  Failed:       0

╔═══════════════════════════════════════════════════════════════╗
║                    ALL TESTS PASSED! ✅                        ║
╚═══════════════════════════════════════════════════════════════╝
```

### Understanding the Test Results

| User | Positive Tests | Negative Tests | Total | What's Verified |
|------|----------------|----------------|-------|-----------------|
| **dm-k8s-admin** | 12 | 0 | 12 | Full K8s cluster-admin + NKP kommander-admin access |
| **dm-dev-workspace-admin** | 5 | 17 | 22 | Access ONLY to dm-dev-workspace, denied everywhere else |
| **dm-dev-project-admin** | 5 | 18 | 23 | Access ONLY to dm-dev-project, denied everywhere else |

### Negative Tests Coverage

**Workspace Admin cannot:**
- List/create/delete workspaces globally
- Access other workspaces (kommander, kommander-default-workspace)
- Access system namespaces (kube-system, default)
- Access global resources (virtualgroups, clusterroles, nodes, PVs)

**Project Admin cannot:**
- List/create workspaces
- Access parent workspace (dm-dev-workspace) resources
- List/create other projects
- Access other workspaces (kommander, etc.)
- Access system namespaces
- Access global resources (virtualgroups, clusterroles, appdeployments)

### Kubeconfig Locations

After running `create-k8s-user.sh`, kubeconfigs are stored at:

```
/Users/deepak.muley/ws/nkp/
├── dm-k8s-admin.kubeconfig           # Super Admin
├── dm-k8s-admin.key                  # Private key (keep secure!)
├── dm-k8s-admin.crt                  # Certificate
├── dm-dev-workspace-admin.kubeconfig # Workspace Admin
├── dm-dev-workspace-admin.key
├── dm-dev-workspace-admin.crt
├── dm-dev-project-admin.kubeconfig   # Project Admin
├── dm-dev-project-admin.key
└── dm-dev-project-admin.crt
```

### Quick Test Commands

```bash
# Test Super Admin
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-k8s-admin.kubeconfig auth can-i '*' '*'
# Expected: yes

# Test Workspace Admin
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-dev-workspace-admin.kubeconfig \
    auth can-i get pods -n dm-dev-workspace
# Expected: yes

kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-dev-workspace-admin.kubeconfig \
    auth can-i get nodes
# Expected: no

# Test Project Admin
kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-dev-project-admin.kubeconfig \
    auth can-i get pods -n dm-dev-project
# Expected: yes

kubectl --kubeconfig=/Users/deepak.muley/ws/nkp/dm-dev-project-admin.kubeconfig \
    auth can-i get pods -n dm-dev-workspace
# Expected: no
```

---

## Additional Resources

- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [NKP/DKP Official Documentation](https://docs.d2iq.com/dkp/latest/)
- [Kommander RBAC Guide](https://docs.d2iq.com/dkp/latest/access-control)

