#!/bin/bash
#
# Script to list all ClusterApp and App CRs from the management cluster
# grouped by type with display name and scope information.
#
# Usage:
#   export KUBECONFIG=/path/to/kubeconfig
#   ./scripts/list-clusterapps-and-apps.sh [OPTIONS]
#
# Options:
#   --kind KIND          Filter by kind (ClusterApp or App)
#   --scope SCOPE        Filter by scope (workspace or project)
#   --name PATTERN       Filter by name (partial match)
#   --namespace NS       Filter by namespace (for App resources)
#   --type TYPE          Filter by type (custom, internal, nkp-catalog, nkp-core-platform)
#   --licensing PATTERN  Filter by licensing (partial match, e.g., "pro", "ultimate")
#   --dependencies PATTERN Filter by dependencies (partial match, e.g., "cert-manager")
#   --check-deployments  Show AppDeployment status and cluster deployment info
#   --generate-block-diagram  Generate block diagram of ClusterApp dependencies
#   --no-color           Disable colored output
#   --summary            Show only summary statistics
#   -h, --help           Show this help message
#
# Requirements:
#   - kubectl
#   - jq
#   - KUBECONFIG environment variable set to management cluster kubeconfig
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
FILTER_KIND=""
FILTER_SCOPE=""
FILTER_NAME=""
FILTER_NAMESPACE=""
FILTER_TYPE=""
FILTER_LICENSING=""
FILTER_DEPENDENCIES=""
CHECK_DEPLOYMENTS=false
GENERATE_BLOCK_DIAGRAM=false
NO_COLOR=false
SUMMARY_ONLY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --kind)
      FILTER_KIND="$2"
      shift 2
      ;;
    --scope)
      FILTER_SCOPE="$2"
      shift 2
      ;;
    --name)
      FILTER_NAME="$2"
      shift 2
      ;;
    --namespace)
      FILTER_NAMESPACE="$2"
      shift 2
      ;;
    --type)
      FILTER_TYPE="$2"
      shift 2
      ;;
    --licensing)
      FILTER_LICENSING="$2"
      shift 2
      ;;
    --dependencies)
      FILTER_DEPENDENCIES="$2"
      shift 2
      ;;
    --check-deployments)
      CHECK_DEPLOYMENTS=true
      shift
      ;;
    --generate-block-diagram)
      GENERATE_BLOCK_DIAGRAM=true
      shift
      ;;
    --no-color)
      NO_COLOR=true
      shift
      ;;
    --summary)
      SUMMARY_ONLY=true
      shift
      ;;
    -h|--help)
      cat << EOF
List ClusterApp and App CRs from the management cluster.

Usage:
  $0 [OPTIONS]

Options:
  --kind KIND          Filter by kind (ClusterApp or App)
  --scope SCOPE        Filter by scope (workspace or project)
  --name PATTERN       Filter by name (partial match, case-insensitive)
  --namespace NS        Filter by namespace (for App resources)
  --type TYPE          Filter by type (custom, internal, nkp-catalog, nkp-core-platform)
  --licensing PATTERN  Filter by licensing (partial match, e.g., "pro", "ultimate")
  --dependencies PATTERN Filter by dependencies (partial match, e.g., "cert-manager")
  --check-deployments  Show AppDeployment status and cluster deployment info
  --generate-block-diagram  Generate block diagram of ClusterApp dependencies
  --no-color           Disable colored output
  --summary            Show only summary statistics
  -h, --help           Show this help message

Examples:
  # List all resources
  $0

  # List only ClusterApps
  $0 --kind ClusterApp

  # List workspace-scoped apps
  $0 --scope workspace

  # Search by name
  $0 --name insights

  # Filter by namespace
  $0 --namespace kommander-default-workspace

  # Filter by licensing
  $0 --licensing ultimate

  # Filter by dependencies
  $0 --dependencies cert-manager

  # Combine filters
  $0 --kind App --scope workspace --name kserve --licensing pro

  # Check deployment status
  $0 --check-deployments --name cert-manager
  $0 --check-deployments --kind ClusterApp

  # Generate block diagram
  $0 --generate-block-diagram
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Disable colors if requested
if [ "$NO_COLOR" = true ]; then
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  BOLD=""
  NC=""
fi

# Function to print colored text
print_color() {
  local color=$1
  shift
  echo -e "${color}$@${NC}"
}

# Function to print section header
print_section() {
  local title=$1
  echo ""
  print_color "${BOLD}${CYAN}" "════════════════════════════════════════════════════════════════"
  print_color "${BOLD}${CYAN}" "  $title"
  print_color "${BOLD}${CYAN}" "════════════════════════════════════════════════════════════════"
  echo ""
}

# Function to print table header
print_header() {
  print_color "${BOLD}" "┌─────────────┬──────────────────────────────────────────┬─────────────┬──────────────────────────────────────┬────────────┬──────────────────────────────┬──────────────────────────────────────┬──────────────────────────────────────┐"
  printf "${BOLD}│ %-11s │ %-40s │ %-11s │ %-36s │ %-10s │ %-28s │ %-36s │ %-36s │${NC}\n" "Kind" "Name" "Version" "Display Name" "Scope" "Type" "Licensing" "Dependencies"
  print_color "${BOLD}" "├─────────────┼──────────────────────────────────────────┼─────────────┼──────────────────────────────────────┼────────────┼──────────────────────────────┼──────────────────────────────────────┼──────────────────────────────────────┤"
}

# Function to print table row
print_row() {
  local kind=$1
  local name=$2
  local version=$3
  local display_name=$4
  local scope=$5
  local type=$6
  local licensing=$7
  local dependencies=$8

  # Color code by kind
  local kind_color=""
  if [ "$kind" = "ClusterApp" ]; then
    kind_color="${BLUE}"
  else
    kind_color="${GREEN}"
  fi

  # Color code by scope
  local scope_color=""
  if [ "$scope" = "workspace" ]; then
    scope_color="${YELLOW}"
  elif [ "$scope" = "project" ]; then
    scope_color="${MAGENTA}"
  else
    scope_color="${NC}"
  fi

  # Color code by type
  local type_color=""
  case "$type" in
    "nkp-core-platform")
      type_color="${CYAN}"
      ;;
    "nkp-catalog")
      type_color="${GREEN}"
      ;;
    "custom")
      type_color="${YELLOW}"
      ;;
    "internal")
      type_color="${MAGENTA}"
      ;;
    *)
      type_color="${NC}"
      ;;
  esac

  # Truncate long values
  type=$(echo "$type" | cut -c1-28)
  licensing=$(echo "$licensing" | cut -c1-36)
  dependencies=$(echo "$dependencies" | cut -c1-36)

  printf "│ ${kind_color}%-11s${NC} │ %-40s │ %-11s │ %-36s │ ${scope_color}%-10s${NC} │ ${type_color}%-28s${NC} │ %-36s │ %-36s │\n" \
    "$kind" "$name" "$version" "$display_name" "$scope" "$type" "$licensing" "$dependencies"
}

# Function to print table footer
print_footer() {
  print_color "${BOLD}" "└─────────────┴──────────────────────────────────────────┴─────────────┴──────────────────────────────────────┴────────────┴──────────────────────────────┴──────────────────────────────────────┴──────────────────────────────────────┘"
}

# Function to get deployment status for a ClusterApp/App
get_deployment_status() {
  local kind=$1
  local name=$2
  local namespace=$3

  # Find AppDeployment that references this ClusterApp/App
  local app_deployment=""
  if [ "$kind" = "ClusterApp" ]; then
    app_deployment=$(kubectl get appdeployment -A -o json 2>/dev/null | \
      jq -r --arg NAME "$name" --arg KIND "$kind" \
      '.items[] | select(.spec.appRef.kind == $KIND and .spec.appRef.name == $NAME) |
      "\(.metadata.namespace)|\(.metadata.name)"' 2>/dev/null | head -1)
  else
    # For App, match by name and namespace
    app_deployment=$(kubectl get appdeployment -A -o json 2>/dev/null | \
      jq -r --arg NAME "$name" --arg KIND "$kind" --arg NS "$namespace" \
      '.items[] | select(.spec.appRef.kind == $KIND and .spec.appRef.name == $NAME and .metadata.namespace == $NS) |
      "\(.metadata.namespace)|\(.metadata.name)"' 2>/dev/null | head -1)
  fi

  if [ -z "$app_deployment" ]; then
    echo "Not Enabled|N/A|N/A"
    return 0
  fi

  local ad_namespace=$(echo "$app_deployment" | cut -d'|' -f1)
  local ad_name=$(echo "$app_deployment" | cut -d'|' -f2)

  # Get clusters from AppDeployment
  local clusters=$(kubectl get appdeployment "$ad_name" -n "$ad_namespace" -o json 2>/dev/null | \
    jq -r '.spec.clusterConfigOverrides[]?.clusterSelector.matchExpressions[]?.values[]? // .spec.clusterSelector.matchExpressions[]?.values[]? // empty' 2>/dev/null | \
    sort -u | tr '\n' ',' | sed 's/,$//' || echo "N/A")

  if [ -z "$clusters" ] || [ "$clusters" = "N/A" ]; then
    # Try alternative method
    clusters=$(kubectl get appdeployment "$ad_name" -n "$ad_namespace" -o json 2>/dev/null | \
      jq -r '.spec.clusterSelector.matchLabels."kommander.d2iq.io/cluster-name" // empty' 2>/dev/null || echo "N/A")
  fi

  # Get AppDeploymentInstance status
  local instances=$(kubectl get appdeploymentinstance -n "$ad_namespace" -o json 2>/dev/null | \
    jq -r --arg AD_NAME "$ad_name" \
    '.items[] | select(.metadata.ownerReferences[]?.name == $AD_NAME) |
    "\(.metadata.labels."apps.kommander.nutanix.com/kommander-cluster" // "unknown")|\(.status.conditions[]? | select(.type == "KustomizationReady") | .status // "Unknown")|\(.status.conditions[]? | select(.type == "KustomizationHealthy") | .status // "Unknown")"' 2>/dev/null)

  if [ -z "$instances" ]; then
    echo "Enabled|${clusters}|No Instances"
    return 0
  fi

  # Format instance status
  local healthy_count=0
  local total_count=0
  local instance_details=""

  while IFS='|' read -r cluster ready healthy; do
    if [ -z "$cluster" ] || [ "$cluster" = "unknown" ]; then
      continue
    fi
    total_count=$((total_count + 1))
    if [ "$ready" = "True" ] && [ "$healthy" = "True" ]; then
      healthy_count=$((healthy_count + 1))
      if [ "$NO_COLOR" = false ]; then
        instance_details="${instance_details}${GREEN}✓${NC} ${cluster} "
      else
        instance_details="${instance_details}✓ ${cluster} "
      fi
    else
      if [ "$NO_COLOR" = false ]; then
        instance_details="${instance_details}${YELLOW}○${NC} ${cluster} "
      else
        instance_details="${instance_details}○ ${cluster} "
      fi
    fi
  done <<< "$instances"

  # Remove trailing space
  instance_details=$(echo "$instance_details" | sed 's/ $//')

  if [ "$total_count" -eq 0 ]; then
    echo "Enabled|${clusters}|No Instances|"
  else
    local status_text="${healthy_count}/${total_count} Healthy"
    echo "Enabled|${clusters}|${status_text}|${instance_details}"
  fi
}

# Function to process and print resources by type
process_by_type() {
  local type=$1
  local kind=$2
  local count_file=$3
  local count=0

  # Build jq filter
  local jq_filter=".items[] | select((.metadata.annotations.\"apps.kommander.d2iq.io/type\" // .metadata.labels.\"apps.kommander.d2iq.io/type\" // \"N/A\") == \"$type\")"

  # Apply kind filter
  if [ "$kind" = "ClusterApp" ]; then
    jq_filter="$jq_filter | select(.kind == \"ClusterApp\")"
  else
    jq_filter="$jq_filter | select(.kind == \"App\")"
  fi

  # Apply scope filter
  if [ -n "$FILTER_SCOPE" ]; then
    jq_filter="$jq_filter | select((.metadata.annotations.\"apps.kommander.d2iq.io/scope\" // \"N/A\") == \"$FILTER_SCOPE\")"
  fi

  # Apply name filter
  if [ -n "$FILTER_NAME" ]; then
    jq_filter="$jq_filter | select((.metadata.name | ascii_downcase) | contains(\"$FILTER_NAME\" | ascii_downcase))"
  fi

  # Apply namespace filter (only for App resources)
  if [ -n "$FILTER_NAMESPACE" ] && [ "$kind" = "App" ]; then
    jq_filter="$jq_filter | select(.metadata.namespace == \"$FILTER_NAMESPACE\")"
  fi

  # Apply licensing filter
  if [ -n "$FILTER_LICENSING" ]; then
    jq_filter="$jq_filter | select((.metadata.annotations.\"apps.kommander.d2iq.io/licensing\" // \"\") | ascii_downcase | contains(\"$FILTER_LICENSING\" | ascii_downcase))"
  fi

  # Apply dependencies filter
  if [ -n "$FILTER_DEPENDENCIES" ]; then
    jq_filter="$jq_filter | select((.metadata.annotations.\"apps.kommander.d2iq.io/dependencies\" // .metadata.annotations.\"apps.kommander.d2iq.io/required-dependencies\" // \"\") | ascii_downcase | contains(\"$FILTER_DEPENDENCIES\" | ascii_downcase))"
  fi

  # Get resources
  local resources=""
  if [ "$kind" = "ClusterApp" ]; then
    resources=$(kubectl get clusterapps -A -o json 2>/dev/null | jq -r "$jq_filter | \"\(.kind)|\(.metadata.name)|\(.spec.version)|\(.metadata.annotations.\"apps.kommander.d2iq.io/display-name\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/scope\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/type\" // .metadata.labels.\"apps.kommander.d2iq.io/type\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/licensing\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/dependencies\" // .metadata.annotations.\"apps.kommander.d2iq.io/required-dependencies\" // \"N/A\")\"" 2>/dev/null || true)
  else
    resources=$(kubectl get apps -A -o json 2>/dev/null | jq -r "$jq_filter | \"\(.kind)|\(.metadata.name)|\(.spec.version)|\(.metadata.annotations.\"apps.kommander.d2iq.io/display-name\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/scope\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/type\" // .metadata.labels.\"apps.kommander.d2iq.io/type\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/licensing\" // \"N/A\")|\(.metadata.annotations.\"apps.kommander.d2iq.io/dependencies\" // .metadata.annotations.\"apps.kommander.d2iq.io/required-dependencies\" // \"N/A\")|\(.metadata.namespace)\"" 2>/dev/null || true)
  fi

  if [ -z "$resources" ]; then
    echo "0" > "$count_file"
    return 0
  fi

  # Count resources (remove empty lines)
  count=$(echo "$resources" | grep -v '^$' | wc -l | tr -d ' ')

  if [ "$count" -eq 0 ] || [ -z "$count" ]; then
    echo "0" > "$count_file"
    return 0
  fi

  # Write count to file
  echo "$count" > "$count_file"

  if [ "$SUMMARY_ONLY" = false ]; then
    print_section "Type: ${BOLD}${type}${NC} | Kind: ${BOLD}${kind}${NC} | Count: ${BOLD}${count}${NC}"
    print_header

    echo "$resources" | grep -v '^$' | sort -t'|' -u -k5,5 -k2,2 | while IFS='|' read -r line; do
      # Parse the line - App resources have namespace at the end, ClusterApp don't
      if [ "$kind" = "App" ]; then
        IFS='|' read -r k n v d s t l dep ns <<< "$line"
      else
        IFS='|' read -r k n v d s t l dep <<< "$line"
        ns=""  # ClusterApp doesn't have namespace in the output
      fi
      print_row "$k" "$n" "$v" "$d" "$s" "$t" "$l" "$dep"

      # Show deployment status if requested
      if [ "$CHECK_DEPLOYMENTS" = true ]; then
        local deployment_status=$(get_deployment_status "$k" "$n" "$ns")
        local enabled=$(echo "$deployment_status" | cut -d'|' -f1)
        local clusters=$(echo "$deployment_status" | cut -d'|' -f2)
        local status=$(echo "$deployment_status" | cut -d'|' -f3)
        local instance_details=$(echo "$deployment_status" | cut -d'|' -f4)

        if [ "$enabled" = "Enabled" ]; then
          if [ "$NO_COLOR" = false ]; then
            if [ -n "$instance_details" ] && [ "$instance_details" != "N/A" ]; then
              printf "  ${GREEN}✓${NC} Enabled on clusters: ${CYAN}%s${NC} | Status: %s\n" "$clusters" "$status"
              printf "    Instances: %b\n" "$instance_details"
            else
              printf "  ${GREEN}✓${NC} Enabled on clusters: ${CYAN}%s${NC} | Status: %s\n" "$clusters" "$status"
            fi
          else
            if [ -n "$instance_details" ] && [ "$instance_details" != "N/A" ]; then
              printf "  ✓ Enabled on clusters: %s | Status: %s\n" "$clusters" "$status"
              printf "    Instances: %s\n" "$instance_details"
            else
              printf "  ✓ Enabled on clusters: %s | Status: %s\n" "$clusters" "$status"
            fi
          fi
        else
          if [ "$NO_COLOR" = false ]; then
            printf "  ${YELLOW}○${NC} Not enabled\n"
          else
            printf "  ○ Not enabled\n"
          fi
        fi
      fi
    done

    print_footer
  fi
}

# Check if KUBECONFIG is set
if [ -z "${KUBECONFIG:-}" ]; then
  print_color "${RED}" "Error: KUBECONFIG environment variable is not set"
  echo "Please set it to your management cluster kubeconfig:"
  echo "  export KUBECONFIG=/path/to/kubeconfig"
  exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  print_color "${RED}" "Error: kubectl is not installed or not in PATH"
  exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  print_color "${RED}" "Error: jq is not installed or not in PATH"
  exit 1
fi

# Print header
print_section "ClusterApp and App Resources"

# Show active filters
if [ -n "$FILTER_KIND" ] || [ -n "$FILTER_SCOPE" ] || [ -n "$FILTER_NAME" ] || [ -n "$FILTER_NAMESPACE" ] || [ -n "$FILTER_TYPE" ] || [ -n "$FILTER_LICENSING" ] || [ -n "$FILTER_DEPENDENCIES" ]; then
  print_color "${YELLOW}" "Active Filters:"
  [ -n "$FILTER_KIND" ] && print_color "${YELLOW}" "  Kind: $FILTER_KIND"
  [ -n "$FILTER_SCOPE" ] && print_color "${YELLOW}" "  Scope: $FILTER_SCOPE"
  [ -n "$FILTER_NAME" ] && print_color "${YELLOW}" "  Name: $FILTER_NAME"
  [ -n "$FILTER_NAMESPACE" ] && print_color "${YELLOW}" "  Namespace: $FILTER_NAMESPACE"
  [ -n "$FILTER_TYPE" ] && print_color "${YELLOW}" "  Type: $FILTER_TYPE"
  [ -n "$FILTER_LICENSING" ] && print_color "${YELLOW}" "  Licensing: $FILTER_LICENSING"
  [ -n "$FILTER_DEPENDENCIES" ] && print_color "${YELLOW}" "  Dependencies: $FILTER_DEPENDENCIES"
  echo ""
fi

# Get all unique types
TYPES=$(kubectl get clusterapps,apps -A -o json 2>/dev/null | jq -r '.items[] | .metadata.annotations."apps.kommander.d2iq.io/type" // .metadata.labels."apps.kommander.d2iq.io/type" // "N/A"' | sort -u)

if [ -z "$TYPES" ]; then
  print_color "${YELLOW}" "No ClusterApp or App resources found in the cluster"
  exit 0
fi

# Apply type filter
if [ -n "$FILTER_TYPE" ]; then
  TYPES=$(echo "$TYPES" | grep -i "$FILTER_TYPE" || true)
  if [ -z "$TYPES" ]; then
    print_color "${YELLOW}" "No resources found matching type: $FILTER_TYPE"
    exit 0
  fi
fi

# Process each type
TOTAL_COUNT=0
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Initialize count files
touch "$TEMP_DIR/types.txt"
touch "$TEMP_DIR/kinds.txt"
touch "$TEMP_DIR/scopes.txt"

for type in $TYPES; do
  # Determine which kinds to process
  KINDS_TO_PROCESS=""

  if [ -z "$FILTER_KIND" ] || [ "$FILTER_KIND" = "ClusterApp" ]; then
    CLUSTERAPPS=$(kubectl get clusterapps -A -o json 2>/dev/null | jq -r --arg TYPE "$type" '.items[] |
      select((.metadata.annotations."apps.kommander.d2iq.io/type" // .metadata.labels."apps.kommander.d2iq.io/type" // "N/A") == $TYPE) | .kind' | head -1)
    if [ -n "$CLUSTERAPPS" ]; then
      KINDS_TO_PROCESS="${KINDS_TO_PROCESS}ClusterApp "
    fi
  fi

  if [ -z "$FILTER_KIND" ] || [ "$FILTER_KIND" = "App" ]; then
    APPS=$(kubectl get apps -A -o json 2>/dev/null | jq -r --arg TYPE "$type" '.items[] |
      select((.metadata.annotations."apps.kommander.d2iq.io/type" // .metadata.labels."apps.kommander.d2iq.io/type" // "N/A") == $TYPE) | .kind' | head -1)
    if [ -n "$APPS" ]; then
      KINDS_TO_PROCESS="${KINDS_TO_PROCESS}App "
    fi
  fi

  for kind in $KINDS_TO_PROCESS; do
    count_file="$TEMP_DIR/count_${type}_${kind}.txt"
    process_by_type "$type" "$kind" "$count_file"
    count=$(cat "$count_file" 2>/dev/null || echo "0")

    if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
      TOTAL_COUNT=$((TOTAL_COUNT + count))
      # Add type and kind counts
      for i in $(seq 1 $count); do
        echo "$type" >> "$TEMP_DIR/types.txt"
        echo "$kind" >> "$TEMP_DIR/kinds.txt"
      done

      # Count by scope
      if [ "$kind" = "ClusterApp" ]; then
        kubectl get clusterapps -A -o json 2>/dev/null | jq -r --arg TYPE "$type" '.items[] |
          select((.metadata.annotations."apps.kommander.d2iq.io/type" // .metadata.labels."apps.kommander.d2iq.io/type" // "N/A") == $TYPE) |
          .metadata.annotations."apps.kommander.d2iq.io/scope" // "N/A"' 2>/dev/null | \
          while read -r scope; do
            if [ -z "$FILTER_SCOPE" ] || [ "$scope" = "$FILTER_SCOPE" ]; then
              echo "$scope" >> "$TEMP_DIR/scopes.txt"
            fi
          done || true
      else
        kubectl get apps -A -o json 2>/dev/null | jq -r --arg TYPE "$type" '.items[] |
          select((.metadata.annotations."apps.kommander.d2iq.io/type" // .metadata.labels."apps.kommander.d2iq.io/type" // "N/A") == $TYPE) |
          .metadata.annotations."apps.kommander.d2iq.io/scope" // "N/A"' 2>/dev/null | \
          while read -r scope; do
            if [ -z "$FILTER_SCOPE" ] || [ "$scope" = "$FILTER_SCOPE" ]; then
              echo "$scope" >> "$TEMP_DIR/scopes.txt"
            fi
          done || true
      fi
    fi
  done
done

# Print summary
echo ""
print_section "Summary Statistics"

print_color "${BOLD}" "Total Resources: ${GREEN}${TOTAL_COUNT}${NC}"
echo ""

# Count by type
if [ -s "$TEMP_DIR/types.txt" ]; then
  print_color "${BOLD}${CYAN}" "By Type:"
  sort "$TEMP_DIR/types.txt" | uniq -c | sort -rn | while read -r count type; do
    printf "  ${YELLOW}%-20s${NC}: ${GREEN}%3d${NC}\n" "$type" "$count"
  done
  echo ""
fi

# Count by kind
if [ -s "$TEMP_DIR/kinds.txt" ]; then
  print_color "${BOLD}${CYAN}" "By Kind:"
  sort "$TEMP_DIR/kinds.txt" | uniq -c | sort -rn | while read -r count kind; do
    printf "  ${BLUE}%-20s${NC}: ${GREEN}%3d${NC}\n" "$kind" "$count"
  done
  echo ""
fi

# Count by scope
if [ -s "$TEMP_DIR/scopes.txt" ]; then
  print_color "${BOLD}${CYAN}" "By Scope:"
  sort "$TEMP_DIR/scopes.txt" | uniq -c | sort -rn | while read -r count scope; do
    printf "  ${MAGENTA}%-20s${NC}: ${GREEN}%3d${NC}\n" "$scope" "$count"
  done
fi

# Generate block diagram if requested
if [ "$GENERATE_BLOCK_DIAGRAM" = true ]; then
  echo ""
  print_color "${BOLD}${CYAN}" "Generating ClusterApp dependency block diagram..."
  echo ""

  # Get script directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PYTHON_SCRIPT="$SCRIPT_DIR/generate-clusterapp-block-diagram.py"

  if [ ! -f "$PYTHON_SCRIPT" ]; then
    print_color "${RED}" "Error: Python script not found at $PYTHON_SCRIPT"
    exit 1
  fi

  # Check if Python 3 is available
  if ! command -v python3 &> /dev/null; then
    print_color "${RED}" "Error: python3 is not installed or not in PATH"
    exit 1
  fi

  # Run the Python script
  python3 "$PYTHON_SCRIPT"

  if [ $? -eq 0 ]; then
    echo ""
    print_color "${GREEN}" "✓ Block diagram generated successfully!"
    print_color "${CYAN}" "  Output: docs/internal/CLUSTERAPP-BLOCK-DIAGRAM.md"
    print_color "${YELLOW}" "  Note: This file is in .gitignore and will not be committed"
  else
    print_color "${RED}" "✗ Failed to generate block diagram"
    exit 1
  fi
fi
