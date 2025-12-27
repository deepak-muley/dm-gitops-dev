#!/bin/bash

# Validate Security Fixes Script
# Helps determine if security fixes will break a pod by analyzing:
# 1. Current security requirements
# 2. What the pod actually uses
# 3. Documentation/annotations
# 4. Testing with dry-run

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
NAMESPACE=""
POD_NAME=""
RESOURCE_KIND=""
RESOURCE_NAME=""
KUBECONFIG_FLAG=""
EXPORT_FILE=""

usage() {
    cat << EOF
${CYAN}Validate Security Fixes Script${NC}

This script helps determine if security fixes will break a pod by analyzing:
- Current security requirements
- What the pod actually uses at runtime
- Documentation/annotations
- Testing with dry-run

Usage: $0 --namespace <namespace> --pod <pod-name> [options]

Required Arguments:
  --namespace, -n <namespace>    Kubernetes namespace
  --pod, -p <pod-name>          Name of the pod to analyze

Optional Arguments:
  --kubeconfig, -k <path>       Path to kubeconfig file
  --export, -o <file>           Export analysis report to file
  --help, -h                     Show this help message

Examples:
  $0 --namespace kube-system --pod cilium-xxx
  $0 -n kommander -p kommander-appmanagement-xxx -k /path/to/kubeconfig
  $0 -n default -p my-pod --export analysis-report.txt

EOF
    exit 1
}

print_section() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

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
if [ -z "$NAMESPACE" ] || [ -z "$POD_NAME" ]; then
    print_result "FAIL" "Namespace and pod name are required"
    usage
fi

# Set kubeconfig
if [ -n "${KUBECONFIG_FLAG:-}" ]; then
    KUBECONFIG="$KUBECONFIG_FLAG"
    KUBECONFIG_ARG="--kubeconfig=$KUBECONFIG"
    export KUBECONFIG
elif [ -n "${KUBECONFIG:-}" ]; then
    KUBECONFIG_ARG="--kubeconfig=$KUBECONFIG"
else
    KUBECONFIG_ARG=""
fi

# Check if pod exists
if ! kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    print_result "FAIL" "Pod '$POD_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

# Get owner resource
get_owner_resource() {
    local owner_kind=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
    local owner_name=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")

    if [ -n "$owner_kind" ] && [ -n "$owner_name" ]; then
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

# Main analysis
main() {
    print_section "Security Fix Validation Analysis"
    print_result "INFO" "Analyzing pod: $POD_NAME in namespace: $NAMESPACE"

    local owner_info=$(get_owner_resource)
    RESOURCE_KIND=$(echo "$owner_info" | cut -d'|' -f1)
    RESOURCE_NAME=$(echo "$owner_info" | cut -d'|' -f2)

    print_result "INFO" "Detected resource: $RESOURCE_KIND/$RESOURCE_NAME"

    # 1. Analyze current security context
    print_section "1. Current Security Configuration"
    analyze_current_config

    # 2. Check what the pod actually uses
    print_section "2. Runtime Requirements Analysis"
    analyze_runtime_requirements

    # 3. Check documentation/annotations
    print_section "3. Documentation and Annotations"
    check_documentation

    # 4. Test with dry-run
    print_section "4. Dry-Run Validation"
    test_dry_run

    # 5. Recommendations
    print_section "5. Recommendations"
    generate_recommendations

    print_section "Analysis Complete"
}

# Analyze current security configuration
analyze_current_config() {
    local pod_json=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o json)

    # Pod-level
    local host_network=$(echo "$pod_json" | jq -r '.spec.hostNetwork // false')
    local host_pid=$(echo "$pod_json" | jq -r '.spec.hostPID // false')
    local host_ipc=$(echo "$pod_json" | jq -r '.spec.hostIPC // false')
    local run_as_user=$(echo "$pod_json" | jq -r '.spec.securityContext.runAsUser // "not set"')
    local run_as_nonroot=$(echo "$pod_json" | jq -r '.spec.securityContext.runAsNonRoot // "not set"')

    echo -e "${CYAN}Pod-Level Security:${NC}"
    [ "$host_network" = "true" ] && print_result "WARN" "hostNetwork: true (required for CNI/network plugins)"
    [ "$host_pid" = "true" ] && print_result "WARN" "hostPID: true (may be required for system monitoring)"
    [ "$host_ipc" = "true" ] && print_result "WARN" "hostIPC: true (may be required for IPC)"
    [ "$run_as_user" = "0" ] && print_result "FAIL" "runAsUser: 0 (running as root)"
    [ "$run_as_user" != "0" ] && [ "$run_as_user" != "not set" ] && print_result "PASS" "runAsUser: $run_as_user (non-root)"
    [ "$run_as_nonroot" = "true" ] && print_result "PASS" "runAsNonRoot: true"

    # Container-level
    echo -e "\n${CYAN}Container-Level Security:${NC}"
    local containers=$(echo "$pod_json" | jq -r '.spec.containers[] | @json')
    while IFS= read -r container; do
        local name=$(echo "$container" | jq -r '.name')
        local privileged=$(echo "$container" | jq -r '.securityContext.privileged // false')
        local allow_priv_esc=$(echo "$container" | jq -r '.securityContext.allowPrivilegeEscalation // "not set"')
        local readonly_root=$(echo "$container" | jq -r '.securityContext.readOnlyRootFilesystem // false')
        local caps_add=$(echo "$container" | jq -r '.securityContext.capabilities.add // [] | length')
        local caps_drop=$(echo "$container" | jq -r '.securityContext.capabilities.drop // [] | length')

        echo -e "\n  ${CYAN}Container: $name${NC}"
        [ "$privileged" = "true" ] && print_result "FAIL" "privileged: true (CRITICAL - full host access)"
        [ "$allow_priv_esc" = "true" ] && print_result "WARN" "allowPrivilegeEscalation: true"
        [ "$readonly_root" = "false" ] && print_result "WARN" "readOnlyRootFilesystem: false"
        [ "$caps_add" -gt 0 ] && print_result "WARN" "Added capabilities: $caps_add (check if required)"
        [ "$caps_drop" -gt 0 ] && print_result "PASS" "Dropped capabilities: $caps_drop"
    done <<< "$containers"
}

# Analyze what the pod actually uses at runtime
analyze_runtime_requirements() {
    print_result "INFO" "Checking what the pod actually uses at runtime..."

    # Check if pod is running
    local pod_status=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$pod_status" != "Running" ]; then
        print_result "WARN" "Pod is not running (status: $pod_status). Cannot analyze runtime requirements."
        return
    fi

    # Check current user
    local current_user=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'id -u 2>/dev/null || echo "unknown"' 2>/dev/null || echo "unknown")
    if [ "$current_user" != "unknown" ]; then
        if [ "$current_user" = "0" ]; then
            print_result "FAIL" "Currently running as root (UID: 0)"
            print_result "INFO" "→ Fix: Set runAsUser to non-root (e.g., 65532)"
            print_result "INFO" "→ Risk: HIGH - May break if app requires root privileges"
        else
            print_result "PASS" "Currently running as non-root (UID: $current_user)"
            print_result "INFO" "→ Fix: Set runAsUser to $current_user (safe)"
        fi
    fi

    # Check capabilities actually in use
    local caps=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'cat /proc/self/status | grep CapEff 2>/dev/null || echo ""' 2>/dev/null || echo "")
    if [ -n "$caps" ]; then
        local cap_eff=$(echo "$caps" | grep "CapEff:" | awk '{print $2}')
        if [ "$cap_eff" != "0000000000000000" ] && [ -n "$cap_eff" ]; then
            print_result "WARN" "Container has effective capabilities: $cap_eff"
            print_result "INFO" "→ Fix: Drop ALL capabilities"
            print_result "INFO" "→ Risk: MEDIUM - May break if app needs specific capabilities"
        else
            print_result "PASS" "No effective capabilities (already secure)"
        fi
    fi

    # Check if writes to root filesystem
    local writable_dirs=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'test -w /tmp && echo "writable" || echo "readonly"' 2>/dev/null || echo "unknown")
    if [ "$writable_dirs" = "writable" ]; then
        print_result "WARN" "Root filesystem is writable"
        print_result "INFO" "→ Fix: Set readOnlyRootFilesystem: true"
        print_result "INFO" "→ Risk: HIGH - May break if app writes to / (use emptyDir volumes for /tmp)"
    fi

    # Check network requirements
    local host_network=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.hostNetwork}' 2>/dev/null || echo "false")
    if [ "$host_network" = "true" ]; then
        print_result "WARN" "hostNetwork is enabled"
        print_result "INFO" "→ Fix: Set hostNetwork: false"
        print_result "INFO" "→ Risk: CRITICAL - Will break CNI plugins, node exporters, etc."
        print_result "INFO" "→ Action: DO NOT change if this is a network/system pod"
    fi
}

# Check documentation and annotations
check_documentation() {
    local pod_json=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o json)
    local annotations=$(echo "$pod_json" | jq -r '.metadata.annotations // {}')

    # Check for security-related annotations
    local security_notes=$(echo "$annotations" | jq -r 'to_entries[] | select(.key | contains("security") or contains("privilege") or contains("capability")) | "\(.key): \(.value)"' 2>/dev/null || echo "")

    if [ -n "$security_notes" ]; then
        print_result "INFO" "Found security-related annotations:"
        echo "$security_notes" | while IFS= read -r line; do
            echo "  - $line"
        done
    else
        print_result "INFO" "No security-related annotations found"
    fi

    # Check labels for hints
    local labels=$(echo "$pod_json" | jq -r '.metadata.labels // {}')
    local app_name=$(echo "$labels" | jq -r '.["app.kubernetes.io/name"] // .app // .name // "unknown"' 2>/dev/null || echo "unknown")

    print_result "INFO" "Application: $app_name"

    # Common patterns
    case "$app_name" in
        *cilium*|*calico*|*flannel*|*weave*)
            print_result "WARN" "This appears to be a CNI/network plugin"
            print_result "INFO" "→ These typically require: hostNetwork, privileged, NET_ADMIN"
            print_result "INFO" "→ Recommendation: DO NOT apply strict security fixes"
            ;;
        *node-exporter*|*prometheus*|*metrics*)
            print_result "WARN" "This appears to be a monitoring/metrics pod"
            print_result "INFO" "→ May require hostPID or hostNetwork for system metrics"
            ;;
        *operator*|*controller*)
            print_result "INFO" "This appears to be a controller/operator"
            print_result "INFO" "→ Usually safe to apply security fixes (check documentation)"
            ;;
    esac
}

# Test with dry-run
test_dry_run() {
    print_result "INFO" "Testing security fixes with kubectl dry-run..."

    # Get the resource
    local resource_json
    if [ "$RESOURCE_KIND" = "Pod" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get pod "$RESOURCE_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
    elif [ "$RESOURCE_KIND" = "Deployment" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get deployment "$RESOURCE_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
    elif [ "$RESOURCE_KIND" = "StatefulSet" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get statefulset "$RESOURCE_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
    elif [ "$RESOURCE_KIND" = "DaemonSet" ]; then
        resource_json=$(kubectl ${KUBECONFIG_ARG} get daemonset "$RESOURCE_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
    else
        print_result "WARN" "Cannot test dry-run for resource kind: $RESOURCE_KIND"
        return
    fi

    # Apply basic security fixes (non-breaking ones)
    local test_json=$(echo "$resource_json" | jq '
        # Only apply safe fixes for dry-run
        if .spec.template.spec.securityContext then
            .spec.template.spec.securityContext.runAsNonRoot = true
        else
            .spec.template.spec.securityContext = {runAsNonRoot: true}
        end |
        if .spec.template.spec.containers then
            .spec.template.spec.containers = (.spec.template.spec.containers | map(
                if .securityContext then
                    .securityContext.allowPrivilegeEscalation = false
                else
                    .securityContext = {allowPrivilegeEscalation: false}
                end
            ))
        end
    ' 2>/dev/null)

    if [ -n "$test_json" ]; then
        # Test with dry-run
        if echo "$test_json" | kubectl ${KUBECONFIG_ARG} apply --dry-run=server -f - &>/dev/null; then
            print_result "PASS" "Dry-run validation passed (basic fixes are valid)"
        else
            print_result "FAIL" "Dry-run validation failed (fixes may be invalid)"
        fi
    fi
}

# Generate recommendations
generate_recommendations() {
    print_result "INFO" "Generating recommendations based on analysis..."

    local pod_json=$(kubectl ${KUBECONFIG_ARG} get pod "$POD_NAME" -n "$NAMESPACE" -o json)
    local host_network=$(echo "$pod_json" | jq -r '.spec.hostNetwork // false')
    local privileged=$(echo "$pod_json" | jq -r '.spec.containers[0].securityContext.privileged // false')
    local app_name=$(echo "$pod_json" | jq -r '.metadata.labels."app.kubernetes.io/name" // .metadata.labels.app // "unknown"' 2>/dev/null || echo "unknown")

    echo -e "\n${CYAN}Recommendations:${NC}"

    # Critical checks
    if [ "$privileged" = "true" ]; then
        print_result "FAIL" "CRITICAL: Pod runs in privileged mode"
        echo "  → This pod requires full host access"
        echo "  → DO NOT remove privileged mode without testing"
        echo "  → Check if this is a system/CNI pod that legitimately needs it"
    fi

    if [ "$host_network" = "true" ]; then
        print_result "WARN" "Pod uses hostNetwork"
        if [[ "$app_name" =~ (cilium|calico|flannel|weave|kube-proxy) ]]; then
            echo "  → This is a network plugin - hostNetwork is REQUIRED"
            echo "  → DO NOT change hostNetwork: false"
        else
            echo "  → Consider if hostNetwork is really needed"
            echo "  → Test carefully before changing"
        fi
    fi

    # Safe fixes
    local current_user=$(kubectl ${KUBECONFIG_ARG} exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'id -u 2>/dev/null || echo "unknown"' 2>/dev/null || echo "unknown")
    if [ "$current_user" != "0" ] && [ "$current_user" != "unknown" ]; then
        print_result "PASS" "Safe to set runAsUser: $current_user (already running as non-root)"
    fi

    echo -e "\n${CYAN}Testing Strategy:${NC}"
    echo "  1. Apply fixes to a test namespace first"
    echo "  2. Monitor pod logs and metrics after applying"
    echo "  3. Test all functionality of the application"
    echo "  4. Roll back immediately if issues occur"
    echo "  5. Check application documentation for security requirements"
}

# Run main
main "$@"

