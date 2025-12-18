#!/bin/bash
# =============================================================================
# Verify NKP RBAC Users - Test Permissions
# =============================================================================
#
# This script tests the permissions of each NKP RBAC user to verify
# they have the correct access levels.
#
# Usage:
#   ./verify-rbac-users.sh [kubeconfig-dir]
#
# Examples:
#   ./verify-rbac-users.sh                           # Uses default dir
#   ./verify-rbac-users.sh /Users/deepak.muley/ws/nkp
#
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
KUBECONFIG_DIR="${1:-/Users/deepak.muley/ws/nkp}"

# Test result tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_subheader() {
    echo ""
    echo -e "${CYAN}─── $1 ───${NC}"
}

test_permission() {
    local kubeconfig="$1"
    local description="$2"
    local expected="$3"  # "yes" or "no"
    local resource="$4"
    local verb="${5:-get}"
    local namespace="${6:-}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    local ns_flag=""
    if [ -n "$namespace" ]; then
        ns_flag="-n $namespace"
    else
        ns_flag="-A"
    fi
    
    local result
    result=$(kubectl --kubeconfig="$kubeconfig" auth can-i "$verb" "$resource" $ns_flag 2>/dev/null | head -1 || echo "no")
    # Normalize result - trim whitespace and take first word
    result=$(echo "$result" | tr -d '[:space:]' | cut -c1-3)
    
    local status_icon
    local status_color
    
    if [ "$result" = "$expected" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        status_icon="✅"
        status_color="${GREEN}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        status_icon="❌"
        status_color="${RED}"
    fi
    
    printf "  ${status_color}${status_icon}${NC} %-50s (expected: %-3s, got: %-3s)\n" "$description" "$expected" "$result"
}

verify_user_exists() {
    local kubeconfig="$1"
    local username="$2"

    if [ ! -f "$kubeconfig" ]; then
        echo -e "${RED}ERROR: Kubeconfig not found: $kubeconfig${NC}"
        echo -e "${YELLOW}Run: ./scripts/create-k8s-user.sh $username${NC}"
        return 1
    fi

    # Test basic auth
    local auth_result
    auth_result=$(kubectl --kubeconfig="$kubeconfig" auth whoami 2>/dev/null | grep -i "username" || echo "")

    if [ -z "$auth_result" ]; then
        echo -e "${RED}ERROR: Cannot authenticate with kubeconfig: $kubeconfig${NC}"
        return 1
    fi

    echo -e "${GREEN}  Authenticated as: $(echo "$auth_result" | awk '{print $2}')${NC}"
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          NKP RBAC User Verification Script                    ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Kubeconfig Directory: ${KUBECONFIG_DIR}"
echo ""

# Check if directory exists
if [ ! -d "$KUBECONFIG_DIR" ]; then
    echo -e "${RED}ERROR: Kubeconfig directory not found: $KUBECONFIG_DIR${NC}"
    exit 1
fi

# =============================================================================
# Test 1: Super Admin (dm-k8s-admin)
# =============================================================================
print_header "SUPER ADMIN: dm-k8s-admin"
SUPER_ADMIN_KUBECONFIG="${KUBECONFIG_DIR}/dm-k8s-admin.kubeconfig"

if verify_user_exists "$SUPER_ADMIN_KUBECONFIG" "dm-k8s-admin"; then

    print_subheader "Kubernetes Cluster Access (cluster-admin)"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get nodes" "yes" "nodes" "get"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get PVs" "yes" "persistentvolumes" "get"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get secrets (all namespaces)" "yes" "secrets" "get"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Create namespaces" "yes" "namespaces" "create"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Delete pods (kube-system)" "yes" "pods" "delete" "kube-system"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "All permissions (*)" "yes" "*" "*"

    print_subheader "NKP/Kommander Access (kommander-admin)"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get workspaces" "yes" "workspaces.workspaces.kommander.mesosphere.io" "get"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Create workspaces" "yes" "workspaces.workspaces.kommander.mesosphere.io" "create"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get projects (all)" "yes" "projects.workspaces.kommander.mesosphere.io" "get"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get virtualgroups" "yes" "virtualgroups.kommander.mesosphere.io" "get"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get appdeployments" "yes" "appdeployments.apps.kommander.d2iq.io" "get"
    test_permission "$SUPER_ADMIN_KUBECONFIG" "Get kommanderclusters" "yes" "kommanderclusters.kommander.mesosphere.io" "get"
else
    echo -e "${YELLOW}Skipping super admin tests - kubeconfig not found${NC}"
fi

# =============================================================================
# Test 2: Workspace Admin (dm-dev-workspace-admin)
# =============================================================================
print_header "WORKSPACE ADMIN: dm-dev-workspace-admin"
WS_ADMIN_KUBECONFIG="${KUBECONFIG_DIR}/dm-dev-workspace-admin.kubeconfig"

if verify_user_exists "$WS_ADMIN_KUBECONFIG" "dm-dev-workspace-admin"; then

    print_subheader "Workspace Access (dm-dev-workspace)"
    test_permission "$WS_ADMIN_KUBECONFIG" "Get workspaceroles (dm-dev-workspace)" "yes" "workspaceroles.workspaces.kommander.mesosphere.io" "get" "dm-dev-workspace"
    test_permission "$WS_ADMIN_KUBECONFIG" "Get projects (dm-dev-workspace)" "yes" "projects.workspaces.kommander.mesosphere.io" "get" "dm-dev-workspace"
    test_permission "$WS_ADMIN_KUBECONFIG" "Get pods (dm-dev-workspace)" "yes" "pods" "get" "dm-dev-workspace"

    print_subheader "Should NOT Have Access To"
    test_permission "$WS_ADMIN_KUBECONFIG" "Get nodes (cluster-level)" "no" "nodes" "get"
    test_permission "$WS_ADMIN_KUBECONFIG" "Get secrets (kube-system)" "no" "secrets" "get" "kube-system"
    test_permission "$WS_ADMIN_KUBECONFIG" "Get workspaceroles (kommander)" "no" "workspaceroles.workspaces.kommander.mesosphere.io" "get" "kommander"
    test_permission "$WS_ADMIN_KUBECONFIG" "Create workspaces (global)" "no" "workspaces.workspaces.kommander.mesosphere.io" "create"
else
    echo -e "${YELLOW}Skipping workspace admin tests - kubeconfig not found${NC}"
fi

# =============================================================================
# Test 3: Project Admin (dm-dev-project-admin)
# =============================================================================
print_header "PROJECT ADMIN: dm-dev-project-admin"
PROJ_ADMIN_KUBECONFIG="${KUBECONFIG_DIR}/dm-dev-project-admin.kubeconfig"

if verify_user_exists "$PROJ_ADMIN_KUBECONFIG" "dm-dev-project-admin"; then

    print_subheader "Project Access (dm-dev-project)"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Get pods (dm-dev-project)" "yes" "pods" "get" "dm-dev-project"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Get projectroles (dm-dev-project)" "yes" "projectroles.workspaces.kommander.mesosphere.io" "get" "dm-dev-project"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Create configmaps (dm-dev-project)" "yes" "configmaps" "create" "dm-dev-project"

    print_subheader "Should NOT Have Access To"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Get nodes (cluster-level)" "no" "nodes" "get"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Get pods (dm-dev-workspace)" "no" "pods" "get" "dm-dev-workspace"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Get pods (default)" "no" "pods" "get" "default"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Get workspaceroles (dm-dev-workspace)" "no" "workspaceroles.workspaces.kommander.mesosphere.io" "get" "dm-dev-workspace"
    test_permission "$PROJ_ADMIN_KUBECONFIG" "Create workspaces" "no" "workspaces.workspaces.kommander.mesosphere.io" "create"
else
    echo -e "${YELLOW}Skipping project admin tests - kubeconfig not found${NC}"
fi

# =============================================================================
# Summary
# =============================================================================
print_header "TEST SUMMARY"

echo ""
echo -e "  Total Tests:  ${TOTAL_TESTS}"
echo -e "  ${GREEN}Passed:       ${PASSED_TESTS}${NC}"
echo -e "  ${RED}Failed:       ${FAILED_TESTS}${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ] && [ $TOTAL_TESTS -gt 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    ALL TESTS PASSED! ✅                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    exit 0
elif [ $TOTAL_TESTS -eq 0 ]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║         NO TESTS RUN - Create users first                     ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Run the following commands to create users:"
    echo -e "  ./scripts/create-k8s-user.sh dm-k8s-admin"
    echo -e "  ./scripts/create-k8s-user.sh dm-dev-workspace-admin"
    echo -e "  ./scripts/create-k8s-user.sh dm-dev-project-admin"
    echo ""
    echo -e "Then move kubeconfigs to: $KUBECONFIG_DIR"
    exit 1
else
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                 SOME TESTS FAILED! ❌                          ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Check the RBAC configuration and ensure:"
    echo -e "  1. VirtualGroups are created correctly"
    echo -e "  2. Role bindings are applied"
    echo -e "  3. Certificate CN matches VirtualGroup subject name"
    exit 1
fi

