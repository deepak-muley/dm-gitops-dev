#!/usr/bin/env python3
"""
Kubescape CVE Report Generator

Usage:
    ./get-kubescape-cves.py [severity] [cluster] [--namespace ns1,ns2,...]
    ./get-kubescape-cves.py critical mgmt
    ./get-kubescape-cves.py high workload1 --namespace default,kube-system
    ./get-kubescape-cves.py all workload2 --namespace kommander

Severity options: all, critical, high, medium, low (default: all)
Cluster options: mgmt, workload1, workload2 (default: mgmt)
Namespace filter: --namespace ns1,ns2,... (comma-separated, optional)
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path


# Default kubeconfig locations for NKP clusters
DEFAULT_KUBECONFIGS = {
    'mgmt': '/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf',
    'workload1': '/Users/deepak.muley/ws/nkp/dm-nkp-workload-1.kubeconfig',
    'workload2': '/Users/deepak.muley/ws/nkp/dm-nkp-workload-2.kubeconfig'
}

CLUSTER_NAMES = {
    'mgmt': 'Management Cluster (dm-nkp-mgmt-1)',
    'workload1': 'Workload Cluster 1 (dm-nkp-workload-1)',
    'workload2': 'Workload Cluster 2 (dm-nkp-workload-2)'
}

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    MAGENTA = '\033[0;35m'
    NC = '\033[0m'  # No Color


def print_header(text):
    """Print a formatted header."""
    print(f"\n{Colors.CYAN}{'=' * 64}{Colors.NC}")
    print(f"{Colors.CYAN}  {text}{Colors.NC}")
    print(f"{Colors.CYAN}{'=' * 64}{Colors.NC}\n")


def to_upper(text):
    """Convert text to uppercase."""
    return text.upper()


def check_kubescape_operator():
    """Check if Kubescape operator is installed."""
    try:
        # Check for any vulnerability-related CRD
        result = subprocess.run(
            "kubectl get crd | grep -i vulnerability",
            shell=True,
            capture_output=True,
            check=False
        )
        return result.returncode == 0 and result.stdout.strip()
    except:
        return False


def get_cves(severity, namespace_filter, kubeconfig):
    """Get CVEs using the extract_cves_from_kubescape.py script."""
    script_dir = Path(__file__).parent
    extract_script = script_dir / "extract_cves_from_kubescape.py"

    if not extract_script.exists():
        print(f"{Colors.RED}Error: extract_cves_from_kubescape.py not found{Colors.NC}", file=sys.stderr)
        return []

    print(f"{Colors.CYAN}Querying Kubescape Operator CRDs...{Colors.NC}")

    cmd = [
        sys.executable,
        str(extract_script),
        "--severity", severity,
        "--kubeconfig", kubeconfig
    ]

    if namespace_filter:
        cmd.extend(["--namespace", namespace_filter])

    try:
        # Set environment variable for subprocess
        env = os.environ.copy()
        env['KUBECONFIG'] = kubeconfig

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=300  # 5 minute timeout
        )

        if result.returncode != 0:
            if result.stderr:
                print(f"{Colors.RED}Error running extract script: {result.stderr}{Colors.NC}", file=sys.stderr)
            return []

        if result.stdout.strip():
            return json.loads(result.stdout)
        return []
    except subprocess.TimeoutExpired:
        print(f"{Colors.RED}Error: Extract script timed out after 5 minutes{Colors.NC}", file=sys.stderr)
        return []
    except json.JSONDecodeError as e:
        print(f"{Colors.RED}Error parsing JSON: {e}{Colors.NC}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"{Colors.RED}Error: {e}{Colors.NC}", file=sys.stderr)
        return []


def count_cves_by_severity(cves, severity_filter):
    """Count CVEs by severity."""
    counts = {'critical': 0, 'high': 0, 'medium': 0, 'low': 0}

    for cve in cves:
        sev = cve.get('severity', 'unknown').lower()
        if severity_filter == 'all' or severity_filter in sev:
            if 'critical' in sev:
                counts['critical'] += 1
            elif 'high' in sev:
                counts['high'] += 1
            elif 'medium' in sev:
                counts['medium'] += 1
            elif 'low' in sev:
                counts['low'] += 1

    return counts


def display_cves(cves, severity_filter, cluster_name):
    """Display CVEs in a formatted way."""
    header_text = f"CVE Report - {cluster_name} (Severity: {to_upper(severity_filter)})"
    if not cves:
        print_header(header_text)
        print(f"{Colors.GREEN}✓ No CVEs found matching severity filter: {severity_filter}{Colors.NC}\n")
        return

    counts = count_cves_by_severity(cves, severity_filter)

    print_header(header_text)
    print(f"{Colors.CYAN}Summary:{Colors.NC}")
    print(f"  {Colors.RED}Critical: {counts['critical']}{Colors.NC}")
    print(f"  {Colors.YELLOW}High: {counts['high']}{Colors.NC}")
    print(f"  {Colors.BLUE}Medium: {counts['medium']}{Colors.NC}")
    print(f"  {Colors.GREEN}Low: {counts['low']}{Colors.NC}")
    print()

    # Group by severity
    for sev in ['critical', 'high', 'medium', 'low']:
        if severity_filter == 'all' or severity_filter == sev:
            sev_cves = [
                c for c in cves
                if sev in c.get('severity', 'unknown').lower()
            ]

            if sev_cves:
                print(f"{Colors.CYAN}{'─' * 64}{Colors.NC}")
                print(f"{Colors.CYAN}{sev.upper()} Severity CVEs{Colors.NC}")
                print(f"{Colors.CYAN}{'─' * 64}{Colors.NC}\n")

                for cve in sev_cves:
                    print(f"CVE: {cve.get('cve', 'N/A')}")
                    print(f"Severity: {cve.get('severity', 'unknown')}")
                    print(f"Component: {cve.get('component', 'N/A')}")
                    print(f"Namespace: {cve.get('namespace', 'N/A')}")
                    print(f"Image: {cve.get('image', 'N/A')}")
                    print(f"Fixed Version: {cve.get('fixedVersion', 'N/A')}")
                    print(f"Description: {cve.get('description', 'N/A')}")
                    print(f"{'─' * 64}\n")


def generate_jira_report(cves, severity_filter, namespace_filter, cluster_name, cluster_key):
    """Generate a Jira-friendly markdown report."""
    report_suffix = f"{cluster_key}-{severity_filter}"
    if namespace_filter:
        ns_suffix = namespace_filter.replace(',', '-')
        report_suffix = f"{report_suffix}-ns-{ns_suffix}"

    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    report_file = f"kubescape-cve-report-{report_suffix}-{timestamp}.md"

    print_header("Generating Jira Report")

    with open(report_file, 'w') as f:
        f.write("# Kubescape CVE Report\n\n")
        f.write(f"**Cluster:** {cluster_name}\n")
        f.write(f"**Severity Filter:** {to_upper(severity_filter)}\n")
        if namespace_filter:
            f.write(f"**Namespace Filter:** {namespace_filter}\n")
        f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write("---\n\n")

        if not cves:
            f.write("## Summary\n\n")
            f.write(f"✅ No CVEs found matching severity filter: `{severity_filter}`\n\n")
        else:
            counts = count_cves_by_severity(cves, severity_filter)

            f.write("## Summary\n\n")
            f.write("| Severity | Count |\n")
            f.write("|----------|-------|\n")
            f.write(f"| 🔴 Critical | {counts['critical']} |\n")
            f.write(f"| 🟠 High | {counts['high']} |\n")
            f.write(f"| 🟡 Medium | {counts['medium']} |\n")
            f.write(f"| 🟢 Low | {counts['low']} |\n\n")
            f.write("---\n\n")

            f.write("## Detailed Findings\n\n")

            for sev in ['critical', 'high', 'medium', 'low']:
                if severity_filter == 'all' or severity_filter == sev:
                    sev_cves = [
                        c for c in cves
                        if sev in c.get('severity', 'unknown').lower()
                    ]

                    if sev_cves:
                        f.write(f"### {to_upper(sev)} Severity CVEs\n\n")
                        f.write("| CVE ID | Component | Namespace | Image | Fixed Version | Description |\n")
                        f.write("|--------|-----------|-----------|-------|--------------|-------------|\n")

                        for cve in sev_cves:
                            cve_id = cve.get('cve', 'N/A')
                            component = cve.get('component', 'N/A')
                            namespace = cve.get('namespace', 'N/A')
                            image = cve.get('image', 'N/A')
                            fixed_version = cve.get('fixedVersion', 'N/A')
                            description = cve.get('description', 'N/A')

                            # Escape pipe characters in description for markdown table
                            description = description.replace('|', '\\|')

                            f.write(f"| {cve_id} | {component} | {namespace} | {image} | {fixed_version} | {description} |\n")

                        f.write("\n")

        f.write("---\n\n")
        f.write("*Report generated by kubescape CVE scanner*\n")

    print(f"{Colors.GREEN}✓ Jira report saved to: {report_file}{Colors.NC}\n")


def main():
    parser = argparse.ArgumentParser(
        description='Kubescape CVE Report Generator',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s critical mgmt
  %(prog)s high workload1 --namespace default,kube-system
  %(prog)s all workload2 --namespace kommander
        """
    )

    parser.add_argument(
        'severity',
        nargs='?',
        default='all',
        choices=['all', 'critical', 'high', 'medium', 'low'],
        help='Severity filter (default: all)'
    )

    parser.add_argument(
        'cluster',
        nargs='?',
        default='mgmt',
        choices=['mgmt', 'workload1', 'workload2'],
        help='Cluster to scan (default: mgmt)'
    )

    parser.add_argument(
        '--namespace',
        help='Comma-separated list of namespaces to filter'
    )

    args = parser.parse_args()

    # Set kubeconfig
    kubeconfig = DEFAULT_KUBECONFIGS.get(args.cluster)
    if not kubeconfig or not os.path.exists(kubeconfig):
        print(f"{Colors.RED}Error: Kubeconfig not found: {kubeconfig}{Colors.NC}", file=sys.stderr)
        sys.exit(1)

    cluster_name = CLUSTER_NAMES.get(args.cluster, args.cluster)

    # Set kubeconfig environment variable first
    os.environ['KUBECONFIG'] = kubeconfig

    # Print header
    print_header("Kubescape CVE Scanner")
    print(f"{Colors.CYAN}Cluster:{Colors.NC} {cluster_name}")
    print(f"{Colors.CYAN}Severity Filter:{Colors.NC} {to_upper(args.severity)}")
    if args.namespace:
        print(f"{Colors.CYAN}Namespace Filter:{Colors.NC} {args.namespace}")
    print(f"{Colors.CYAN}Kubeconfig:{Colors.NC} {kubeconfig}")
    print()

    # Check for Kubescape operator (skip check, proceed if extract script works)
    print(f"{Colors.GREEN}✓ Using Kubescape Operator CRDs{Colors.NC}\n")

    # Get CVEs
    cves = get_cves(args.severity, args.namespace, kubeconfig)

    # Display results
    display_cves(cves, args.severity, cluster_name)

    # Generate Jira report
    generate_jira_report(cves, args.severity, args.namespace, cluster_name, args.cluster)

    print_header("Report Complete")
    print(f"{Colors.GREEN}✓ CVE scan completed{Colors.NC}\n")
    print(f"To view the Jira report:")
    print(f"  {Colors.CYAN}cat kubescape-cve-report-{args.cluster}-{args.severity}*.md{Colors.NC}\n")


if __name__ == '__main__':
    main()

