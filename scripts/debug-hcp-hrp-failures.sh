#!/bin/bash
# Debug script for HCP and HRP failures on management cluster
# This script identifies and provides solutions for HelmChartProxy and HelmReleaseProxy failures

set -euo pipefail

MGMT_KUBECONFIG="${MGMT_KUBECONFIG:-/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf}"
WORKLOAD1_KUBECONFIG="${WORKLOAD1_KUBECONFIG:-/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig}"
WORKLOAD2_KUBECONFIG="${WORKLOAD2_KUBECONFIG:-/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if kubeconfig files exist
check_kubeconfigs() {
    print_header "Checking Kubeconfig Files"
    local missing=0

    if [[ ! -f "$MGMT_KUBECONFIG" ]]; then
        print_error "Management cluster kubeconfig not found: $MGMT_KUBECONFIG"
        missing=1
    else
        print_success "Management cluster kubeconfig found"
    fi

    if [[ ! -f "$WORKLOAD1_KUBECONFIG" ]]; then
        print_warning "Workload cluster 1 kubeconfig not found: $WORKLOAD1_KUBECONFIG"
    else
        print_success "Workload cluster 1 kubeconfig found"
    fi

    if [[ ! -f "$WORKLOAD2_KUBECONFIG" ]]; then
        print_warning "Workload cluster 2 kubeconfig not found: $WORKLOAD2_KUBECONFIG"
    else
        print_success "Workload cluster 2 kubeconfig found"
    fi

    return $missing
}

# Check HCP status
check_hcp_status() {
    print_header "HelmChartProxy Status"

    if ! KUBECONFIG="$MGMT_KUBECONFIG" kubectl get crd helmchartproxies.addons.cluster.x-k8s.io &>/dev/null; then
        print_error "HelmChartProxy CRD not installed"
        return 1
    fi

    local total=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmchartproxies -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    local ready=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmchartproxies -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
    local not_ready=$((total - ready))

    echo "Total HCPs: $total"
    echo "Ready: $ready"
    echo "Not Ready: $not_ready"

    if [[ $not_ready -gt 0 ]]; then
        echo -e "\n${YELLOW}Not Ready HelmChartProxies:${NC}"
        KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmchartproxies -A --no-headers 2>/dev/null | \
            grep -v "True" | while read -r ns name ready reason message rest; do
            echo -e "  ${RED}→${NC} $ns/$name"
            echo "    Reason: $reason"
            echo "    Message: $message"
        done
        return 1
    fi

    return 0
}

# Check HRP status
check_hrp_status() {
    print_header "HelmReleaseProxy Status"

    if ! KUBECONFIG="$MGMT_KUBECONFIG" kubectl get crd helmreleaseproxies.addons.cluster.x-k8s.io &>/dev/null; then
        print_error "HelmReleaseProxy CRD not installed"
        return 1
    fi

    local total=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmreleaseproxies -A --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    local ready=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmreleaseproxies -A --no-headers 2>/dev/null | grep -c "True" | tr -d '[:space:]')
    local not_ready=$((total - ready))

    echo "Total HRPs: $total"
    echo "Ready: $ready"
    echo "Not Ready: $not_ready"

    if [[ $not_ready -gt 0 ]]; then
        echo -e "\n${YELLOW}Failed HelmReleaseProxies:${NC}"
        KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmreleaseproxies -A -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.status == "failed" or (.status.conditions[]? | select(.type == "Ready" and .status == "False"))) |
            "\(.metadata.namespace)/\(.metadata.name)\t\(.spec.clusterRef.name)\t\(.status.status // "unknown")\t\(.status.conditions[]? | select(.type == "Ready") | .message // "N/A")"' | \
            while IFS=$'\t' read -r name cluster status message; do
            echo -e "  ${RED}→${NC} $name (cluster: $cluster, status: $status)"
            echo "    Message: $message"
        done
        return 1
    fi

    return 0
}

# Check workload cluster health
check_workload_cluster() {
    local cluster_name=$1
    local kubeconfig=$2

    if [[ ! -f "$kubeconfig" ]]; then
        print_warning "Skipping $cluster_name - kubeconfig not found"
        return 0
    fi

    print_header "Workload Cluster: $cluster_name"

    # Check nodes
    echo -e "\n${YELLOW}Node Status:${NC}"
    KUBECONFIG="$kubeconfig" kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,TAINTS:.spec.taints 2>/dev/null || print_error "Cannot connect to cluster"

    # Check critical pods
    echo -e "\n${YELLOW}Critical Pods Status:${NC}"
    for ns in kube-system ntnx-system; do
        echo "Namespace: $ns"
        KUBECONFIG="$kubeconfig" kubectl get pods -n "$ns" -o wide 2>/dev/null | grep -E "(cilium|nutanix-cloud|konnector|nutanix-csi)" | head -10 || true
    done

    # Check CCM status
    echo -e "\n${YELLOW}CCM Status:${NC}"
    KUBECONFIG="$kubeconfig" kubectl get pods -n kube-system -l app=nutanix-cloud-controller-manager 2>/dev/null || true

    # Check Cilium status
    echo -e "\n${YELLOW}Cilium Status:${NC}"
    KUBECONFIG="$kubeconfig" kubectl get daemonset -n kube-system cilium 2>/dev/null || true
    KUBECONFIG="$kubeconfig" kubectl get pods -n kube-system -l k8s-app=cilium 2>/dev/null | head -5 || true
}

# Get detailed failure information
get_failure_details() {
    print_header "Detailed Failure Analysis"

    # Get all failed HRPs
    local failed_hrps=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmreleaseproxies -A -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.status == "failed" or (.status.conditions[]? | select(.type == "Ready" and .status == "False"))) | "\(.metadata.namespace)/\(.metadata.name)"')

    if [[ -z "$failed_hrps" ]]; then
        print_success "No failed HRPs found"
        return 0
    fi

    echo "$failed_hrps" | while read -r hrp; do
        local ns=$(echo "$hrp" | cut -d'/' -f1)
        local name=$(echo "$hrp" | cut -d'/' -f2)

        echo -e "\n${YELLOW}HRP: $ns/$name${NC}"
        KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmreleaseproxy -n "$ns" "$name" -o json 2>/dev/null | \
            jq -r '.status.conditions[]? | select(.type == "Ready" or .type == "HelmReleaseReady") |
            "  Type: \(.type)\n  Status: \(.status)\n  Reason: \(.reason)\n  Message: \(.message)\n"'
    done
}

# Provide solutions
provide_solutions() {
    print_header "Recommended Solutions"

    echo -e "${YELLOW}Based on the failures detected, here are recommended actions:${NC}\n"

    # Check for Cilium failures
    local cilium_failures=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmreleaseproxies -A -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("cilium")) | select(.status.status == "failed" or (.status.conditions[]? | select(.type == "Ready" and .status == "False"))) | .metadata.name')

    if [[ -n "$cilium_failures" ]]; then
        echo -e "${RED}1. Cilium Failures Detected${NC}"
        echo "   - Cilium pods are likely crashing due to networking issues"
        echo "   - Check Cilium pod logs: kubectl logs -n kube-system <cilium-pod> --kubeconfig=<workload-kubeconfig>"
        echo "   - Verify k8sServiceHost and k8sServicePort in Cilium config match control plane VIP"
        echo "   - Consider restarting Cilium daemonset: kubectl rollout restart daemonset/cilium -n kube-system"
        echo ""
    fi

    # Check for CCM failures
    if [[ -f "$WORKLOAD1_KUBECONFIG" ]]; then
        local ccm_status=$(KUBECONFIG="$WORKLOAD1_KUBECONFIG" kubectl get pods -n kube-system -l app=nutanix-cloud-controller-manager --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || echo "0")
        if [[ "$ccm_status" != "0" ]]; then
            echo -e "${RED}2. CCM (Cloud Controller Manager) Failures Detected${NC}"
            echo "   - CCM cannot reach Kubernetes API server"
            echo "   - This prevents node initialization (removing uninitialized taints)"
            echo "   - Check CCM logs: kubectl logs -n kube-system <ccm-pod> --kubeconfig=<workload-kubeconfig>"
            echo "   - Verify network connectivity to API server (10.96.0.1:443)"
            echo "   - Ensure Cilium is working properly first"
            echo ""
        fi
    fi

    # Check for node taint issues
    if [[ -f "$WORKLOAD1_KUBECONFIG" ]]; then
        local uninitialized_nodes=$(KUBECONFIG="$WORKLOAD1_KUBECONFIG" kubectl get nodes -o json 2>/dev/null | \
            jq -r '.items[] | select(.spec.taints[]? | select(.key == "node.cluster.x-k8s.io/uninitialized")) | .metadata.name' | wc -l | tr -d '[:space:]')
        if [[ "$uninitialized_nodes" -gt 0 ]]; then
            echo -e "${RED}3. Node Initialization Issues${NC}"
            echo "   - $uninitialized_nodes node(s) have uninitialized taints"
            echo "   - This prevents pods from scheduling (konnector-agent, CSI precheck)"
            echo "   - Nodes will be initialized once CCM is working"
            echo "   - Manual fix (NOT RECOMMENDED): kubectl taint nodes <node-name> node.cluster.x-k8s.io/uninitialized-"
            echo ""
        fi
    fi

    # Check for hook timeout issues
    local hook_failures=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl get helmreleaseproxies -A -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.conditions[]? | select(.type == "Ready" and .message | contains("hook"))) | .metadata.name')

    if [[ -n "$hook_failures" ]]; then
        echo -e "${RED}4. Helm Hook Timeout Issues${NC}"
        echo "   - Helm hooks are timing out waiting for pods to become ready"
        echo "   - This is usually a symptom of the underlying issues above"
        echo "   - Fix the root cause (Cilium/CCM) and hooks should pass"
        echo "   - To retry: Delete the failed HRP and let it recreate"
        echo ""
    fi

    echo -e "${YELLOW}General Troubleshooting Steps:${NC}"
    echo "1. Verify workload cluster connectivity from management cluster"
    echo "2. Check if Cilium CNI is properly configured and running"
    echo "3. Ensure CCM credentials are correct and secret exists"
    echo "4. Verify network policies aren't blocking required traffic"
    echo "5. Check cluster resource quotas and limits"
    echo ""
    echo -e "${YELLOW}To retry failed deployments:${NC}"
    echo "  # Delete failed HRP (it will be recreated by HCP)"
    echo "  kubectl delete helmreleaseproxy <name> -n <namespace> --kubeconfig=$MGMT_KUBECONFIG"
    echo ""
    echo -e "${YELLOW}To check specific resource:${NC}"
    echo "  kubectl describe helmreleaseproxy <name> -n <namespace> --kubeconfig=$MGMT_KUBECONFIG"
    echo "  kubectl describe helmchartproxy <name> -n <namespace> --kubeconfig=$MGMT_KUBECONFIG"
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   HCP/HRP Failure Debugging Script                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if ! check_kubeconfigs; then
        print_error "Required kubeconfig files are missing. Please set environment variables:"
        echo "  export MGMT_KUBECONFIG=/path/to/mgmt-kubeconfig"
        echo "  export WORKLOAD1_KUBECONFIG=/path/to/workload1-kubeconfig"
        exit 1
    fi

    check_hcp_status
    echo ""
    check_hrp_status
    echo ""
    get_failure_details
    echo ""

    if [[ -f "$WORKLOAD1_KUBECONFIG" ]]; then
        check_workload_cluster "dm-nkp-workload-1" "$WORKLOAD1_KUBECONFIG"
        echo ""
    fi

    if [[ -f "$WORKLOAD2_KUBECONFIG" ]]; then
        check_workload_cluster "dm-nkp-workload-2" "$WORKLOAD2_KUBECONFIG"
        echo ""
    fi

    provide_solutions
}

main "$@"

