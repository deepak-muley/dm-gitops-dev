#!/usr/bin/env python3
"""
Extract CVEs from Kubescape Operator CRDs (VulnerabilityManifestSummary and VulnerabilityManifest).

This script queries Kubernetes API to get vulnerability scan results from Kubescape operator
and extracts CVEs matching the specified severity and namespace filters.
"""

import json
import sys
import subprocess
import argparse
import tempfile
import os


def run_kubectl_command(cmd):
    """Run kubectl command and return JSON output."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError, ValueError):
        return None


def get_vulnerability_manifest_summary_names(namespace_filter=None):
    """Get list of VulnerabilityManifestSummary resource names, optionally filtered by namespace."""
    if namespace_filter:
        # Query specific namespaces
        all_names = []
        for ns in namespace_filter.split(','):
            cmd = f"kubectl get vulnerabilitymanifestsummary -n {ns} --no-headers -o custom-columns=NAME:.metadata.name"
            try:
                result = subprocess.run(
                    cmd,
                    shell=True,
                    capture_output=True,
                    text=True,
                    check=False
                )
                if result.returncode == 0:
                    names = [n.strip() for n in result.stdout.strip().split('\n') if n.strip()]
                    all_names.extend([(ns, name) for name in names])
            except:
                pass
        return all_names
    else:
        # Query all namespaces
        cmd = "kubectl get vulnerabilitymanifestsummary -A --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name"
        try:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                check=False
            )
            if result.returncode == 0:
                names = []
                for line in result.stdout.strip().split('\n'):
                    if line.strip():
                        parts = line.strip().split()
                        if len(parts) >= 2:
                            names.append((parts[0], parts[1]))
                return names
        except:
            pass
        return []


def get_vulnerability_manifest_summary(vms_name, namespace):
    """Get a single VulnerabilityManifestSummary resource."""
    cmd = f"kubectl get vulnerabilitymanifestsummary {vms_name} -n {namespace} -o json"
    return run_kubectl_command(cmd)


def get_vulnerability_manifest(vm_name):
    """Get a VulnerabilityManifest resource from the kubescape namespace."""
    cmd = f"kubectl get vulnerabilitymanifest {vm_name} -n kubescape -o json"
    return run_kubectl_command(cmd)


def extract_cves_from_manifest(vm_json, severity_filter, namespace_val):
    """Extract CVEs from a VulnerabilityManifest JSON object."""
    if not vm_json:
        return []

    matches = vm_json.get('spec', {}).get('payload', {}).get('matches', [])
    if not matches:
        return []

    cve_list = []
    seen_cves = set()

    for match in matches:
        vuln = match.get('vulnerability')
        if not vuln:
            continue

        # Filter by severity
        severity = vuln.get('severity', 'unknown').lower()
        if severity_filter != 'all' and severity_filter not in severity:
            continue

        cve_id = vuln.get('id')
        if not cve_id or cve_id in seen_cves:
            continue
        seen_cves.add(cve_id)

        artifact = match.get('artifact', {})
        fix_versions = vuln.get('fix', {}).get('versions', [])

        cve_list.append({
            'cve': cve_id,
            'severity': vuln.get('severity', 'unknown'),
            'description': vuln.get('description', ''),
            'component': artifact.get('name', ''),
            'namespace': namespace_val,
            'image': artifact.get('name', ''),
            'fixedVersion': fix_versions[0] if fix_versions else ''
        })

    return cve_list


def main():
    parser = argparse.ArgumentParser(description='Extract CVEs from Kubescape Operator CRDs')
    parser.add_argument('--severity', required=True, help='Severity filter (all, critical, high, medium, low)')
    parser.add_argument('--namespace', help='Comma-separated list of namespaces to filter')
    parser.add_argument('--kubeconfig', help='Path to kubeconfig file')

    args = parser.parse_args()

    # Set kubeconfig if provided
    if args.kubeconfig:
        os.environ['KUBECONFIG'] = args.kubeconfig

    severity_filter = args.severity.lower()
    namespace_filter = args.namespace

    # Get list of VulnerabilityManifestSummary resource names
    vms_names = get_vulnerability_manifest_summary_names(namespace_filter)

    if not vms_names:
        print("DEBUG: No VMS names found", file=sys.stderr)
        print(json.dumps([]))
        return

    all_cves = []
    seen_cve_ids = set()

    # Process each VulnerabilityManifestSummary individually
    processed = 0
    skipped_no_vm = 0
    skipped_ns_filter = 0
    skipped_no_manifest = 0

    for namespace, vms_name in vms_names:
        # Get the individual VMS item
        vms_item = get_vulnerability_manifest_summary(vms_name, namespace)
        if not vms_item:
            continue
        # Get the vulnerability manifest name
        vulnerabilities_ref = vms_item.get('spec', {}).get('vulnerabilitiesRef', {})
        vm_name = None

        # Try 'all' first, then 'relevant'
        if vulnerabilities_ref.get('all', {}).get('name'):
            vm_name = vulnerabilities_ref['all']['name']
        elif vulnerabilities_ref.get('relevant', {}).get('name'):
            vm_name = vulnerabilities_ref['relevant']['name']

        if not vm_name:
            skipped_no_vm += 1
            continue

        # Get the workload namespace from labels or metadata
        workload_ns = (
            vms_item.get('metadata', {}).get('labels', {}).get('kubescape.io/workload-namespace') or
            vms_item.get('metadata', {}).get('namespace')
        )

        # Apply namespace filter if specified
        if namespace_filter:
            ns_list = [ns.strip() for ns in namespace_filter.split(',')]
            if workload_ns not in ns_list:
                skipped_ns_filter += 1
                continue

        # Get the VulnerabilityManifest (always from kubescape namespace)
        vm_json = get_vulnerability_manifest(vm_name)
        if not vm_json:
            skipped_no_manifest += 1
            continue

        # Extract CVEs from the manifest
        cves = extract_cves_from_manifest(vm_json, severity_filter, workload_ns)

        if cves:
            processed += 1

        # Add unique CVEs to the list
        for cve in cves:
            cve_id = cve.get('cve')
            if cve_id and cve_id not in seen_cve_ids:
                seen_cve_ids.add(cve_id)
                all_cves.append(cve)

    # Output as JSON
    print(json.dumps(all_cves, indent=2))


if __name__ == '__main__':
    main()

