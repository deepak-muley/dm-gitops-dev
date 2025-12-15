#!/usr/bin/env bash
#
# bootstrap-capk.sh - Install Cluster API Provider Kubemark (CAPK)
#
# This script installs CAPK on a management cluster for creating
# Kubemark clusters (hollow node simulation for scale testing)
#
# Usage:
#   ./scripts/bootstrap-capk.sh [cluster]
#
# Examples:
#   ./scripts/bootstrap-capk.sh              # Install on mgmt cluster (default)
#   ./scripts/bootstrap-capk.sh mgmt         # Install on mgmt cluster
#   ./scripts/bootstrap-capk.sh /path/to/kubeconfig  # Custom kubeconfig
#
# Options:
#   --generate-manifests  Generate CAPK manifests for GitOps (doesn't install)
#   --status              Check CAPK installation status
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
CAPK_MANIFESTS_DIR="${REPO_ROOT}/region-usa/az1/management-cluster/workspaces/dm-dev-workspace/clusters/kubemark-infra/capk-provider"

# CAPK version and URLs
CAPK_VERSION="v0.10.0"
CAPK_GITHUB_URL="https://github.com/kubernetes-sigs/cluster-api-provider-kubemark/releases/download/${CAPK_VERSION}/infrastructure-components.yaml"

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
${BOLD}bootstrap-capk.sh${NC} - Install Cluster API Provider Kubemark (CAPK)

${BOLD}USAGE:${NC}
    ./scripts/bootstrap-capk.sh [OPTIONS] [CLUSTER]

${BOLD}ARGUMENTS:${NC}
    CLUSTER     Cluster shortcut or kubeconfig path (default: mgmt)
                Shortcuts: mgmt, workload1, workload2

${BOLD}OPTIONS:${NC}
    --direct              Download and apply CAPK directly (bypasses clusterctl)
    --generate-manifests  Download CAPK manifests for GitOps (doesn't install)
    --status              Check CAPK installation status
    --help                Show this help message

${BOLD}EXAMPLES:${NC}
    # Install CAPK on management cluster (tries clusterctl, falls back to direct)
    ./scripts/bootstrap-capk.sh
    ./scripts/bootstrap-capk.sh mgmt

    # Install CAPK directly (bypasses clusterctl - use if TLS issues)
    ./scripts/bootstrap-capk.sh --direct mgmt

    # Check CAPK status
    ./scripts/bootstrap-capk.sh --status mgmt

    # Download manifests for GitOps deployment
    ./scripts/bootstrap-capk.sh --generate-manifests

${BOLD}KUBECONFIG SHORTCUTS:${NC}
    mgmt       ${KUBECONFIG_MGMT}
    workload1  ${KUBECONFIG_WORKLOAD1}
    workload2  ${KUBECONFIG_WORKLOAD2}

${BOLD}WHAT IS KUBEMARK?${NC}
    Kubemark creates "hollow" nodes for testing Kubernetes at scale without
    actual compute resources. Each hollow node runs as a pod (~50Mi memory)
    simulating real node behavior. Useful for:
    - Scale testing (100s-1000s of nodes)
    - Performance benchmarking
    - Testing cluster autoscaler
    - Validating controllers at scale

${BOLD}PREREQUISITES:${NC}
    - clusterctl CLI installed (brew install clusterctl)
    - kubectl configured with cluster access
    - Cluster API already initialized on the cluster

EOF
}

# Check prerequisites
check_prerequisites() {
    local missing=0

    if ! command -v clusterctl &> /dev/null; then
        error "clusterctl not found. Install with: brew install clusterctl"
        missing=1
    fi

    if ! command -v kubectl &> /dev/null; then
        error "kubectl not found. Install with: brew install kubectl"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        exit 1
    fi

    success "Prerequisites check passed"
}

# Resolve kubeconfig path
resolve_kubeconfig() {
    local input="$1"

    # Check if it's a shortcut
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
            # Check if it's a file path
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

# Check CAPK status
check_status() {
    local kubeconfig="$1"

    print_header "CAPK STATUS CHECK"

    info "Checking CAPK provider..."
    echo ""

    # Check if capk-system namespace exists
    if kubectl --kubeconfig="$kubeconfig" get namespace capk-system &> /dev/null; then
        success "capk-system namespace exists"

        echo ""
        echo -e "${BOLD}Pods in capk-system:${NC}"
        kubectl --kubeconfig="$kubeconfig" get pods -n capk-system 2>/dev/null || echo "  No pods found"

        echo ""
        echo -e "${BOLD}CAPK Provider:${NC}"
        kubectl --kubeconfig="$kubeconfig" get providers -A 2>/dev/null | grep -i kubemark || echo "  CAPK provider not found in providers list"

    else
        warn "capk-system namespace does not exist"
        info "CAPK is not installed. Run: ./scripts/bootstrap-capk.sh"
    fi

    echo ""
    echo -e "${BOLD}All Cluster API Providers:${NC}"
    kubectl --kubeconfig="$kubeconfig" get providers -A 2>/dev/null || warn "Could not list providers"

    echo ""
    echo -e "${BOLD}Kubemark Clusters:${NC}"
    kubectl --kubeconfig="$kubeconfig" get clusters -A -l cluster.x-k8s.io/provider=kubemark 2>/dev/null || echo "  No Kubemark clusters found"
}

# Download CAPK components directly from GitHub
download_capk_components() {
    local output_file="$1"

    info "Downloading CAPK ${CAPK_VERSION} from GitHub..."
    info "URL: ${CAPK_GITHUB_URL}"

    # Download with curl (use -k to skip cert verification if needed)
    if curl -sL "${CAPK_GITHUB_URL}" -o "$output_file" 2>/dev/null; then
        # Verify file has content
        if [[ -s "$output_file" ]]; then
            success "Downloaded CAPK components ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            return 0
        fi
    fi

    # Try with -k flag (skip cert verification) as fallback
    warn "Retrying with certificate verification disabled..."
    if curl -skL "${CAPK_GITHUB_URL}" -o "$output_file" 2>/dev/null; then
        if [[ -s "$output_file" ]]; then
            success "Downloaded CAPK components ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            return 0
        fi
    fi

    error "Failed to download CAPK components"
    return 1
}

# Generate manifests for GitOps
generate_manifests() {
    print_header "DOWNLOADING CAPK MANIFESTS FOR GITOPS"

    local output_file="${CAPK_MANIFESTS_DIR}/capk-components.yaml"

    info "Target: $output_file"
    echo ""

    # Download directly from GitHub (more reliable than clusterctl generate)
    if download_capk_components "$output_file"; then
        # Show what was downloaded
        echo ""
        echo -e "${BOLD}Downloaded resources:${NC}"
        grep -E "^kind:" "$output_file" | sort | uniq -c || true

        echo ""
        success "Manifests saved to: $output_file"
        echo ""
        warn "Next steps:"
        echo "  1. Review the manifests: $output_file"
        echo "  2. Uncomment 'capk-components.yaml' in:"
        echo "     ${CAPK_MANIFESTS_DIR}/kustomization.yaml"
        echo "  3. Commit and push to git"
        echo "  4. Flux will apply the manifests automatically"
    else
        exit 1
    fi
}

# Install CAPK directly (bypasses clusterctl)
install_capk_direct() {
    local kubeconfig="$1"
    local tmp_file="/tmp/capk-infrastructure-components.yaml"

    info "Installing CAPK directly from GitHub (bypassing clusterctl)..."
    echo ""

    # Download components
    if ! download_capk_components "$tmp_file"; then
        exit 1
    fi

    echo ""
    info "Applying CAPK components to cluster..."

    if kubectl --kubeconfig="$kubeconfig" apply -f "$tmp_file"; then
        success "CAPK components applied successfully"
        rm -f "$tmp_file"
        return 0
    else
        error "Failed to apply CAPK components"
        rm -f "$tmp_file"
        return 1
    fi
}

# Install CAPK
install_capk() {
    local kubeconfig="$1"
    local direct="${2:-false}"

    print_header "INSTALLING CAPK PROVIDER"

    info "Target cluster kubeconfig: $kubeconfig"
    info "CAPK version: ${CAPK_VERSION}"
    echo ""

    # Verify cluster access
    info "Verifying cluster access..."
    if ! kubectl --kubeconfig="$kubeconfig" cluster-info &> /dev/null; then
        error "Cannot connect to cluster. Check your kubeconfig."
        exit 1
    fi
    success "Cluster is accessible"

    # Check if CAPK already installed
    if kubectl --kubeconfig="$kubeconfig" get namespace capk-system &> /dev/null; then
        warn "CAPK already installed!"
        check_status "$kubeconfig"
        exit 0
    fi

    # Check if Cluster API is initialized
    info "Checking Cluster API installation..."
    if ! kubectl --kubeconfig="$kubeconfig" get namespace capi-system &> /dev/null; then
        warn "Cluster API core (capi-system) not found"
        warn "CAPK requires Cluster API to be installed first"
        info "If this is an NKP cluster, CAPI should already be present"
        echo ""
    else
        success "Cluster API is initialized"
    fi

    echo ""

    # Use direct download if requested or as fallback
    if [[ "$direct" == "true" ]]; then
        info "Using direct download method (--direct flag)"
        install_capk_direct "$kubeconfig"
    else
        # Try clusterctl first, fall back to direct download
        info "Trying clusterctl init..."
        echo ""
        echo -e "${YELLOW}Running: clusterctl init --infrastructure kubemark${NC}"
        echo ""

        if KUBECONFIG="$kubeconfig" clusterctl init --infrastructure kubemark 2>&1; then
            success "clusterctl installation succeeded"
        else
            echo ""
            warn "clusterctl failed (common with TLS/network issues)"
            info "Falling back to direct download method..."
            echo ""
            install_capk_direct "$kubeconfig"
        fi
    fi

    echo ""

    # Verify installation
    info "Verifying installation..."
    sleep 5  # Wait for pods to start

    echo ""
    echo -e "${BOLD}CAPK Pods:${NC}"
    kubectl --kubeconfig="$kubeconfig" get pods -n capk-system

    echo ""
    echo -e "${BOLD}CAPK CRDs:${NC}"
    kubectl --kubeconfig="$kubeconfig" get crds | grep kubemark || true

    echo ""
    success "CAPK ${CAPK_VERSION} is ready!"

    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Enable kubemark-infra in clusters/kustomization.yaml:"
    echo "     Uncomment: # - kubemark-infra"
    echo ""
    echo "  2. Commit and push to git"
    echo ""
    echo "  3. Monitor cluster creation:"
    echo "     kubectl --kubeconfig=$kubeconfig get clusters -n dm-dev-workspace -w"
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
            --generate-manifests)
                action="generate"
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

    # Check prerequisites (clusterctl optional for direct install)
    if [[ "$direct" != "true" && "$action" != "generate" ]]; then
        check_prerequisites
    else
        # Only check kubectl for direct/generate
        if ! command -v kubectl &> /dev/null; then
            error "kubectl not found. Install with: brew install kubectl"
            exit 1
        fi
        if ! command -v curl &> /dev/null; then
            error "curl not found"
            exit 1
        fi
        success "Prerequisites check passed"
    fi

    # Resolve kubeconfig
    local kubeconfig
    kubeconfig=$(resolve_kubeconfig "$cluster")

    # Verify kubeconfig exists (except for generate which doesn't need it)
    if [[ "$action" != "generate" && ! -f "$kubeconfig" ]]; then
        error "Kubeconfig not found: $kubeconfig"
        exit 1
    fi

    # Execute action
    case "$action" in
        status)
            check_status "$kubeconfig"
            ;;
        generate)
            generate_manifests
            ;;
        install)
            install_capk "$kubeconfig" "$direct"
            ;;
    esac
}

main "$@"

