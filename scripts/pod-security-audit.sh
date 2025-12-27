#!/bin/bash

# Pod Security Audit Tool
# Comprehensive security testing for Kubernetes pods
# Usage: ./pod-security-audit.sh --namespace <ns> --pod <pod> [options]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""
POD_NAME=""
TEST_TYPE="all"
# Preserve KUBECONFIG from environment if set, otherwise empty
# This will be overridden by --kubeconfig flag if provided
KUBECONFIG_SCRIPT="${KUBECONFIG:-}"
EXPORT_FILE=""
BEFORE_SCORE=""
AFTER_SCORE=""

# Print usage
usage() {
    cat << EOF
${CYAN}Pod Security Audit Tool${NC}

Usage: $0 --namespace <namespace> --pod <pod-name> [options]

Required Arguments:
  --namespace, -n <namespace>    Kubernetes namespace
  --pod, -p <pod-name>          Name of the pod to test

Optional Arguments:
  --test-type, -t <type>        Type of test to run (default: all)
                                Options:
                                  escape      - Container escape attempts
                                  hardening   - Security hardening checks
                                  context     - Security context analysis
                                  all         - Run all tests
  --kubeconfig, -k <path>       Path to kubeconfig file
  --export, -o <file>           Export fixed YAML to file (Pod or Deployment)
  --help, -h                     Show this help message

Examples:
  $0 --namespace default --pod my-pod --test-type escape
  $0 -n kommander -p kommander-appmanagement-xxx -t all
  $0 --namespace default --pod test-pod --test-type hardening --kubeconfig /path/to/kubeconfig
  $0 -n kommander -p my-pod -k /Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf
  $0 -n kommander -p my-pod --export fixed-pod.yaml
  $0 -n default -p my-pod -o deployment-fixed.yaml

EOF
    exit 1
}

# Print section header
print_section() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

# Print test result
print_result() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗${NC} $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${CYAN}ℹ${NC} $message"
    else
        echo -e "  $message"
    fi
}

# Check if pod exists
check_pod() {
    # First, check if we can connect to the cluster
    local cluster_check
    if [ -n "$KUBECONFIG_ARG" ]; then
        cluster_check=$(kubectl ${KUBECONFIG_ARG} cluster-info &>/dev/null; echo $?)
    else
        cluster_check=$(kubectl cluster-info &>/dev/null; echo $?)
    fi

    if [ "$cluster_check" -ne 0 ]; then
        print_result "FAIL" "Cannot connect to Kubernetes cluster"
        if [ -z "$KUBECONFIG" ]; then
            print_result "INFO" "Hint: Use --kubeconfig flag to specify kubeconfig file"
            print_result "INFO" "Example: $0 --namespace $NAMESPACE --pod $POD_NAME --kubeconfig /path/to/kubeconfig"
        fi
        exit 1
    fi

    # Now check if pod exists
    local pod_check
    if [ -n "$KUBECONFIG_ARG" ]; then
        pod_check=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" 2>&1)
    else
        pod_check=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" 2>&1)
    fi

    if echo "$pod_check" | grep -q "NotFound\|not found"; then
        print_result "FAIL" "Pod '$POD_NAME' not found in namespace '$NAMESPACE'"
        # Try to list pods in the namespace to help user
        print_result "INFO" "Checking available pods in namespace '$NAMESPACE'..."
        if [ -n "$KUBECONFIG_ARG" ]; then
            kubectl ${KUBECONFIG_ARG} get pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -10 | awk '{print "  - " $1}' || true
        else
            kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -10 | awk '{print "  - " $1}' || true
        fi
        exit 1
    elif echo "$pod_check" | grep -q "error\|Error"; then
        print_result "FAIL" "Error checking pod: $(echo "$pod_check" | head -1)"
        exit 1
    fi

    print_result "INFO" "Pod found: $POD_NAME in namespace $NAMESPACE"
}

# Get pod security context
get_security_context() {
    kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o json | \
        jq -r '.spec | {
            runAsUser: .securityContext.runAsUser,
            runAsGroup: .securityContext.runAsGroup,
            runAsNonRoot: .securityContext.runAsNonRoot,
            fsGroup: .securityContext.fsGroup,
            seccompProfile: .securityContext.seccompProfile.type,
            hostPID: .hostPID,
            hostIPC: .hostIPC,
            hostNetwork: .hostNetwork,
            containers: [.containers[] | {
                name: .name,
                runAsUser: .securityContext.runAsUser,
                runAsNonRoot: .securityContext.runAsNonRoot,
                privileged: .securityContext.privileged,
                allowPrivilegeEscalation: .securityContext.allowPrivilegeEscalation,
                readOnlyRootFilesystem: .securityContext.readOnlyRootFilesystem,
                capabilities: .securityContext.capabilities
            }]
        }'
}

# Test 1: Security Context Analysis
test_security_context() {
    print_section "Security Context Analysis"

    local context=$(get_security_context)
    local pod_user=$(echo "$context" | jq -r '.runAsUser // "not set"')
    local pod_nonroot=$(echo "$context" | jq -r '.runAsNonRoot // "not set"')
    local host_pid=$(echo "$context" | jq -r '.hostPID // false')
    local host_ipc=$(echo "$context" | jq -r '.hostIPC // false')
    local host_net=$(echo "$context" | jq -r '.hostNetwork // false')

    # Pod-level checks
    echo -e "${CYAN}Pod-Level Security Context:${NC}"
    if [ "$pod_user" != "not set" ] && [ "$pod_user" != "null" ]; then
        if [ "$pod_user" = "0" ]; then
            print_result "FAIL" "Pod runs as root (UID: $pod_user)"
        else
            print_result "PASS" "Pod runs as non-root (UID: $pod_user)"
        fi
    elif [ "$pod_nonroot" = "true" ]; then
        print_result "PASS" "Pod has runAsNonRoot: true"
    else
        print_result "WARN" "Pod security context not explicitly set (may default to root)"
    fi

    [ "$host_pid" = "true" ] && print_result "FAIL" "hostPID is enabled (security risk)" || print_result "PASS" "hostPID is disabled"
    [ "$host_ipc" = "true" ] && print_result "FAIL" "hostIPC is enabled (security risk)" || print_result "PASS" "hostIPC is disabled"
    [ "$host_net" = "true" ] && print_result "WARN" "hostNetwork is enabled" || print_result "PASS" "hostNetwork is disabled"

    # Container-level checks
    echo -e "\n${CYAN}Container-Level Security Context:${NC}"
    local container_count=$(echo "$context" | jq '.containers | length')
    for ((i=0; i<container_count; i++)); do
        local container=$(echo "$context" | jq -r ".containers[$i]")
        local name=$(echo "$container" | jq -r '.name')
        local privileged=$(echo "$container" | jq -r '.privileged // false')
        local allow_priv_esc=$(echo "$container" | jq -r '.allowPrivilegeEscalation // "not set"')
        local readonly_root=$(echo "$container" | jq -r '.readOnlyRootFilesystem // false')
        local caps=$(echo "$container" | jq -r '.capabilities // "not set"')

        echo -e "\n  ${CYAN}Container: $name${NC}"
        [ "$privileged" = "true" ] && print_result "FAIL" "Container is privileged" || print_result "PASS" "Container is not privileged"

        if [ "$allow_priv_esc" = "true" ]; then
            print_result "FAIL" "Privilege escalation allowed"
        elif [ "$allow_priv_esc" = "false" ]; then
            print_result "PASS" "Privilege escalation disabled"
        else
            print_result "WARN" "Privilege escalation not explicitly set"
        fi

        [ "$readonly_root" = "true" ] && print_result "PASS" "Root filesystem is read-only" || print_result "WARN" "Root filesystem is writable"

        if [ "$caps" != "not set" ] && [ "$caps" != "null" ]; then
            local add_caps=$(echo "$caps" | jq -r '.add // [] | length')
            local drop_caps=$(echo "$caps" | jq -r '.drop // [] | length')
            if [ "$add_caps" -gt 0 ]; then
                print_result "WARN" "Container has $add_caps added capabilities"
            fi
            if [ "$drop_caps" -gt 0 ]; then
                print_result "PASS" "Container drops $drop_caps capabilities"
            fi
        else
            print_result "WARN" "Capabilities not explicitly configured"
        fi
    done
}

# Test 2: Hardening Checks
test_hardening() {
    print_section "Security Hardening Checks"

    # Check if running as root
    local current_user=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'id -u' 2>/dev/null || echo "unknown")
    if [ "$current_user" = "0" ]; then
        print_result "FAIL" "Container is running as root (UID: 0)"
    else
        print_result "PASS" "Container is running as non-root (UID: $current_user)"
    fi

    # Check capabilities
    local caps=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'cat /proc/self/status | grep Cap' 2>/dev/null || echo "")
    if [ -n "$caps" ]; then
        local cap_eff=$(echo "$caps" | grep "CapEff:" | awk '{print $2}')
        if [ "$cap_eff" = "0000000000000000" ]; then
            print_result "PASS" "All effective capabilities are dropped"
        else
            print_result "WARN" "Container has effective capabilities: $cap_eff"
        fi
    fi

    # Check for dangerous binaries
    echo -e "\n${CYAN}Checking for dangerous binaries:${NC}"
    local dangerous_bins=("nsenter" "chroot" "mount" "unshare" "setcap" "getcap")
    for bin in "${dangerous_bins[@]}"; do
        if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c "which $bin" &>/dev/null; then
            print_result "WARN" "$bin is available in container"
        else
            print_result "PASS" "$bin is not available"
        fi
    done

    # Check seccomp
    local seccomp=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'cat /proc/self/status | grep Seccomp' 2>/dev/null || echo "")
    if [ -n "$seccomp" ]; then
        local seccomp_val=$(echo "$seccomp" | grep "Seccomp:" | awk '{print $2}')
        if [ "$seccomp_val" = "2" ]; then
            print_result "PASS" "Seccomp is enabled (filter mode)"
        elif [ "$seccomp_val" = "1" ]; then
            print_result "WARN" "Seccomp is in strict mode"
        else
            print_result "WARN" "Seccomp status: $seccomp_val"
        fi
    fi

    # Check AppArmor/SELinux
    local no_new_privs=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'cat /proc/self/status | grep NoNewPrivs' 2>/dev/null || echo "")
    if [ -n "$no_new_privs" ]; then
        local nnpr=$(echo "$no_new_privs" | grep "NoNewPrivs:" | awk '{print $2}')
        [ "$nnpr" = "1" ] && print_result "PASS" "NoNewPrivs is enabled" || print_result "WARN" "NoNewPrivs is disabled"
    fi
}

# Test 3: Container Escape Attempts
test_escape() {
    print_section "Container Escape Attempts"

    # Test 1: Check for host namespace access
    echo -e "${CYAN}Test 1: Host Namespace Access${NC}"
    if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'test -d /proc/1/ns/pid' &>/dev/null; then
        if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'readlink /proc/1/ns/pid' &>/dev/null; then
            print_result "WARN" "Can access host PID namespace symlinks"
        else
            print_result "PASS" "Cannot read host namespace symlinks (Permission denied)"
        fi
    else
        print_result "PASS" "Cannot access host namespace directories"
    fi

    # Test 2: nsenter attempt
    echo -e "\n${CYAN}Test 2: nsenter to Host Namespace${NC}"
    if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'which nsenter' &>/dev/null; then
        if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'nsenter --target 1 --mount --pid --uts --ipc --net sh -c "hostname"' &>/dev/null 2>&1; then
            print_result "FAIL" "SUCCESSFULLY ESCAPED to host namespace via nsenter"
        else
            print_result "PASS" "nsenter escape blocked (Operation not permitted)"
        fi
    else
        print_result "PASS" "nsenter not available"
    fi

    # Test 3: User namespace unshare
    echo -e "\n${CYAN}Test 3: User Namespace Privilege Escalation${NC}"
    if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'which unshare' &>/dev/null; then
        local unshare_result=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'unshare -r sh -c "id -u"' 2>&1)
        if [ "$unshare_result" = "0" ]; then
            print_result "WARN" "Can create user namespace with root (UID 0) - partial privilege escalation"
            # Check if we can do anything useful
            if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'unshare -r -m sh -c "mount -t tmpfs tmpfs /tmp/test && echo success"' &>/dev/null 2>&1; then
                print_result "WARN" "Can mount tmpfs in user namespace"
            fi
        else
            print_result "PASS" "User namespace creation blocked or ineffective"
        fi
    else
        print_result "PASS" "unshare not available"
    fi

    # Test 4: Host filesystem access via /proc
    echo -e "\n${CYAN}Test 4: Host Filesystem Access${NC}"
    if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'test -d /proc/1/root' &>/dev/null; then
        local host_root=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'ls /proc/1/root/etc 2>&1 | head -1' 2>/dev/null)
        if [ -n "$host_root" ] && [[ ! "$host_root" =~ "Permission denied" ]] && [[ ! "$host_root" =~ "No such file" ]]; then
            print_result "WARN" "Can access host filesystem via /proc/1/root"
        else
            print_result "PASS" "Host filesystem access via /proc blocked"
        fi
    else
        print_result "PASS" "Cannot access /proc/1/root"
    fi

    # Test 5: Overlay filesystem inspection
    echo -e "\n${CYAN}Test 5: Overlay Filesystem Inspection${NC}"
    local overlay_info=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'cat /proc/self/mountinfo | grep overlay' 2>/dev/null || echo "")
    if [ -n "$overlay_info" ]; then
        local upperdir=$(echo "$overlay_info" | grep -o 'upperdir=[^,]*' | cut -d= -f2 | head -1)
        if [ -n "$upperdir" ]; then
            print_result "INFO" "Overlay upperdir path exposed: $upperdir"
            # Try to access it
            if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c "test -d $upperdir" &>/dev/null 2>&1; then
                print_result "WARN" "Can access overlay filesystem directory"
            else
                print_result "PASS" "Overlay directory not accessible from container"
            fi
        fi
    fi

    # Test 6: Docker/containerd socket access
    echo -e "\n${CYAN}Test 6: Container Runtime Socket Access${NC}"
    local sockets=("/var/run/docker.sock" "/var/run/containerd/containerd.sock" "/run/containerd/containerd.sock")
    local socket_found=false
    for socket in "${sockets[@]}"; do
        if kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c "test -S $socket" &>/dev/null 2>&1; then
            print_result "FAIL" "Container runtime socket accessible: $socket"
            socket_found=true
        fi
    done
    [ "$socket_found" = "false" ] && print_result "PASS" "No container runtime sockets accessible"

    # Test 7: HostPath volume mounts
    echo -e "\n${CYAN}Test 7: HostPath Volume Mounts${NC}"
    local volumes=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].hostPath.path}' 2>/dev/null || echo "")
    if [ -n "$volumes" ]; then
        print_result "WARN" "Pod has hostPath volumes: $volumes"
    else
        print_result "PASS" "No hostPath volumes mounted"
    fi
}

# Generate recommendations
generate_recommendations() {
    print_section "Security Recommendations"

    local context=$(get_security_context)
    local pod_user=$(echo "$context" | jq -r '.runAsUser // "not set"')
    local pod_nonroot=$(echo "$context" | jq -r '.runAsNonRoot // "not set"')
    local host_pid=$(echo "$context" | jq -r '.hostPID // false')
    local host_ipc=$(echo "$context" | jq -r '.hostIPC // false')
    local host_net=$(echo "$context" | jq -r '.hostNetwork // false')

    echo -e "${CYAN}Recommended Security Context Configuration:${NC}\n"

    cat << EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
spec:
  securityContext:
    # Run as non-root user
    runAsNonRoot: true
    runAsUser: 65532  # or appropriate non-root UID
    runAsGroup: 65532
    fsGroup: 65532
    # Use seccomp profile
    seccompProfile:
      type: RuntimeDefault
    # Do not use host namespaces
    hostPID: false
    hostIPC: false
    hostNetwork: false
  containers:
  - name: <container-name>
    securityContext:
      # Explicitly disable privilege escalation
      allowPrivilegeEscalation: false
      # Run as non-root
      runAsNonRoot: true
      runAsUser: 65532
      # Read-only root filesystem
      readOnlyRootFilesystem: true
      # Drop all capabilities
      capabilities:
        drop:
          - ALL
      # Do not run privileged
      privileged: false
EOF

    echo -e "\n${CYAN}Specific Recommendations:${NC}\n"

    if [ "$pod_user" = "0" ] || [ "$pod_user" = "not set" ] || [ "$pod_user" = "null" ]; then
        print_result "WARN" "Set runAsNonRoot: true and runAsUser to a non-root UID (e.g., 65532)"
    fi

    if [ "$host_pid" = "true" ]; then
        print_result "WARN" "Disable hostPID unless absolutely necessary"
    fi

    if [ "$host_ipc" = "true" ]; then
        print_result "WARN" "Disable hostIPC unless absolutely necessary"
    fi

    if [ "$host_net" = "true" ]; then
        print_result "WARN" "Consider disabling hostNetwork if not required"
    fi

    local container_count=$(echo "$context" | jq '.containers | length')
    for ((i=0; i<container_count; i++)); do
        local container=$(echo "$context" | jq -r ".containers[$i]")
        local allow_priv_esc=$(echo "$container" | jq -r '.allowPrivilegeEscalation // "not set"')
        local readonly_root=$(echo "$container" | jq -r '.readOnlyRootFilesystem // false')

        if [ "$allow_priv_esc" != "false" ]; then
            print_result "WARN" "Set allowPrivilegeEscalation: false for all containers"
        fi

        if [ "$readonly_root" != "true" ]; then
            print_result "WARN" "Consider setting readOnlyRootFilesystem: true if possible"
        fi
    done
}

# Get owner resource (Deployment, StatefulSet, etc.)
get_owner_resource() {
    local owner_kind=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
    local owner_name=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")

    if [ -n "$owner_kind" ] && [ -n "$owner_name" ]; then
        # Handle ReplicaSet -> Deployment
        if [ "$owner_kind" = "ReplicaSet" ]; then
            local deployment=$(kubectl ${KUBECONFIG_ARG} get replicaset "$owner_name" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}' 2>/dev/null || echo "")
            if [ -n "$deployment" ]; then
                echo "Deployment|$deployment"
                return
            fi
        fi
        echo "${owner_kind}|${owner_name}"
    else
        echo "Pod|$POD_NAME"
    fi
}

# Export fixed YAML
export_fixed_yaml() {
    if [ -z "$EXPORT_FILE" ]; then
        return
    fi

    print_section "Exporting Fixed YAML"

    local owner_info=$(get_owner_resource)
    local resource_kind=$(echo "$owner_info" | cut -d'|' -f1)
    local resource_name=$(echo "$owner_info" | cut -d'|' -f2)

    print_result "INFO" "Detected resource: $resource_kind/$resource_name"

    # Get the resource as JSON (more reliable than YAML)
    local resource_json
    if [ "$resource_kind" = "Pod" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get pod "$resource_name" -n "$NAMESPACE" -o json 2>/dev/null)
    elif [ "$resource_kind" = "Deployment" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get deployment "$resource_name" -n "$NAMESPACE" -o json 2>/dev/null)
    elif [ "$resource_kind" = "StatefulSet" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get statefulset "$resource_name" -n "$NAMESPACE" -o json 2>/dev/null)
    elif [ "$resource_kind" = "DaemonSet" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get daemonset "$resource_name" -n "$NAMESPACE" -o json 2>/dev/null)
    else
        print_result "WARN" "Unsupported resource kind: $resource_kind. Exporting Pod YAML instead."
        resource_json=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
    fi

    if [ -z "$resource_json" ]; then
        print_result "FAIL" "Failed to get resource JSON"
        return
    fi

    # Get current security context
    local context=$(get_security_context)
    local pod_user=$(echo "$context" | jq -r '.runAsUser // "65532"')
    if [ "$pod_user" = "null" ] || [ "$pod_user" = "not set" ] || [ "$pod_user" = "0" ]; then
        pod_user="65532"
    fi

    # Use jq to modify JSON with security improvements
    local fixed_json=$(echo "$resource_json" | jq --arg uid "$pod_user" '
        # Remove status and runtime metadata
        del(.status) |
        del(.metadata.uid) |
        del(.metadata.resourceVersion) |
        del(.metadata.creationTimestamp) |
        del(.metadata.selfLink) |
        del(.metadata.managedFields) |
        del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration") |

        # Pod-level security context (only if spec exists and is an object)
        (if .spec and (.spec | type) == "object" then
            .spec.securityContext = ((.spec.securityContext // {}) | if type == "object" then . else {} end) |
            .spec.securityContext.runAsNonRoot = true |
            .spec.securityContext.runAsUser = ($uid | tonumber) |
            .spec.securityContext.runAsGroup = ($uid | tonumber) |
            .spec.securityContext.fsGroup = ($uid | tonumber) |
            .spec.securityContext.seccompProfile = {"type": "RuntimeDefault"} |
            .spec.hostPID = false |
            .spec.hostIPC = false |
            .spec.hostNetwork = false |

            # Container-level security context
            .spec.containers = ((.spec.containers // []) | if type == "array" then
                map(if type == "object" then
                    .securityContext = ((.securityContext // {}) | if type == "object" then . else {} end) |
                    .securityContext.allowPrivilegeEscalation = false |
                    .securityContext.runAsNonRoot = true |
                    .securityContext.runAsUser = ($uid | tonumber) |
                    .securityContext.readOnlyRootFilesystem = true |
                    .securityContext.privileged = false |
                    .securityContext.capabilities = {"drop": ["ALL"]}
                else . end)
            else . end)
        else . end) |

        # For Deployment/StatefulSet/DaemonSet, also update template
        (if .spec.template.spec and (.spec.template.spec | type) == "object" then
            .spec.template.spec.securityContext = ((.spec.template.spec.securityContext // {}) | if type == "object" then . else {} end) |
            .spec.template.spec.securityContext.runAsNonRoot = true |
            .spec.template.spec.securityContext.runAsUser = ($uid | tonumber) |
            .spec.template.spec.securityContext.runAsGroup = ($uid | tonumber) |
            .spec.template.spec.securityContext.fsGroup = ($uid | tonumber) |
            .spec.template.spec.securityContext.seccompProfile = {"type": "RuntimeDefault"} |
            .spec.template.spec.hostPID = false |
            .spec.template.spec.hostIPC = false |
            .spec.template.spec.hostNetwork = false |
            .spec.template.spec.containers = ((.spec.template.spec.containers // []) | if type == "array" then
                map(if type == "object" then
                    .securityContext = ((.securityContext // {}) | if type == "object" then . else {} end) |
                    .securityContext.allowPrivilegeEscalation = false |
                    .securityContext.runAsNonRoot = true |
                    .securityContext.runAsUser = ($uid | tonumber) |
                    .securityContext.readOnlyRootFilesystem = true |
                    .securityContext.privileged = false |
                    .securityContext.capabilities = {"drop": ["ALL"]}
                else . end)
            else . end)
        else . end)
    ' 2>&1)

    # Check if jq had errors
    if echo "$fixed_json" | jq empty 2>/dev/null; then
        # JSON is valid
        :
    else
        print_result "FAIL" "Failed to process JSON: $(echo "$fixed_json" | head -1)"
        return
    fi

    # Convert JSON to YAML - try kubectl first, fallback to yq or manual conversion
    if echo "$fixed_json" | kubectl ${KUBECONFIG_ARG} --local -f - -o yaml 2>/dev/null > "$EXPORT_FILE"; then
        # Success
        :
    elif command -v yq &> /dev/null; then
        # Use yq if available
        echo "$fixed_json" | yq eval -P '.' > "$EXPORT_FILE" 2>/dev/null || {
            print_result "WARN" "YAML conversion had issues. Check the output file."
        }
    else
        # Last resort: save as JSON and warn user
        echo "$fixed_json" | jq '.' > "${EXPORT_FILE%.yaml}.json" 2>/dev/null
        print_result "WARN" "Could not convert to YAML. JSON saved to: ${EXPORT_FILE%.yaml}.json"
        print_result "INFO" "Install yq for YAML output: brew install yq"
        return
    fi

    print_result "PASS" "Exported fixed YAML to: $EXPORT_FILE"
    print_result "INFO" "Review the file and make any necessary adjustments before applying"
    print_result "INFO" "Note: Some fields may need manual review (e.g., readOnlyRootFilesystem if app requires writes)"
}

# Scan resource with kubesec (before export)
scan_kubesec_before() {
    local owner_info=$(get_owner_resource)
    local resource_kind=$(echo "$owner_info" | cut -d'|' -f1)
    local resource_name=$(echo "$owner_info" | cut -d'|' -f2)

    print_section "Kubesec Security Scan - BEFORE Fixes"

    # Check if kubesec plugin is available
    if ! kubectl kubesec_scan --help &>/dev/null; then
        print_result "WARN" "kubesec plugin not found. Install with: kubectl krew install kubesec_scan"
        return 1
    fi

    # Run kubesec scan on the original resource
    # kubesec_scan uses KUBECONFIG env var, not --kubeconfig flag
    local scan_output
    local old_kubeconfig="${KUBECONFIG:-}"
    if [ -n "$KUBECONFIG" ]; then
        export KUBECONFIG
    fi

    if [ "$resource_kind" = "Deployment" ]; then
        scan_output=$(kubectl kubesec_scan deployment "$resource_name" -n "$NAMESPACE" 2>&1)
    elif [ "$resource_kind" = "Pod" ]; then
        scan_output=$(kubectl kubesec_scan pod "$resource_name" -n "$NAMESPACE" 2>&1)
    elif [ "$resource_kind" = "StatefulSet" ]; then
        scan_output=$(kubectl kubesec_scan statefulset "$resource_name" -n "$NAMESPACE" 2>&1)
    elif [ "$resource_kind" = "DaemonSet" ]; then
        scan_output=$(kubectl kubesec_scan daemonset "$resource_name" -n "$NAMESPACE" 2>&1)
    else
        print_result "WARN" "Unsupported resource kind for kubesec: $resource_kind"
        [ -n "$old_kubeconfig" ] && export KUBECONFIG="$old_kubeconfig" || unset KUBECONFIG
        return 1
    fi

    local exit_code=$?
    if [ -n "$old_kubeconfig" ]; then
        export KUBECONFIG="$old_kubeconfig"
    elif [ -z "$KUBECONFIG" ]; then
        unset KUBECONFIG
    fi

    if [ $exit_code -ne 0 ] || [ -z "$scan_output" ]; then
        print_result "WARN" "kubesec scan failed for original resource (exit code: $exit_code)"
        echo "$scan_output" | head -10
        return 1
    fi

    # Parse and display score
    parse_kubesec_output "$scan_output" "BEFORE"
    return 0
}

# Scan YAML with kubesec (after export)
scan_kubesec() {
    local yaml_file=$1

    if [ ! -f "$yaml_file" ]; then
        return
    fi

    print_section "Kubesec Security Scan - AFTER Fixes"

    # Check if kubesec plugin is available
    if ! kubectl kubesec_scan --help &>/dev/null; then
        print_result "WARN" "kubesec plugin not found. Install with: kubectl krew install kubesec_scan"
        print_result "INFO" "Skipping kubesec scan"
        return
    fi

    # Determine resource type from YAML
    local resource_kind=$(grep -E "^kind:" "$yaml_file" | head -1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
    local resource_name=$(grep -E "^  name:" "$yaml_file" | head -1 | awk '{print $2}')

    # Run kubesec scan based on resource type
    # Note: kubesec_scan uses KUBECONFIG env var, not --kubeconfig flag
    local scan_output
    local old_kubeconfig="${KUBECONFIG:-}"
    if [ -n "$KUBECONFIG" ]; then
        export KUBECONFIG
    fi

    if [ "$resource_kind" = "deployment" ]; then
        scan_output=$(kubectl kubesec_scan deployment "$resource_name" -n "$NAMESPACE" 2>&1)
    elif [ "$resource_kind" = "pod" ]; then
        scan_output=$(kubectl kubesec_scan pod "$resource_name" -n "$NAMESPACE" 2>&1)
    elif [ "$resource_kind" = "statefulset" ]; then
        scan_output=$(kubectl kubesec_scan statefulset "$resource_name" -n "$NAMESPACE" 2>&1)
    elif [ "$resource_kind" = "daemonset" ]; then
        scan_output=$(kubectl kubesec_scan daemonset "$resource_name" -n "$NAMESPACE" 2>&1)
    else
        print_result "WARN" "Unsupported resource kind for kubesec: $resource_kind"
        [ -n "$old_kubeconfig" ] && export KUBECONFIG="$old_kubeconfig" || unset KUBECONFIG
        return
    fi

    local exit_code=$?
    if [ -n "$old_kubeconfig" ]; then
        export KUBECONFIG="$old_kubeconfig"
    elif [ -z "$KUBECONFIG" ]; then
        unset KUBECONFIG
    fi

    if [ $exit_code -ne 0 ] || [ -z "$scan_output" ]; then
        print_result "WARN" "kubesec scan failed for exported YAML (exit code: $exit_code)"
        echo "$scan_output" | head -10
        return
    fi

    # Parse and display score
    parse_kubesec_output "$scan_output" "AFTER"
}

# Parse and display kubesec output
parse_kubesec_output() {
    local scan_output="$1"
    local stage="$2"  # "BEFORE" or "AFTER"

    # Parse kubesec output (text format: "kubesec.io score: X" or "kubesec.io score: -X")
    local score=$(echo "$scan_output" | grep -i "kubesec.io score:" | sed -E 's/.*kubesec\.io score: *(-?[0-9]+).*/\1/' | head -1)
    local max_score="9"  # kubesec typically has 9 checks

    if [ -z "$score" ]; then
        print_result "WARN" "Could not parse kubesec score from output"
        echo "$scan_output" | head -30
        return
    fi

    # Handle negative scores (critical issues)
    local is_negative=false
    if [[ "$score" =~ ^- ]]; then
        is_negative=true
        score="${score#-}"  # Remove negative sign for display
        print_result "FAIL" "CRITICAL: Negative kubesec score indicates severe security issues!"
    fi

    # Calculate percentage (only for positive scores)
    local score_percent="0"
    if [ "$is_negative" = "false" ]; then
        score_percent=$(echo "scale=0; ($score * 100) / $max_score" | bc 2>/dev/null || echo "0")
    fi

    # Store score for comparison (store as-is, including negative)
    if [ "$stage" = "BEFORE" ]; then
        BEFORE_SCORE=$(echo "$scan_output" | grep -i "kubesec.io score:" | sed -E 's/.*kubesec\.io score: *(-?[0-9]+).*/\1/' | head -1)
    elif [ "$stage" = "AFTER" ]; then
        AFTER_SCORE=$(echo "$scan_output" | grep -i "kubesec.io score:" | sed -E 's/.*kubesec\.io score: *(-?[0-9]+).*/\1/' | head -1)
    fi

    # Display score
    echo -e "\n${CYAN}Kubesec Score (${stage}):${NC}"
    if [ "$is_negative" = "true" ]; then
        echo -e "  Score: -${score} (CRITICAL - negative score indicates severe security issues)"
        print_result "FAIL" "This resource has critical security problems that must be addressed!"
    else
        echo -e "  Score: ${score}/${max_score} (${score_percent}%)"
    fi

    # Check if score is perfect
    if [ "$is_negative" = "false" ] && [ "$score" = "$max_score" ]; then
        print_result "PASS" "Perfect kubesec score achieved! (${score}/${max_score})"
    elif [ "$is_negative" = "false" ]; then
        local missing=$((max_score - score))
        print_result "WARN" "Score is ${score}/${max_score} (${score_percent}%). Missing ${missing} point(s)."
    fi

        # Extract recommendations (advice items)
        echo -e "\n${CYAN}Additional Recommendations to Improve Score:${NC}"

        # Parse advice items - format is:
        # "AdviseN. path | path | ..." or "N. path"
        # Followed by description on next line
        local advice_section=$(echo "$scan_output" | sed -n '/^Advise/,/^$/p')

        if [ -n "$advice_section" ]; then
            local prev_line=""
            local advice_num=0
            local description=""

            echo "$advice_section" | while IFS= read -r line; do
                # Skip separator lines and empty lines at start
                [[ "$line" =~ ^-+$ ]] && continue
                [[ "$line" =~ ^Advise$ ]] && continue
                [ -z "$line" ] && [ -z "$prev_line" ] && continue

                # Check if this is a new advice item (starts with "Advise" + number and dot, or just number and dot)
                if [[ "$line" =~ ^Advise[0-9]+\. ]] || [[ "$line" =~ ^[0-9]+\. ]]; then
                    # Print previous advice if exists
                    if [ "$advice_num" -gt 0 ] && [ -n "$description" ]; then
                        print_result "INFO" "[${advice_num}] $description"
                    fi

                    # Start new advice
                    advice_num=$(echo "$line" | grep -oE "[0-9]+" | head -1)
                    description=""
                    prev_line="$line"
                elif [ -n "$prev_line" ] && ([[ "$prev_line" =~ ^Advise[0-9]+\. ]] || [[ "$prev_line" =~ ^[0-9]+\. ]]); then
                    # This is the description line for the previous advice
                    description="$line"
                    prev_line=""
                else
                    prev_line="$line"
                fi
            done

            # Print last advice
            if [ "$advice_num" -gt 0 ] && [ -n "$description" ]; then
                print_result "INFO" "[${advice_num}] $description"
            fi
        fi

    # Show what's missing
    echo -e "\n${CYAN}To reach maximum score (${max_score}/${max_score}), implement the recommendations above.${NC}"
}

# Main execution
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace|-n)
                NAMESPACE="$2"
                shift 2
                ;;
            --pod|-p)
                POD_NAME="$2"
                shift 2
                ;;
            --test-type|-t)
                TEST_TYPE="$2"
                shift 2
                ;;
            --kubeconfig|-k)
                KUBECONFIG_FLAG="$2"
                shift 2
                ;;
            --export|-o)
                EXPORT_FILE="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                print_result "FAIL" "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$NAMESPACE" ]; then
        print_result "FAIL" "Namespace is required. Use --namespace or -n"
        usage
    fi

    if [ -z "$POD_NAME" ]; then
        print_result "FAIL" "Pod name is required. Use --pod or -p"
        usage
    fi

    # Validate test type
    if [[ ! "$TEST_TYPE" =~ ^(escape|hardening|context|all)$ ]]; then
        print_result "FAIL" "Invalid test type: $TEST_TYPE. Must be one of: escape, hardening, context, all"
        usage
    fi

    # Set kubeconfig argument
    # Priority: 1) --kubeconfig flag, 2) KUBECONFIG environment variable, 3) none
    if [ -n "${KUBECONFIG_FLAG:-}" ]; then
        # Use flag value
        KUBECONFIG="$KUBECONFIG_FLAG"
        KUBECONFIG_ARG="--kubeconfig=$KUBECONFIG"
        export KUBECONFIG
    elif [ -n "${KUBECONFIG:-}" ]; then
        # Use environment variable (already set)
        KUBECONFIG_ARG="--kubeconfig=$KUBECONFIG"
        # KUBECONFIG is already exported from environment
    else
        # No kubeconfig specified
        KUBECONFIG_ARG=""
    fi

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_result "FAIL" "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        print_result "FAIL" "jq not found. Please install jq for JSON parsing."
        exit 1
    fi

    # Check pod exists
    check_pod

    # Run tests based on type
    case "$TEST_TYPE" in
        escape)
            test_escape
            ;;
        hardening)
            test_hardening
            ;;
        context)
            test_security_context
            ;;
        all)
            test_security_context
            test_hardening
            test_escape
            generate_recommendations
            ;;
        *)
            print_result "FAIL" "Unknown test type: $TEST_TYPE"
            usage
            ;;
    esac

    # Export fixed YAML if requested
    if [ -n "$EXPORT_FILE" ]; then
        # Scan BEFORE export
        scan_kubesec_before

        # Export fixed YAML
        export_fixed_yaml

        # Scan AFTER export
        scan_kubesec "$EXPORT_FILE"

        # Show comparison
        show_score_comparison
    fi

    print_section "Audit Complete"
    print_result "INFO" "Test completed for pod: $POD_NAME in namespace: $NAMESPACE"
    if [ -n "$EXPORT_FILE" ]; then
        print_result "INFO" "Fixed YAML exported to: $EXPORT_FILE"
    fi
}

# Show score comparison
show_score_comparison() {
    if [ -z "$EXPORT_FILE" ] || [ -z "$BEFORE_SCORE" ] || [ -z "$AFTER_SCORE" ]; then
        return
    fi

    print_section "Score Comparison Summary"

    # Handle negative scores
    local before_abs="${BEFORE_SCORE#-}"
    local after_abs="${AFTER_SCORE#-}"
    local before_neg=false
    local after_neg=false

    [[ "$BEFORE_SCORE" =~ ^- ]] && before_neg=true
    [[ "$AFTER_SCORE" =~ ^- ]] && after_neg=true

    if [ "$before_neg" = "true" ]; then
        echo -e "${RED}Before Fixes:${NC}  ${BEFORE_SCORE} (CRITICAL - negative score)"
    else
        local before_percent=$(echo "scale=0; ($before_abs * 100) / 9" | bc 2>/dev/null || echo "0")
        echo -e "${CYAN}Before Fixes:${NC}  ${BEFORE_SCORE}/9 (${before_percent}%)"
    fi

    if [ "$after_neg" = "true" ]; then
        echo -e "${RED}After Fixes:${NC}   ${AFTER_SCORE} (CRITICAL - negative score)"
    else
        local after_percent=$(echo "scale=0; ($after_abs * 100) / 9" | bc 2>/dev/null || echo "0")
        echo -e "${CYAN}After Fixes:${NC}   ${AFTER_SCORE}/9 (${after_percent}%)"
    fi

    # Calculate improvement (handle negative scores)
    if [ "$before_neg" = "true" ] && [ "$after_neg" = "true" ]; then
        # Both negative - compare absolute values
        local improvement=$((after_abs - before_abs))
        if [ "$improvement" -gt 0 ]; then
            print_result "PASS" "Score improved by ${improvement} points (less negative)"
        elif [ "$improvement" -lt 0 ]; then
            print_result "FAIL" "Score worsened by $((improvement * -1)) points"
        else
            print_result "WARN" "Score unchanged. Critical issues remain."
        fi
    elif [ "$before_neg" = "true" ] && [ "$after_neg" = "false" ]; then
        # Went from negative to positive - huge improvement!
        local improvement=$((after_abs + before_abs))
        print_result "PASS" "Excellent! Score improved from negative to positive (+${improvement} points)"
    elif [ "$before_neg" = "false" ] && [ "$after_neg" = "true" ]; then
        # Went from positive to negative - this shouldn't happen
        print_result "FAIL" "Score worsened significantly (became negative)"
    else
        # Both positive - normal comparison
        local improvement=$((after_abs - before_abs))
        if [ "$improvement" -gt 0 ]; then
            print_result "PASS" "Score improved by ${improvement} point(s)!"
        elif [ "$improvement" -eq 0 ]; then
            print_result "INFO" "Score unchanged. Additional manual fixes may be needed (see recommendations above)."
        else
            print_result "WARN" "Score decreased by $((improvement * -1)) point(s). Review exported YAML."
        fi
    fi

    if [ "$after_neg" = "false" ] && [ "$after_abs" -lt 9 ]; then
        local remaining=$((9 - after_abs))
        echo -e "\n${CYAN}To reach perfect score (9/9), implement the recommendations shown above.${NC}"
        print_result "INFO" "Missing ${remaining} point(s) for perfect score"
    elif [ "$after_neg" = "true" ]; then
        echo -e "\n${RED}CRITICAL: This resource has severe security issues that must be addressed!${NC}"
        print_result "FAIL" "Review the critical issues above and fix them before deploying"
    fi
}

# Run main function
main "$@"

