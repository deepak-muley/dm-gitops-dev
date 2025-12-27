#!/bin/bash

# Script to list container images with their tags, deployment names, pod names, and image details
# Usage: ./list-container-images.sh [--cluster CLUSTER] [--namespace NAMESPACES]
#   --cluster, -c: Cluster to query (mgmt, workload1, workload2). Default: current kubectl context
#   --namespace, -n: Comma-separated list of namespaces (e.g., "default,kube-system,dm-dev-workspace")
#                    If not provided, lists images from all namespaces
#
# Examples:
#   ./list-container-images.sh --cluster mgmt
#   ./list-container-images.sh --cluster workload1 --namespace default,kube-system
#   ./list-container-images.sh -c workload2 -n dm-dev-workspace
#   ./list-container-images.sh --namespace default                    # Uses current kubectl context

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Kubeconfig paths
KUBECONFIG_MGMT="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
KUBECONFIG_WORKLOAD1="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
KUBECONFIG_WORKLOAD2="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

# Function to print header
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Function to set kubeconfig based on cluster
set_kubeconfig() {
    local cluster="$1"
    local kubeconfig_path=""

    case "$cluster" in
        mgmt)
            kubeconfig_path="$KUBECONFIG_MGMT"
            ;;
        workload1)
            kubeconfig_path="$KUBECONFIG_WORKLOAD1"
            ;;
        workload2)
            kubeconfig_path="$KUBECONFIG_WORKLOAD2"
            ;;
        *)
            echo -e "${RED}Error: Invalid cluster '$cluster'. Must be one of: mgmt, workload1, workload2${NC}" >&2
            exit 1
            ;;
    esac

    if [ ! -f "$kubeconfig_path" ]; then
        echo -e "${RED}Error: Kubeconfig file not found: $kubeconfig_path${NC}" >&2
        exit 1
    fi

    export KUBECONFIG="$kubeconfig_path"
    echo -e "${GREEN}Using cluster: $cluster (kubeconfig: $kubeconfig_path)${NC}"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [--cluster CLUSTER | -c CLUSTER] [--namespace NAMESPACES | -n NAMESPACES]"
    echo ""
    echo "Options:"
    echo "  --cluster, -c         Cluster to query (mgmt, workload1, workload2)"
    echo "                        If not specified, uses current kubectl context"
    echo ""
    echo "  --namespace, -n       Comma-separated list of namespaces to query"
    echo "                        Example: \"default,kube-system,dm-dev-workspace\""
    echo "                        If not specified, queries all namespaces"
    echo ""
    echo "Examples:"
    echo "  $0 --cluster mgmt"
    echo "  $0 --cluster workload1 --namespace default,kube-system"
    echo "  $0 -c workload2 -n dm-dev-workspace"
    echo "  $0 --namespace default                    # Uses current kubectl context"
    echo "  $0 --cluster mgmt --namespace default,kube-system,dm-dev-workspace"
}

# Function to extract image tag from image string
extract_tag() {
    local image="$1"
    if [[ "$image" == *":"* ]]; then
        echo "${image##*:}"
    else
        echo "latest"
    fi
}

# Function to extract image path (without tag)
extract_image_path() {
    local image="$1"
    if [[ "$image" == *":"* ]]; then
        echo "${image%:*}"
    else
        echo "$image"
    fi
}

# Function to get deployment name from pod
get_deployment_name() {
    local namespace="$1"
    local pod_name="$2"

    # Try to get owner reference (ReplicaSet -> Deployment)
    local owner_ref=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="ReplicaSet")].name}' 2>/dev/null || echo "")

    if [ -n "$owner_ref" ]; then
        # Get the deployment name from the ReplicaSet
        local deployment=$(kubectl get replicaset "$owner_ref" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}' 2>/dev/null || echo "")
        if [ -n "$deployment" ]; then
            echo "$deployment"
            return
        fi
    fi

    # Try direct owner reference to Deployment
    local direct_deployment=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}' 2>/dev/null || echo "")
    if [ -n "$direct_deployment" ]; then
        echo "$direct_deployment"
        return
    fi

    # Try StatefulSet
    local statefulset=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="StatefulSet")].name}' 2>/dev/null || echo "")
    if [ -n "$statefulset" ]; then
        echo "StatefulSet: $statefulset"
        return
    fi

    # Try DaemonSet
    local daemonset=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="DaemonSet")].name}' 2>/dev/null || echo "")
    if [ -n "$daemonset" ]; then
        echo "DaemonSet: $daemonset"
        return
    fi

    # Try Job
    local job=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Job")].name}' 2>/dev/null || echo "")
    if [ -n "$job" ]; then
        echo "Job: $job"
        return
    fi

    # If no owner found, return "N/A"
    echo "N/A"
}

# Function to process a namespace
process_namespace() {
    local namespace="$1"

    echo ""
    print_header "Namespace: $namespace"

    # Get all pods in the namespace
    local pods=$(kubectl get pods -n "$namespace" -o json 2>/dev/null || echo '{"items":[]}')

    if [ "$(echo "$pods" | jq -r '.items | length')" -eq 0 ]; then
        echo -e "${YELLOW}No pods found in namespace: $namespace${NC}"
        return
    fi

    # Print table header
    printf "%-40s %-50s %-60s %-30s %-20s\n" "DEPLOYMENT" "POD NAME" "IMAGE PATH" "IMAGE TAG" "CONTAINER TYPE"
    printf "%-40s %-50s %-60s %-30s %-20s\n" "$(printf '=%.0s' {1..40})" "$(printf '=%.0s' {1..50})" "$(printf '=%.0s' {1..60})" "$(printf '=%.0s' {1..30})" "$(printf '=%.0s' {1..20})"

    # Get list of pod names
    local pod_names=($(echo "$pods" | jq -r '.items[].metadata.name'))

    # Process each pod
    for pod_name in "${pod_names[@]}"; do
        # Get deployment name once per pod (cached for efficiency)
        local deployment=$(get_deployment_name "$namespace" "$pod_name")

        # Process regular containers
        local container_count=$(echo "$pods" | jq -r ".items[] | select(.metadata.name == \"$pod_name\") | .spec.containers | length")

        for ((i=0; i<container_count; i++)); do
            local image=$(echo "$pods" | jq -r ".items[] | select(.metadata.name == \"$pod_name\") | .spec.containers[$i].image // empty")

            if [ -n "$image" ] && [ "$image" != "null" ]; then
                local image_path=$(extract_image_path "$image")
                local image_tag=$(extract_tag "$image")

                printf "%-40s %-50s %-60s %-30s %-20s\n" \
                    "$deployment" "$pod_name" "$image_path" "$image_tag" "Container"
            fi
        done

        # Process init containers
        local init_container_count=$(echo "$pods" | jq -r ".items[] | select(.metadata.name == \"$pod_name\") | .spec.initContainers // [] | length")

        for ((i=0; i<init_container_count; i++)); do
            local init_image=$(echo "$pods" | jq -r ".items[] | select(.metadata.name == \"$pod_name\") | .spec.initContainers[$i].image // empty")

            if [ -n "$init_image" ] && [ "$init_image" != "null" ]; then
                local image_path=$(extract_image_path "$init_image")
                local image_tag=$(extract_tag "$init_image")

                printf "%-40s %-50s %-60s %-30s %-20s\n" \
                    "$deployment" "$pod_name" "$image_path" "$image_tag" "InitContainer"
            fi
        done
    done
}

# Main script
main() {
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}" >&2
        exit 1
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed or not in PATH${NC}" >&2
        echo -e "${YELLOW}Please install jq: brew install jq (macOS) or apt-get install jq (Linux)${NC}" >&2
        exit 1
    fi

    # Parse arguments
    local cluster=""
    local namespace_list=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster|-c)
                if [ -z "${2:-}" ]; then
                    echo -e "${RED}Error: --cluster requires a value (mgmt, workload1, workload2)${NC}" >&2
                    show_usage
                    exit 1
                fi
                cluster="$2"
                shift 2
                ;;
            --namespace|-n)
                if [ -z "${2:-}" ]; then
                    echo -e "${RED}Error: --namespace requires a value (comma-separated list)${NC}" >&2
                    show_usage
                    exit 1
                fi
                namespace_list="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
                echo -e "${YELLOW}Use --namespace or -n to specify namespaces${NC}" >&2
                show_usage
                exit 1
                ;;
        esac
    done

    # Parse comma-separated namespaces
    local namespaces=()
    if [ -n "$namespace_list" ]; then
        # Save current IFS
        local old_ifs="$IFS"
        # Split comma-separated string into array
        IFS=',' read -ra namespaces <<< "$namespace_list"
        # Restore IFS
        IFS="$old_ifs"
        # Trim whitespace from each namespace
        local trimmed_namespaces=()
        for ns in "${namespaces[@]}"; do
            trimmed_ns=$(echo "$ns" | xargs)  # xargs trims whitespace
            if [ -n "$trimmed_ns" ]; then
                trimmed_namespaces+=("$trimmed_ns")
            fi
        done
        namespaces=("${trimmed_namespaces[@]}")
    fi

    # Set kubeconfig if cluster is specified
    if [ -n "$cluster" ]; then
        set_kubeconfig "$cluster"
    else
        echo -e "${GREEN}Using current kubectl context${NC}"
    fi

    # Check if we can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}" >&2
        if [ -n "$cluster" ]; then
            echo -e "${YELLOW}Please verify the kubeconfig file exists and is valid${NC}" >&2
        else
            echo -e "${YELLOW}Please verify your kubectl context is set correctly${NC}" >&2
        fi
        exit 1
    fi

    # Get cluster name for display
    local cluster_name=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}' 2>/dev/null || echo "unknown")

    # Determine namespaces to process
    if [ ${#namespaces[@]} -eq 0 ]; then
        # No namespaces provided, get all namespaces
        echo -e "${GREEN}No namespaces specified. Listing images from all namespaces...${NC}"
        namespaces=($(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'))
    fi

    if [ ${#namespaces[@]} -eq 0 ]; then
        echo -e "${YELLOW}No namespaces found${NC}"
        exit 0
    fi

    # Print summary
    print_header "Container Images Report"
    echo -e "${GREEN}Cluster: $cluster_name${NC}"
    echo -e "${GREEN}Processing ${#namespaces[@]} namespace(s)${NC}"
    echo ""

    # Process each namespace
    for namespace in "${namespaces[@]}"; do
        # Verify namespace exists
        if ! kubectl get namespace "$namespace" &> /dev/null; then
            echo -e "${RED}Warning: Namespace '$namespace' does not exist, skipping...${NC}" >&2
            continue
        fi

        process_namespace "$namespace"
    done

    echo ""
    echo -e "${GREEN}Report complete!${NC}"
}

# Run main function
main "$@"

