#!/bin/bash
#
# Kubescape CVE Report Generator
#
# Usage:
#   ./get-kubescape-cves.sh [severity] [cluster] [--namespace ns1,ns2,...]
#   ./get-kubescape-cves.sh critical mgmt
#   ./get-kubescape-cves.sh high workload1 --namespace default,kube-system
#   ./get-kubescape-cves.sh all workload2 --namespace kommander
#
# Severity options: all, critical, high, medium, low (default: all)
# Cluster options: mgmt, workload1, workload2 (default: mgmt)
# Namespace filter: --namespace ns1,ns2,... (comma-separated, optional)
#
# Author: Platform Team
# Date: December 2024
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default kubeconfig locations for NKP clusters
DEFAULT_MGMT_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
DEFAULT_WORKLOAD1_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
DEFAULT_WORKLOAD2_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

# Parse arguments
SEVERITY="all"
CLUSTER="mgmt"
NAMESPACES=""

# Parse positional and named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACES="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [severity] [cluster] [--namespace ns1,ns2,...]"
            echo ""
            echo "Parameters:"
            echo "  severity    - all, critical, high, medium, low (default: all)"
            echo "  cluster     - mgmt, workload1, workload2 (default: mgmt)"
            echo "  --namespace - Comma-separated list of namespaces to filter (optional)"
            echo ""
            echo "Examples:"
            echo "  $0 critical mgmt"
            echo "  $0 high workload1 --namespace default,kube-system"
            echo "  $0 all workload2 --namespace kommander"
            exit 0
            ;;
        all|critical|high|medium|low)
            SEVERITY="$1"
            shift
            ;;
        mgmt|workload1|workload2)
            CLUSTER="$1"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown argument '$1'${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate severity
case "$SEVERITY" in
    all|critical|high|medium|low)
        ;;
    *)
        echo -e "${RED}Error: Invalid severity '$SEVERITY'${NC}"
        echo "Valid options: all, critical, high, medium, low"
        exit 1
        ;;
esac

# Set kubeconfig based on cluster
case "$CLUSTER" in
    mgmt)
        KUBECONFIG_FILE="$DEFAULT_MGMT_KUBECONFIG"
        CLUSTER_NAME="Management Cluster (dm-nkp-mgmt-1)"
        ;;
    workload1)
        KUBECONFIG_FILE="$DEFAULT_WORKLOAD1_KUBECONFIG"
        CLUSTER_NAME="Workload Cluster 1 (dm-nkp-workload-1)"
        ;;
    workload2)
        KUBECONFIG_FILE="$DEFAULT_WORKLOAD2_KUBECONFIG"
        CLUSTER_NAME="Workload Cluster 2 (dm-nkp-workload-2)"
        ;;
    *)
        echo -e "${RED}Error: Invalid cluster '$CLUSTER'${NC}"
        echo "Valid options: mgmt, workload1, workload2"
        exit 1
        ;;
esac

# Check if kubeconfig exists
if [[ ! -f "$KUBECONFIG_FILE" ]]; then
    echo -e "${RED}Error: Kubeconfig file not found: $KUBECONFIG_FILE${NC}"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"

# Function to print header
print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Function to convert to uppercase (bash 3.2 compatible)
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Function to print severity with color
print_severity() {
    case $1 in
        critical) echo -e "${RED}🔴 CRITICAL${NC}" ;;
        high)     echo -e "${YELLOW}🟠 HIGH${NC}" ;;
        medium)   echo -e "${BLUE}🟡 MEDIUM${NC}" ;;
        low)      echo -e "${GREEN}🟢 LOW${NC}" ;;
        *)        echo -e "⚪ $1" ;;
    esac
}

# Check if kubescape CLI is installed
check_kubescape_cli() {
    if command -v kubescape &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if kubescape operator is installed
check_kubescape_operator() {
    kubectl get crd vulnerabilitymanifestsummaries.spdx.softwarecomposition.kubescape.io &>/dev/null 2>&1 || \
    kubectl get crd vulnerabilitymanifests.spdx.softwarecomposition.kubescape.io &>/dev/null 2>&1 || \
    kubectl get crd vulnerabilitysummaries.spdx.softwarecomposition.kubescape.io &>/dev/null 2>&1 || \
    kubectl get vulnerabilitymanifestsummary -A &>/dev/null 2>&1
}

# Check if namespace matches filter
namespace_matches_filter() {
    local ns="$1"
    local filter="$2"

    # If no filter, match all
    [[ -z "$filter" ]] && return 0

    # Convert comma-separated string to array and check
    IFS=',' read -ra NS_ARRAY <<< "$filter"
    for filter_ns in "${NS_ARRAY[@]}"; do
        if [[ "$ns" == "$filter_ns" ]]; then
            return 0
        fi
    done

    return 1
}

# Get CVEs using kubescape CLI
get_cves_via_cli() {
    local severity_filter="$1"
    local namespace_filter="$2"
    local temp_file=$(mktemp)

    print_header "Scanning cluster with Kubescape CLI"

    # Try vulnerability scan first (most relevant for CVEs)
    if kubescape scan vulnerability --format json --output "$temp_file" 2>/dev/null; then
        # Extract vulnerabilities from vulnerability scan
        if [[ "$severity_filter" == "all" ]]; then
            if [[ -n "$namespace_filter" ]]; then
                # Filter by both severity (all) and namespace
                IFS=',' read -ra NS_ARRAY <<< "$namespace_filter"
                jq -r --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .results[]? |
                select(.resource.namespace as $ns | $ns_filter | index($ns) != null) |
                {
                    cve: .vulnerabilityID,
                    severity: (.severity // "unknown"),
                    description: (.description // ""),
                    component: .resource.name,
                    namespace: .resource.namespace,
                    kind: .resource.kind,
                    image: .resource.containerImage,
                    fixedVersion: .fixedVersion
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            else
                jq -r '
                .results[]? |
                {
                    cve: .vulnerabilityID,
                    severity: (.severity // "unknown"),
                    description: (.description // ""),
                    component: .resource.name,
                    namespace: .resource.namespace,
                    kind: .resource.kind,
                    image: .resource.containerImage,
                    fixedVersion: .fixedVersion
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            fi
        else
            if [[ -n "$namespace_filter" ]]; then
                # Filter by both severity and namespace
                IFS=',' read -ra NS_ARRAY <<< "$namespace_filter"
                jq -r --arg sev "$severity_filter" --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .results[]? |
                select((.severity // "unknown") | ascii_downcase | contains($sev)) |
                select(.resource.namespace as $ns | $ns_filter | index($ns) != null) |
                {
                    cve: .vulnerabilityID,
                    severity: (.severity // "unknown"),
                    description: (.description // ""),
                    component: .resource.name,
                    namespace: .resource.namespace,
                    kind: .resource.kind,
                    image: .resource.containerImage,
                    fixedVersion: .fixedVersion
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            else
                jq -r --arg sev "$severity_filter" '
                .results[]? |
                select((.severity // "unknown") | ascii_downcase | contains($sev)) |
                {
                    cve: .vulnerabilityID,
                    severity: (.severity // "unknown"),
                    description: (.description // ""),
                    component: .resource.name,
                    namespace: .resource.namespace,
                    kind: .resource.kind,
                    image: .resource.containerImage,
                    fixedVersion: .fixedVersion
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            fi
        fi
    # Try framework scans as fallback
    elif kubescape scan framework nsa --format json --output "$temp_file" 2>/dev/null; then
        # Extract vulnerabilities
        if [[ -n "$namespace_filter" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespace_filter"
            if [[ "$severity_filter" == "all" ]]; then
                jq -r --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .summaryDetails.controls[] |
                select(.status == "failed" or .status == "failed") |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | select(.namespace as $ns | $ns_filter | index($ns) != null) | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                } | select(.resources | length > 0)
                ' "$temp_file" 2>/dev/null || echo "[]"
            else
                jq -r --arg sev "$severity_filter" --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .summaryDetails.controls[] |
                select((.status == "failed" or .status == "failed") and
                       ((.controlSeverity // "unknown") | ascii_downcase | contains($sev))) |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | select(.namespace as $ns | $ns_filter | index($ns) != null) | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                } | select(.resources | length > 0)
                ' "$temp_file" 2>/dev/null || echo "[]"
            fi
        else
            if [[ "$severity_filter" == "all" ]]; then
                jq -r '
                .summaryDetails.controls[] |
                select(.status == "failed" or .status == "failed") |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            else
                jq -r --arg sev "$severity_filter" '
                .summaryDetails.controls[] |
                select((.status == "failed" or .status == "failed") and
                       ((.controlSeverity // "unknown") | ascii_downcase | contains($sev))) |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            fi
        fi
    elif kubescape scan framework mitre --format json --output "$temp_file" 2>/dev/null; then
        # Try MITRE framework if NSA fails
        if [[ -n "$namespace_filter" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespace_filter"
            if [[ "$severity_filter" == "all" ]]; then
                jq -r --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .summaryDetails.controls[] |
                select(.status == "failed") |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | select(.namespace as $ns | $ns_filter | index($ns) != null) | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                } | select(.resources | length > 0)
                ' "$temp_file" 2>/dev/null || echo "[]"
            else
                jq -r --arg sev "$severity_filter" --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .summaryDetails.controls[] |
                select(.status == "failed" and
                       ((.controlSeverity // "unknown") | ascii_downcase | contains($sev))) |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | select(.namespace as $ns | $ns_filter | index($ns) != null) | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                } | select(.resources | length > 0)
                ' "$temp_file" 2>/dev/null || echo "[]"
            fi
        else
            if [[ "$severity_filter" == "all" ]]; then
                jq -r '
                .summaryDetails.controls[] |
                select(.status == "failed") |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            else
                jq -r --arg sev "$severity_filter" '
                .summaryDetails.controls[] |
                select(.status == "failed" and
                       ((.controlSeverity // "unknown") | ascii_downcase | contains($sev))) |
                {
                    control: .name,
                    severity: (.controlSeverity // "unknown"),
                    description: (.description // ""),
                    resources: [.resources[]? | {
                        kind: .kind,
                        namespace: .namespace,
                        name: .name,
                        resourceID: .resourceID
                    }]
                }
                ' "$temp_file" 2>/dev/null || echo "[]"
            fi
        fi
    else
        echo "[]"
    fi

    rm -f "$temp_file"
}

# Get CVEs using kubescape operator CRDs
get_cves_via_operator() {
    local severity_filter="$1"
    local namespace_filter="$2"

    print_header "Querying Kubescape Operator CRDs"

    # Use Python script for robust CVE extraction
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local python_script="${script_dir}/extract_cves_from_kubescape.py"

    if [[ ! -f "$python_script" ]]; then
        echo "Error: Python script not found at $python_script" >&2
        echo "[]"
        return
    fi

    # Build command arguments
    local cmd_args=("--severity" "$severity_filter")
    if [[ -n "$namespace_filter" ]]; then
        cmd_args+=("--namespace" "$namespace_filter")
    fi
    if [[ -n "$KUBECONFIG" ]]; then
        cmd_args+=("--kubeconfig" "$KUBECONFIG")
    fi

    # Run Python script and return JSON output
    python3 "$python_script" "${cmd_args[@]}" 2>/dev/null || echo "[]"

    # Legacy code below (kept for reference but not used)
    return

    # Query VulnerabilityManifest resources directly and match to namespaces via VulnerabilityManifestSummary
    if kubectl get crd vulnerabilitymanifests.spdx.softwarecomposition.kubescape.io &>/dev/null 2>&1; then
        # Get all vulnerability manifest summaries for namespace mapping
        local vms_json=$(kubectl get vulnerabilitymanifestsummary -A -o json 2>/dev/null)

        # Get list of vulnerability manifest names that should be queried
        # Query them individually to avoid large JSON responses
        local vm_names=$(kubectl get vulnerabilitymanifest -n kubescape -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

        if [[ -n "$namespace_filter" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespace_filter"
            local all_cves="[]"

            # Query vulnerabilitymanifestsummary by namespace directly to get vulnerabilitymanifest names
            # Query each item individually to avoid JSON truncation issues
            for ns in "${NS_ARRAY[@]}"; do
                local vms_names=$(kubectl get vulnerabilitymanifestsummary -n "$ns" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)

                if [[ -z "$vms_names" ]]; then
                    echo "DEBUG: No vulnerabilitymanifestsummary found in namespace $ns" >&2
                    continue
                fi

                for vms_name in $vms_names; do
                    local vm_name=$(kubectl get vulnerabilitymanifestsummary "$vms_name" -n "$ns" -o json 2>/dev/null | jq -r '(.spec.vulnerabilitiesRef.all.name // .spec.vulnerabilitiesRef.relevant.name) | select(. != null and . != "")' 2>/dev/null)

                    if [[ -z "$vm_name" ]]; then
                        echo "DEBUG: No VM name found for $vms_name" >&2
                        continue
                    fi
                    # Get the vulnerability manifest - use temp file to avoid shell variable mangling
                    local tmp_file=$(mktemp)
                    kubectl get vulnerabilitymanifest "$vm_name" -n kubescape -o json > "$tmp_file" 2>/dev/null

                    # Check if it has matches using Python (more robust than jq for malformed JSON)
                    local has_matches=$(python3 -c "
import sys, json
try:
    with open(sys.argv[1], 'r', encoding='utf-8', errors='ignore') as f:
        data = json.load(f)
    matches = data.get('spec', {}).get('payload', {}).get('matches', [])
    print('true' if matches and len(matches) > 0 else 'false')
except:
    print('false')
" "$tmp_file" 2>/dev/null)

                    if [[ "$has_matches" == "true" ]]; then
                        echo "DEBUG: Processing CVEs for $vm_name in namespace $ns" >&2
                        # Use Python for robust JSON parsing (handles escape sequences better than jq)
                        local cves=$(python3 -c "
import sys, json
try:
    with open(sys.argv[3], 'r', encoding='utf-8', errors='ignore') as f:
        data = json.load(f)
    matches = data.get('spec', {}).get('payload', {}).get('matches', [])
    sev_filter = sys.argv[1]
    ns_val = sys.argv[2]

    cve_list = []
    seen_cves = set()

    for m in matches:
        vuln = m.get('vulnerability')
        if not vuln:
            continue

        severity = vuln.get('severity', 'unknown').lower()
        if sev_filter != 'all' and sev_filter not in severity:
            continue

        cve_id = vuln.get('id')
        if not cve_id or cve_id in seen_cves:
            continue
        seen_cves.add(cve_id)

        artifact = m.get('artifact', {})
        fix_versions = vuln.get('fix', {}).get('versions', [])

        cve_list.append({
            'cve': cve_id,
            'severity': vuln.get('severity', 'unknown'),
            'description': vuln.get('description', ''),
            'component': artifact.get('name', ''),
            'namespace': ns_val,
            'image': artifact.get('name', ''),
            'fixedVersion': fix_versions[0] if fix_versions else ''
        })

    print(json.dumps(cve_list))
except Exception as e:
    print('[]')
" "$severity_filter" "$ns" "$tmp_file" 2>/dev/null)
                    rm -f "$tmp_file"

                        if [[ "$cves" != "[]" && -n "$cves" && "$cves" != "null" ]]; then
                            if [[ "$all_cves" == "[]" ]]; then
                                all_cves="$cves"
                            else
                                all_cves=$(echo "$all_cves" "$cves" | jq -s 'add | unique_by(.cve)')
                            fi
                        fi
                    fi
                done
            done
            echo "$all_cves" | jq '.' || echo "[]"
        else
            local all_cves="[]"

            for vm_name in $vm_names; do
                # Use temp file to avoid shell variable mangling
                local tmp_file=$(mktemp)
                kubectl get vulnerabilitymanifest "$vm_name" -n kubescape -o json > "$tmp_file" 2>/dev/null

                if [[ ! -s "$tmp_file" ]]; then
                    rm -f "$tmp_file"
                    continue
                fi

                # Check if it has matches using Python (more robust than jq for malformed JSON)
                local has_matches=$(python3 -c "
import sys, json
try:
    with open(sys.argv[1], 'r', encoding='utf-8', errors='ignore') as f:
        data = json.load(f)
    matches = data.get('spec', {}).get('payload', {}).get('matches', [])
    print('true' if matches and len(matches) > 0 else 'false')
except:
    print('false')
" "$tmp_file" 2>/dev/null)

                if [[ "$has_matches" == "true" ]]; then
                    local workload_ns_list=$(echo "$vms_json" | jq -r --arg vm_name "$vm_name" '
                        .items[] |
                        select(.spec.vulnerabilitiesRef.all.name == $vm_name or .spec.vulnerabilitiesRef.relevant.name == $vm_name) |
                        .metadata.labels."kubescape.io/workload-namespace" // .metadata.namespace
                    ' 2>/dev/null | sort -u)

                    for workload_ns in $workload_ns_list; do
                        # Use Python for robust JSON parsing (handles escape sequences better than jq)
                        local cves=$(python3 -c "
import sys, json
try:
    with open(sys.argv[3], 'r', encoding='utf-8', errors='ignore') as f:
        data = json.load(f)
    matches = data.get('spec', {}).get('payload', {}).get('matches', [])
    sev_filter = sys.argv[1]
    ns_val = sys.argv[2]

    cve_list = []
    seen_cves = set()

    for m in matches:
        vuln = m.get('vulnerability')
        if not vuln:
            continue

        severity = vuln.get('severity', 'unknown').lower()
        if sev_filter != 'all' and sev_filter not in severity:
            continue

        cve_id = vuln.get('id')
        if not cve_id or cve_id in seen_cves:
            continue
        seen_cves.add(cve_id)

        artifact = m.get('artifact', {})
        fix_versions = vuln.get('fix', {}).get('versions', [])

        cve_list.append({
            'cve': cve_id,
            'severity': vuln.get('severity', 'unknown'),
            'description': vuln.get('description', ''),
            'component': artifact.get('name', ''),
            'namespace': ns_val,
            'image': artifact.get('name', ''),
            'fixedVersion': fix_versions[0] if fix_versions else ''
        })

    print(json.dumps(cve_list))
except Exception as e:
    print('[]')
" "$severity_filter" "$workload_ns" "$tmp_file" 2>/dev/null)

                        if [[ "$cves" != "[]" && -n "$cves" && "$cves" != "null" ]]; then
                            if [[ "$all_cves" == "[]" ]]; then
                                all_cves="$cves"
                            else
                                all_cves=$(echo "$all_cves" "$cves" | jq -s 'add | unique_by(.cve)')
                            fi
                        fi
                    done
                    rm -f "$tmp_file"
                fi
            done
            echo "$all_cves" | jq '.' || echo "[]"
        fi
    # Fallback to VulnerabilitySummary CRD (older format)
    elif kubectl get crd vulnerabilitysummaries.operator.kubescape.io &>/dev/null 2>&1; then
        if [[ -n "$namespace_filter" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespace_filter"
            if [[ "$severity_filter" == "all" ]]; then
                kubectl get vulnerabilitysummary -A -o json 2>/dev/null | jq -r --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .items[] |
                select(.metadata.namespace as $ns | $ns_filter | index($ns) != null) |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    vulnerabilities: [.status.vulnerabilities[]? | {
                        cve: .id,
                        severity: .severity,
                        description: .description,
                        component: .component,
                        fixedVersion: .fixedVersion
                    }]
                }
                ' 2>/dev/null || echo "[]"
            else
                kubectl get vulnerabilitysummary -A -o json 2>/dev/null | jq -r --arg sev "$severity_filter" --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .items[] |
                select(.metadata.namespace as $ns | $ns_filter | index($ns) != null) |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    vulnerabilities: [.status.vulnerabilities[]? |
                        select((.severity // "unknown") | ascii_downcase | contains($sev)) |
                        {
                            cve: .id,
                            severity: .severity,
                            description: .description,
                            component: .component,
                            fixedVersion: .fixedVersion
                        }]
                } | select(.vulnerabilities | length > 0)
                ' 2>/dev/null || echo "[]"
            fi
        else
            if [[ "$severity_filter" == "all" ]]; then
                kubectl get vulnerabilitysummary -A -o json 2>/dev/null | jq -r '
                .items[] |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    vulnerabilities: [.status.vulnerabilities[]? | {
                        cve: .id,
                        severity: .severity,
                        description: .description,
                        component: .component,
                        fixedVersion: .fixedVersion
                    }]
                }
                ' 2>/dev/null || echo "[]"
            else
                kubectl get vulnerabilitysummary -A -o json 2>/dev/null | jq -r --arg sev "$severity_filter" '
                .items[] |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    vulnerabilities: [.status.vulnerabilities[]? |
                        select((.severity // "unknown") | ascii_downcase | contains($sev)) |
                        {
                            cve: .id,
                            severity: .severity,
                            description: .description,
                            component: .component,
                            fixedVersion: .fixedVersion
                        }]
                } | select(.vulnerabilities | length > 0)
                ' 2>/dev/null || echo "[]"
            fi
        fi
    # Try ConfigScan CRD
    elif kubectl get crd configscans.operator.kubescape.io &>/dev/null 2>&1; then
        if [[ -n "$namespace_filter" ]]; then
            IFS=',' read -ra NS_ARRAY <<< "$namespace_filter"
            if [[ "$severity_filter" == "all" ]]; then
                kubectl get configscan -A -o json 2>/dev/null | jq -r --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .items[] |
                select(.metadata.namespace as $ns | $ns_filter | index($ns) != null) |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    findings: [.status.findings[]? | {
                        control: .controlID,
                        severity: .severity,
                        description: .description,
                        resources: .resources
                    }]
                }
                ' 2>/dev/null || echo "[]"
            else
                kubectl get configscan -A -o json 2>/dev/null | jq -r --arg sev "$severity_filter" --argjson ns_filter "$(printf '%s\n' "${NS_ARRAY[@]}" | jq -R . | jq -s .)" '
                .items[] |
                select(.metadata.namespace as $ns | $ns_filter | index($ns) != null) |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    findings: [.status.findings[]? |
                        select((.severity // "unknown") | ascii_downcase | contains($sev)) |
                        {
                            control: .controlID,
                            severity: .severity,
                            description: .description,
                            resources: .resources
                        }]
                } | select(.findings | length > 0)
                ' 2>/dev/null || echo "[]"
            fi
        else
            if [[ "$severity_filter" == "all" ]]; then
                kubectl get configscan -A -o json 2>/dev/null | jq -r '
                .items[] |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    findings: [.status.findings[]? | {
                        control: .controlID,
                        severity: .severity,
                        description: .description,
                        resources: .resources
                    }]
                }
                ' 2>/dev/null || echo "[]"
            else
                kubectl get configscan -A -o json 2>/dev/null | jq -r --arg sev "$severity_filter" '
                .items[] |
                {
                    namespace: .metadata.namespace,
                    name: .metadata.name,
                    findings: [.status.findings[]? |
                        select((.severity // "unknown") | ascii_downcase | contains($sev)) |
                        {
                            control: .controlID,
                            severity: .severity,
                            description: .description,
                            resources: .resources
                        }]
                } | select(.findings | length > 0)
                ' 2>/dev/null || echo "[]"
            fi
        fi
    else
        echo "[]"
    fi
}

# Display CVE report
display_cve_report() {
    local cve_data="$1"
    local severity_filter="$2"
    local namespace_filter="$3"

    local header_text="CVE Report - $CLUSTER_NAME (Severity: $(to_upper "$severity_filter"))"
    if [[ -n "$namespace_filter" ]]; then
        header_text="${header_text} [Namespaces: $namespace_filter]"
    fi
    print_header "$header_text"

    if [[ "$cve_data" == "[]" || -z "$cve_data" ]]; then
        echo -e "${GREEN}✓ No CVEs found matching severity filter: $severity_filter${NC}"
        echo ""
        return
    fi

    # Count CVEs by severity
    local critical_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("critical"))] | length' 2>/dev/null || echo "0")
    local high_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("high"))] | length' 2>/dev/null || echo "0")
    local medium_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("medium"))] | length' 2>/dev/null || echo "0")
    local low_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("low"))] | length' 2>/dev/null || echo "0")

    echo -e "${CYAN}Summary:${NC}"
    echo -e "  ${RED}Critical: $critical_count${NC}"
    echo -e "  ${YELLOW}High: $high_count${NC}"
    echo -e "  ${BLUE}Medium: $medium_count${NC}"
    echo -e "  ${GREEN}Low: $low_count${NC}"
    echo ""

    # Group by severity
    for sev in critical high medium low; do
        if [[ "$severity_filter" == "all" || "$severity_filter" == "$sev" ]]; then
            local sev_data=$(echo "$cve_data" | jq -r --arg sev "$sev" '
                [.[] | select((.severity // "unknown") | ascii_downcase | contains($sev))]
            ' 2>/dev/null)

            if [[ "$sev_data" != "[]" && -n "$sev_data" ]]; then
                local sev_count=$(echo "$sev_data" | jq 'length' 2>/dev/null || echo "0")
                if [[ "$sev_count" -gt 0 ]]; then
                    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
                    print_severity "$sev"
                    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
                    echo ""

                    # Check if it's vulnerability format (has CVE ID)
                    if echo "$sev_data" | jq -e '.[0].cve' &>/dev/null; then
                        # Vulnerability format
                        echo "$sev_data" | jq -r '.[] |
                            "CVE: \(.cve // "N/A")
Severity: \(.severity // "unknown")
Component: \(.component // "N/A")
Namespace: \(.namespace // "N/A")
Kind: \(.kind // "N/A")
Image: \(.image // "N/A")
Fixed Version: \(.fixedVersion // "N/A")
Description: \(.description // "N/A")
────────────────────────────────────────────────────────────────"
                        ' 2>/dev/null
                    # Check if it's control format (has control name)
                    elif echo "$sev_data" | jq -e '.[0].control' &>/dev/null; then
                        # Control format
                        echo "$sev_data" | jq -r '.[] |
                            "Control: \(.control // "N/A")
Severity: \(.severity // "unknown")
Description: \(.description // "N/A")
Affected Resources:
\(.resources // [] | .[]? | "  - \(.kind // "N/A")/\(.name // "N/A") in namespace \(.namespace // "default")")
────────────────────────────────────────────────────────────────"
                        ' 2>/dev/null
                    else
                        # Generic format
                        echo "$sev_data" | jq -r '.[] | to_entries | map("\(.key): \(.value)") | join("\n")' 2>/dev/null
                        echo "────────────────────────────────────────────────────────────────"
                    fi
                    echo ""
                fi
            fi
        fi
    done
}

# Generate Jira-friendly report
generate_jira_report() {
    local cve_data="$1"
    local severity_filter="$2"
    local namespace_filter="$3"

    local report_suffix="${CLUSTER}-${severity_filter}"
    if [[ -n "$namespace_filter" ]]; then
        # Replace commas with dashes for filename
        local ns_suffix=$(echo "$namespace_filter" | tr ',' '-')
        report_suffix="${report_suffix}-ns-${ns_suffix}"
    fi
    local report_file="kubescape-cve-report-${report_suffix}-$(date +%Y%m%d-%H%M%S).md"

    print_header "Generating Jira Report"

    {
        echo "# Kubescape CVE Report"
        echo ""
        echo "**Cluster:** $CLUSTER_NAME"
        echo "**Severity Filter:** $(to_upper "$severity_filter")"
        if [[ -n "$namespace_filter" ]]; then
            echo "**Namespace Filter:** $namespace_filter"
        fi
        echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "---"
        echo ""

        if [[ "$cve_data" == "[]" || -z "$cve_data" ]]; then
            echo "## Summary"
            echo ""
            echo "✅ No CVEs found matching severity filter: \`$severity_filter\`"
            echo ""
        else
            # Summary
            local critical_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("critical"))] | length' 2>/dev/null || echo "0")
            local high_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("high"))] | length' 2>/dev/null || echo "0")
            local medium_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("medium"))] | length' 2>/dev/null || echo "0")
            local low_count=$(echo "$cve_data" | jq '[.[] | select(.severity | ascii_downcase | contains("low"))] | length' 2>/dev/null || echo "0")

            echo "## Summary"
            echo ""
            echo "| Severity | Count |"
            echo "|----------|-------|"
            echo "| 🔴 Critical | $critical_count |"
            echo "| 🟠 High | $high_count |"
            echo "| 🟡 Medium | $medium_count |"
            echo "| 🟢 Low | $low_count |"
            echo ""
            echo "---"
            echo ""

            # Detailed findings
            echo "## Detailed Findings"
            echo ""

            for sev in critical high medium low; do
                if [[ "$severity_filter" == "all" || "$severity_filter" == "$sev" ]]; then
                    local sev_data=$(echo "$cve_data" | jq -r --arg sev "$sev" '
                        [.[] | select((.severity // "unknown") | ascii_downcase | contains($sev))]
                    ' 2>/dev/null)

                    if [[ "$sev_data" != "[]" && -n "$sev_data" ]]; then
                        local sev_count=$(echo "$sev_data" | jq 'length' 2>/dev/null || echo "0")
                        if [[ "$sev_count" -gt 0 ]]; then
                            echo "### $(to_upper "$sev") Severity CVEs"
                            echo ""

                            # Check if it's vulnerability format
                            if echo "$sev_data" | jq -e '.[0].cve' &>/dev/null; then
                                echo "| CVE ID | Component | Namespace | Kind | Image | Fixed Version | Description |"
                                echo "|--------|-----------|-----------|------|-------|--------------|-------------|"
                                echo "$sev_data" | jq -r '.[] |
                                    "| \(.cve // "N/A") | \(.component // "N/A") | \(.namespace // "N/A") | \(.kind // "N/A") | \(.image // "N/A") | \(.fixedVersion // "N/A") | \(.description // "N/A") |"
                                ' 2>/dev/null
                            # Check if it's control format
                            elif echo "$sev_data" | jq -e '.[0].control' &>/dev/null; then
                                echo "$sev_data" | jq -r '.[] |
                                    "#### \(.control // "N/A")

**Severity:** \(.severity // "unknown")
**Description:** \(.description // "N/A")

**Affected Resources:**
\(.resources // [] | .[]? | "- \(.kind // "N/A")/\(.name // "N/A") in namespace \(.namespace // "default")")

---"
                                ' 2>/dev/null
                            fi
                            echo ""
                        fi
                    fi
                fi
            done
        fi

        echo "---"
        echo ""
        echo "*Report generated by kubescape CVE scanner*"
    } > "$report_file"

    echo -e "${GREEN}✓ Jira report saved to: $report_file${NC}"
    echo ""
}

# Main execution
print_header "Kubescape CVE Scanner"
echo -e "${CYAN}Cluster:${NC} $CLUSTER_NAME"
echo -e "${CYAN}Severity Filter:${NC} $(to_upper "$SEVERITY")"
if [[ -n "$NAMESPACES" ]]; then
    echo -e "${CYAN}Namespace Filter:${NC} $NAMESPACES"
fi
echo -e "${CYAN}Kubeconfig:${NC} $KUBECONFIG_FILE"
echo ""

CVE_DATA="[]"

# Prefer operator CRDs if available (they contain already-scanned data)
if check_kubescape_operator; then
    echo -e "${GREEN}✓ Kubescape Operator detected${NC}"
    CVE_DATA=$(get_cves_via_operator "$SEVERITY" "$NAMESPACES")

    # If operator didn't return useful data, try CLI as fallback
    if [[ "$CVE_DATA" == "[]" || -z "$CVE_DATA" ]]; then
        if check_kubescape_cli; then
            echo -e "${YELLOW}⚠ Operator returned no results, trying CLI scan...${NC}"
            CVE_DATA=$(get_cves_via_cli "$SEVERITY" "$NAMESPACES")
        fi
    fi
# Try CLI if operator not available
elif check_kubescape_cli; then
    echo -e "${GREEN}✓ Kubescape CLI detected${NC}"
    CVE_DATA=$(get_cves_via_cli "$SEVERITY" "$NAMESPACES")
else
    echo -e "${RED}✗ Error: Neither kubescape CLI nor operator found${NC}"
    echo ""
    echo "To install kubescape CLI:"
    echo "  brew install kubescape  # macOS"
    echo "  or visit: https://kubescape.io/docs/install-cli/"
    echo ""
    exit 1
fi

# Display report
display_cve_report "$CVE_DATA" "$SEVERITY" "$NAMESPACES"

# Generate Jira report
generate_jira_report "$CVE_DATA" "$SEVERITY" "$NAMESPACES"

print_header "Report Complete"
echo -e "${GREEN}✓ CVE scan completed${NC}"
echo ""
echo "To view the Jira report:"
if [[ -n "$NAMESPACES" ]]; then
    ns_suffix=$(echo "$NAMESPACES" | tr ',' '-')
    echo -e "  ${CYAN}cat kubescape-cve-report-${CLUSTER}-${SEVERITY}-ns-${ns_suffix}-*.md${NC}"
else
    echo -e "  ${CYAN}cat kubescape-cve-report-${CLUSTER}-${SEVERITY}-*.md${NC}"
fi
echo ""

