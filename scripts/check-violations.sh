#!/bin/bash
#
# NKP Gatekeeper Violations Checker
# 
# Usage:
#   ./check-violations.sh                    # Uses default kubeconfig
#   ./check-violations.sh /path/to/kubeconfig # Uses specified kubeconfig
#   ./check-violations.sh --summary          # Show only summary
#   ./check-violations.sh --export           # Export to violations-report.json
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
NC='\033[0m' # No Color

# Default kubeconfig locations for NKP clusters
DEFAULT_MGMT_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
DEFAULT_WORKLOAD1_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig"
DEFAULT_WORKLOAD2_KUBECONFIG="/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig"

KUBECONFIG_FILE=""
SUMMARY_ONLY=false
EXPORT_JSON=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --summary)
            SUMMARY_ONLY=true
            shift
            ;;
        --export)
            EXPORT_JSON=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [KUBECONFIG_PATH]"
            echo ""
            echo "Options:"
            echo "  --summary    Show only violation summary (no details)"
            echo "  --export     Export full violations to violations-report.json"
            echo "  --help       Show this help message"
            echo ""
            echo "Kubeconfig shortcuts:"
            echo "  mgmt         Use management cluster kubeconfig"
            echo "  workload1    Use workload cluster 1 kubeconfig"
            echo "  workload2    Use workload cluster 2 kubeconfig"
            echo ""
            echo "Examples:"
            echo "  $0                           # Uses default kubeconfig"
            echo "  $0 mgmt                      # Uses management cluster"
            echo "  $0 /path/to/kubeconfig       # Uses specified file"
            echo "  $0 --summary mgmt            # Summary only for mgmt cluster"
            exit 0
            ;;
        mgmt)
            KUBECONFIG_FILE="$DEFAULT_MGMT_KUBECONFIG"
            shift
            ;;
        workload1)
            KUBECONFIG_FILE="$DEFAULT_WORKLOAD1_KUBECONFIG"
            shift
            ;;
        workload2)
            KUBECONFIG_FILE="$DEFAULT_WORKLOAD2_KUBECONFIG"
            shift
            ;;
        *)
            if [[ -f "$1" ]]; then
                KUBECONFIG_FILE="$1"
            else
                echo -e "${RED}Error: File not found: $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set kubeconfig
if [[ -n "$KUBECONFIG_FILE" ]]; then
    export KUBECONFIG="$KUBECONFIG_FILE"
    echo -e "${BLUE}Using kubeconfig: $KUBECONFIG_FILE${NC}"
elif [[ -f "$DEFAULT_MGMT_KUBECONFIG" ]]; then
    export KUBECONFIG="$DEFAULT_MGMT_KUBECONFIG"
    echo -e "${BLUE}Using default kubeconfig: $DEFAULT_MGMT_KUBECONFIG${NC}"
fi

# Check kubectl connectivity
echo -e "${BLUE}Checking cluster connectivity...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to cluster. Check your kubeconfig.${NC}"
    exit 1
fi

CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
echo -e "${GREEN}Connected to cluster: $CLUSTER_NAME${NC}"
echo ""

# Function to print section header
print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# Function to print severity with color
print_severity() {
    case $1 in
        critical) echo -e "${RED}🔴 CRITICAL${NC}" ;;
        high)     echo -e "${YELLOW}🟠 HIGH${NC}" ;;
        medium)   echo -e "${BLUE}🟡 MEDIUM${NC}" ;;
        *)        echo -e "⚪ $1" ;;
    esac
}

#######################################
# SUMMARY VIEW
#######################################
print_header "GATEKEEPER VIOLATIONS SUMMARY"

echo ""
echo "Constraint                              | Violations | Severity"
echo "----------------------------------------|------------|----------"

kubectl get constraints -o json 2>/dev/null | jq -r '
.items[] | 
select(.status.totalViolations != null) |
[
  .metadata.name,
  (.status.totalViolations | tostring),
  (.metadata.labels["policy-severity"] // "unknown")
] | @tsv
' | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r name count severity; do
    # Pad name to 40 chars
    printf "%-40s| %-10s | " "$name" "$count"
    print_severity "$severity"
done

# Total violations
TOTAL=$(kubectl get constraints -o json 2>/dev/null | jq '[.items[].status.totalViolations // 0] | add')
echo ""
echo -e "----------------------------------------|------------|----------"
echo -e "${YELLOW}TOTAL VIOLATIONS: $TOTAL${NC}"

#######################################
# BY NAMESPACE
#######################################
print_header "VIOLATIONS BY NAMESPACE"

kubectl get constraints -o json 2>/dev/null | jq -r '
[.items[] | .status.violations[]? | .namespace // "cluster-scoped"] | 
group_by(.) | 
map({namespace: .[0], count: length}) | 
sort_by(.count) | reverse | .[:15][] |
"\(.count)\t\(.namespace)"
' | while IFS=$'\t' read -r count ns; do
    printf "  %-30s %s violations\n" "$ns" "$count"
done

#######################################
# BY CATEGORY
#######################################
print_header "VIOLATIONS BY CATEGORY"

kubectl get constraints -o json 2>/dev/null | jq -r '
[.items[] | {category: (.metadata.labels["policy-category"] // "unknown"), violations: (.status.totalViolations // 0)}] |
group_by(.category) |
map({category: .[0].category, total: (map(.violations) | add)}) |
sort_by(.total) | reverse | .[] |
"\(.total)\t\(.category)"
' | while IFS=$'\t' read -r count category; do
    printf "  %-25s %s violations\n" "$category" "$count"
done

#######################################
# DETAILED VIEW (unless --summary)
#######################################
if [[ "$SUMMARY_ONLY" != true ]]; then
    print_header "DETAILED VIOLATIONS"
    
    # Get constraints with violations
    kubectl get constraints -o json 2>/dev/null | jq -r '
    .items[] | 
    select(.status.totalViolations > 0) | 
    .metadata.name
    ' | while read -r constraint; do
        echo ""
        echo -e "${YELLOW}▶ $constraint${NC}"
        
        kubectl get constraints "$constraint" -o json 2>/dev/null | jq -r '
        .status.violations[:10][] |
        "  - \(.namespace // "cluster")/\(.kind)/\(.name)\n    → \(.message)"
        '
        
        # Show if more violations exist
        TOTAL_FOR_CONSTRAINT=$(kubectl get constraints "$constraint" -o json 2>/dev/null | jq '.status.totalViolations')
        if [[ $TOTAL_FOR_CONSTRAINT -gt 10 ]]; then
            echo -e "  ${BLUE}... and $((TOTAL_FOR_CONSTRAINT - 10)) more violations${NC}"
        fi
    done
fi

#######################################
# EXPORT TO JSON
#######################################
if [[ "$EXPORT_JSON" == true ]]; then
    EXPORT_FILE="violations-report-$(date +%Y%m%d-%H%M%S).json"
    print_header "EXPORTING TO $EXPORT_FILE"
    
    kubectl get constraints -o json 2>/dev/null | jq '{
        generated: (now | strftime("%Y-%m-%d %H:%M:%S")),
        cluster: "'"$CLUSTER_NAME"'",
        total_violations: [.items[].status.totalViolations // 0] | add,
        by_constraint: [.items[] | select(.status.totalViolations > 0) | {
            name: .metadata.name,
            category: .metadata.labels["policy-category"],
            severity: .metadata.labels["policy-severity"],
            violations: .status.totalViolations,
            details: .status.violations
        }] | sort_by(.violations) | reverse,
        by_namespace: ([.items[] | .status.violations[]? | .namespace // "cluster-scoped"] | group_by(.) | map({namespace: .[0], count: length}) | sort_by(.count) | reverse)
    }' > "$EXPORT_FILE"
    
    echo -e "${GREEN}Exported to: $EXPORT_FILE${NC}"
fi

#######################################
# QUICK ACTIONS
#######################################
print_header "QUICK ACTIONS"

echo ""
echo "To see all violations for a specific constraint:"
echo -e "  ${GREEN}kubectl get constraints <constraint-name> -o yaml | grep -A 100 violations${NC}"
echo ""
echo "To see violations for a specific namespace:"
echo -e "  ${GREEN}kubectl get constraints -o json | jq '.items[].status.violations[] | select(.namespace==\"<ns>\")' ${NC}"
echo ""
echo "To trigger a full audit:"
echo -e "  ${GREEN}kubectl annotate constraint --all gatekeeper.sh/audit-timestamp=\$(date +%s) --overwrite${NC}"
echo ""
echo "To see constraint templates:"
echo -e "  ${GREEN}kubectl get constrainttemplates${NC}"
echo ""

#######################################
# EXIT STATUS
#######################################
if [[ $TOTAL -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found $TOTAL total violations${NC}"
    exit 0  # Still exit 0 since warn mode doesn't block
else
    echo -e "${GREEN}✅ No violations found${NC}"
    exit 0
fi

