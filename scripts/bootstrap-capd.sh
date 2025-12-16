#!/usr/bin/env bash
#
# bootstrap-capd.sh - Install Cluster API Provider Docker (CAPD)
#
# This script installs CAPD on a management cluster for creating
# Docker-based Kubernetes clusters (useful for local testing)
#
# Usage:
#   ./scripts/bootstrap-capd.sh [cluster]
#
# Examples:
#   ./scripts/bootstrap-capd.sh              # Install on mgmt cluster (default)
#   ./scripts/bootstrap-capd.sh mgmt         # Install on mgmt cluster
#   ./scripts/bootstrap-capd.sh /path/to/kubeconfig  # Custom kubeconfig
#
# Options:
#   --status              Check CAPD installation status
#   --help                Show this help message

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Kubeconfig shortcuts
KUBECONFIG_MGMT="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
KUBECONFIG_WORKLOAD1="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
KUBECONFIG_WORKLOAD2="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# CAPD version - align with CAPI version on your cluster
# Check with: kubectl get providers -A | grep cluster-api
CAPD_VERSION="v1.8.5"
CAPD_GITHUB_URL="https://github.com/kubernetes-sigs/cluster-api/releases/download/${CAPD_VERSION}/infrastructure-components-development.yaml"

# Print header
print_header() {
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
}

# Print success message
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print error message
error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Print info message
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Print warning message
warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Show help
show_help() {
    cat << EOF
${BOLD}bootstrap-capd.sh${NC} - Install Cluster API Provider Docker (CAPD)

${BOLD}USAGE:${NC}
    ./scripts/bootstrap-capd.sh [OPTIONS] [CLUSTER]

${BOLD}ARGUMENTS:${NC}
    CLUSTER     Cluster shortcut or kubeconfig path (default: mgmt)
                Shortcuts: mgmt, workload1, workload2

${BOLD}OPTIONS:${NC}
    --direct              Download and apply CAPD directly (bypasses clusterctl)
    --status              Check CAPD installation status
    --help                Show this help message

${BOLD}EXAMPLES:${NC}
    # Install CAPD on management cluster
    ./scripts/bootstrap-capd.sh
    ./scripts/bootstrap-capd.sh mgmt

    # Install CAPD directly (bypasses clusterctl - use if TLS issues)
    ./scripts/bootstrap-capd.sh --direct mgmt

    # Check CAPD status
    ./scripts/bootstrap-capd.sh --status mgmt

${BOLD}KUBECONFIG SHORTCUTS:${NC}
    mgmt       ${KUBECONFIG_MGMT}
    workload1  ${KUBECONFIG_WORKLOAD1}
    workload2  ${KUBECONFIG_WORKLOAD2}

${BOLD}WHAT IS CAPD?${NC}
    CAPD (Cluster API Provider Docker) creates Kubernetes clusters using
    Docker containers as "machines". Each node runs as a Docker container
    on the management cluster. Useful for:
    - Local development and testing
    - CI/CD pipelines
    - Quick cluster creation without cloud costs
    - Testing with Kubemark hollow nodes

${BOLD}PREREQUISITES:${NC}
    - clusterctl CLI installed (brew install clusterctl)
    - kubectl configured with cluster access
    - Docker available on management cluster nodes
    - Cluster API already initialized on the cluster

${BOLD}IMPORTANT NOTES:${NC}
    - CAPD requires Docker to be running on the management cluster nodes
    - CAPD clusters are typically used for development/testing, not production
    - The management cluster must have sufficient resources to run Docker containers

EOF
}

# Resolve kubeconfig path
resolve_kubeconfig() {
    local input="$1"

    case "$input" in
        mgmt)
            echo "$KUBECONFIG_MGMT"
            ;;
        workload1)
            echo "$KUBECONFIG_WORKLOAD1"
            ;;
        workload2)
            echo "$KUBECONFIG_WORKLOAD2"
            ;;
        *)
            if [[ -f "$input" ]]; then
                echo "$input"
            else
                error "Invalid kubeconfig: $input"
                error "Use one of: mgmt, workload1, workload2, or a valid file path"
                exit 1
            fi
            ;;
    esac
}

# Check CAPD status
check_status() {
    local kubeconfig="$1"

    print_header "CAPD STATUS CHECK"

    info "Checking CAPD provider..."
    echo ""

    # Check if capd-system namespace exists
    if kubectl --kubeconfig="$kubeconfig" get namespace capd-system &> /dev/null; then
        success "capd-system namespace exists"

        echo ""
        echo -e "${BOLD}Pods in capd-system:${NC}"
        kubectl --kubeconfig="$kubeconfig" get pods -n capd-system 2>/dev/null || echo "  No pods found"

        echo ""
        echo -e "${BOLD}CAPD Provider:${NC}"
        kubectl --kubeconfig="$kubeconfig" get providers -A 2>/dev/null | grep -i docker || echo "  CAPD provider not found in providers list"

    else
        warn "capd-system namespace does not exist"
        info "CAPD is not installed. Run: ./scripts/bootstrap-capd.sh"
    fi

    echo ""
    echo -e "${BOLD}All Infrastructure Providers:${NC}"
    kubectl --kubeconfig="$kubeconfig" get providers -A 2>/dev/null | grep -E "(NAME|Infrastructure)" || warn "Could not list providers"

    echo ""
    echo -e "${BOLD}Docker Clusters:${NC}"
    kubectl --kubeconfig="$kubeconfig" get clusters -A -l cluster.x-k8s.io/provider=docker 2>/dev/null || echo "  No Docker clusters found"

    echo ""
    echo -e "${BOLD}DockerCluster CRDs:${NC}"
    kubectl --kubeconfig="$kubeconfig" get crds 2>/dev/null | grep docker || echo "  No Docker CRDs found"
}

# Download CAPD components directly from GitHub
download_capd_components() {
    local output_file="$1"

    info "Downloading CAPD ${CAPD_VERSION} from GitHub..."
    info "URL: ${CAPD_GITHUB_URL}"

    # Download with curl
    if curl -sL "${CAPD_GITHUB_URL}" -o "$output_file" 2>/dev/null; then
        if [[ -s "$output_file" ]]; then
            success "Downloaded CAPD components ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            return 0
        fi
    fi

    # Try with -k flag (skip cert verification) as fallback
    warn "Retrying with certificate verification disabled..."
    if curl -skL "${CAPD_GITHUB_URL}" -o "$output_file" 2>/dev/null; then
        if [[ -s "$output_file" ]]; then
            success "Downloaded CAPD components ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            return 0
        fi
    fi

    error "Failed to download CAPD components"
    return 1
}

# Install CAPD directly (bypasses clusterctl)
install_capd_direct() {
    local kubeconfig="$1"
    local tmp_file="/tmp/capd-infrastructure-components.yaml"

    info "Installing CAPD directly from GitHub (bypassing clusterctl)..."
    echo ""

    # Download components
    if ! download_capd_components "$tmp_file"; then
        exit 1
    fi

    echo ""
    info "Applying CAPD components to cluster..."

    if kubectl --kubeconfig="$kubeconfig" apply -f "$tmp_file"; then
        success "CAPD components applied successfully"
        rm -f "$tmp_file"
        return 0
    else
        error "Failed to apply CAPD components"
        rm -f "$tmp_file"
        return 1
    fi
}

# Install CAPD
install_capd() {
    local kubeconfig="$1"
    local direct="${2:-false}"

    print_header "INSTALLING CAPD PROVIDER"

    info "Target cluster kubeconfig: $kubeconfig"
    info "CAPD version: ${CAPD_VERSION}"
    echo ""

    # Verify cluster access
    info "Verifying cluster access..."
    if ! kubectl --kubeconfig="$kubeconfig" cluster-info &> /dev/null; then
        error "Cannot connect to cluster. Check your kubeconfig."
        exit 1
    fi
    success "Cluster is accessible"

    # Check if CAPD already installed
    if kubectl --kubeconfig="$kubeconfig" get namespace capd-system &> /dev/null; then
        warn "CAPD already installed!"
        check_status "$kubeconfig"
        exit 0
    fi

    # Check if Cluster API is initialized
    info "Checking Cluster API installation..."
    if ! kubectl --kubeconfig="$kubeconfig" get namespace capi-system &> /dev/null; then
        warn "Cluster API core (capi-system) not found"
        warn "CAPD requires Cluster API to be installed first"
        echo ""
    else
        success "Cluster API is initialized"
    fi

    echo ""

    # Important warning about Docker requirement
    warn "IMPORTANT: CAPD requires Docker to be running on management cluster nodes!"
    warn "If management cluster nodes don't have Docker, CAPD clusters will fail to create."
    echo ""

    # Use direct download if requested or as fallback
    if [[ "$direct" == "true" ]]; then
        info "Using direct download method (--direct flag)"
        install_capd_direct "$kubeconfig"
    else
        # Try clusterctl first, fall back to direct download
        info "Trying clusterctl init..."
        echo ""
        echo -e "${YELLOW}Running: clusterctl init --infrastructure docker${NC}"
        echo ""

        if KUBECONFIG="$kubeconfig" clusterctl init --infrastructure docker 2>&1; then
            success "clusterctl installation succeeded"
        else
            echo ""
            warn "clusterctl failed (common with TLS/network issues)"
            info "Falling back to direct download method..."
            echo ""
            install_capd_direct "$kubeconfig"
        fi
    fi

    echo ""

    # Verify installation
    info "Verifying installation..."
    sleep 5  # Wait for pods to start

    echo ""
    echo -e "${BOLD}CAPD Pods:${NC}"
    kubectl --kubeconfig="$kubeconfig" get pods -n capd-system

    echo ""
    echo -e "${BOLD}CAPD CRDs:${NC}"
    kubectl --kubeconfig="$kubeconfig" get crds | grep docker || true

    echo ""
    success "CAPD ${CAPD_VERSION} installation complete!"

    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Verify Docker is running on management cluster nodes"
    echo ""
    echo "  2. Apply your Docker cluster configuration:"
    echo "     kubectl apply -k clusters/docker-infra/"
    echo ""
    echo "  3. Monitor cluster creation:"
    echo "     kubectl --kubeconfig=$kubeconfig get clusters -n dm-dev-workspace -w"
    echo ""
    echo "  4. Get kubeconfig for the new cluster:"
    echo "     clusterctl get kubeconfig dm-capd-workload-1 -n dm-dev-workspace > dm-capd-workload-1.kubeconfig"
}

# Main
main() {
    local cluster="mgmt"
    local action="install"
    local direct="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --status)
                action="status"
                shift
                ;;
            --direct)
                direct="true"
                shift
                ;;
            *)
                cluster="$1"
                shift
                ;;
        esac
    done

    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        error "kubectl not found. Install with: brew install kubectl"
        exit 1
    fi

    if [[ "$direct" != "true" ]] && ! command -v clusterctl &> /dev/null; then
        warn "clusterctl not found. Will use direct download method."
        direct="true"
    fi

    success "Prerequisites check passed"

    # Resolve kubeconfig
    local kubeconfig
    kubeconfig=$(resolve_kubeconfig "$cluster")

    # Verify kubeconfig exists
    if [[ ! -f "$kubeconfig" ]]; then
        error "Kubeconfig not found: $kubeconfig"
        exit 1
    fi

    # Execute action
    case "$action" in
        status)
            check_status "$kubeconfig"
            ;;
        install)
            install_capd "$kubeconfig" "$direct"
            ;;
    esac
}

main "$@"

