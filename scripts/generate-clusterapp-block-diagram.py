#!/usr/bin/env python3
"""
Create a block diagram showing ClusterApp dependencies.
Each app appears once as a block showing its dependencies (parents) and dependents (children).
Root nodes (no dependencies) start their own chains.

Usage:
    python3 scripts/generate-clusterapp-block-diagram.py

Requirements:
    - kubectl configured with access to management cluster
    - kubeconfig file at: /Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf
    - Output: docs/internal/CLUSTERAPP-BLOCK-DIAGRAM.md (not tracked in git)
"""

import sys
import re
import os
import subprocess
import tempfile
import json
from collections import defaultdict, deque

def get_base_name(app_name):
    """Extract base name from versioned app name."""
    base = re.sub(r'-\d+\.\d+\.\d+.*$', '', app_name)
    return base

def parse_clusterapps(file_path):
    """Parse ClusterApps and their dependencies."""
    apps = {}
    dependents = defaultdict(set)

    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split('|')
            if len(parts) < 2:
                continue

            app_name = parts[0].strip()
            deps_str = parts[1].strip() if len(parts) > 1 else ""

            apps[app_name] = []

            if deps_str and deps_str != "N/A":
                deps = [d.strip() for d in deps_str.split(',') if d.strip()]
                apps[app_name] = deps

                for dep in deps:
                    for existing_app in apps.keys():
                        base_name = get_base_name(existing_app)
                        if base_name == dep or existing_app == dep:
                            dependents[existing_app].add(app_name)
                            break

    dependents = {k: sorted(v) for k, v in dependents.items()}
    return apps, dependents

def find_roots(apps):
    """Find root nodes (apps with no dependencies)."""
    return sorted([app for app, deps in apps.items() if not deps])

def create_block_diagram(apps, dependents):
    """Create a block diagram visualization."""
    lines = []
    lines.append("# ClusterApp Dependency Block Diagram")
    lines.append("")
    lines.append("This diagram shows each ClusterApp once as a block with its dependencies (parents) and dependents (children).")
    lines.append("Root nodes (apps with no dependencies) are shown at the top of each chain.")
    lines.append("")
    lines.append("## Block Diagram")
    lines.append("")
    lines.append("```")
    lines.append("")

    roots = find_roots(apps)
    processed = set()

    def draw_app_block(app_name):
        """Draw a single app block showing parents and children."""
        block_lines = []

        # Get dependencies (parents)
        deps = apps.get(app_name, [])
        is_root = len(deps) == 0

        # Get children (dependents)
        children = dependents.get(app_name, [])

        # Draw parents (dependencies) above
        if deps:
            deps_list = ", ".join([d[:30] for d in deps])
            block_lines.append("    ┌─ Parents (depends on): " + deps_list)
            block_lines.append("    │")
            block_lines.append("    ▼")

        # Draw the app block
        app_display = app_name[:60]
        width = max(len(app_display) + 4, 50)
        if is_root:
            block_lines.append("┌─" + "─" * (width - 4) + "─┐")
            block_lines.append("│ " + app_display + " [ROOT]" + " " * (width - len(app_display) - 8) + "│")
        else:
            block_lines.append("┌─" + "─" * (width - 4) + "─┐")
            block_lines.append("│ " + app_display + " " * (width - len(app_display) - 4) + "│")
        block_lines.append("└─" + "─" * (width - 4) + "─┘")

        # Draw children (dependents) below
        if children:
            block_lines.append("    │")
            block_lines.append("    ▼")
            block_lines.append("    └─ Children (used by):")
            for i, child in enumerate(children):
                child_display = child[:55]
                connector = "      ├─" if i < len(children) - 1 else "      └─"
                block_lines.append(f"{connector} {child_display}")
        else:
            block_lines.append("    └─ (no dependents)")

        return block_lines

    # Draw each root and its chain using BFS
    for root_idx, root in enumerate(roots):
        if root_idx > 0:
            lines.append("")
            lines.append("─" * 80)
            lines.append("")

        lines.append(f"### Root Chain {root_idx + 1}: {root}")
        lines.append("")

        # BFS to process all apps in this root's chain
        queue = deque([root])
        chain_apps = []

        while queue:
            app = queue.popleft()
            if app in processed:
                continue

            chain_apps.append(app)
            processed.add(app)

            # Add children to queue
            children = dependents.get(app, [])
            for child in children:
                if child not in processed and child not in queue:
                    queue.append(child)

        # Draw all apps in the chain
        for app in chain_apps:
            block = draw_app_block(app)
            lines.extend(block)
            lines.append("")

    # Draw remaining apps (orphaned)
    remaining = set(apps.keys()) - processed
    if remaining:
        lines.append("")
        lines.append("─" * 80)
        lines.append("")
        lines.append("### Orphaned Apps (not connected to any root)")
        lines.append("")
        for app in sorted(remaining):
            block = draw_app_block(app)
            lines.extend(block)
            lines.append("")

    lines.append("```")
    lines.append("")

    return "\n".join(lines)

def main():
    # Configuration
    kubeconfig = "/Users/deepak.muley/ws/nkp/dm-nkp-mgmt-1.conf"
    output_dir = "docs/internal"
    output_file = os.path.join(output_dir, "CLUSTERAPP-BLOCK-DIAGRAM.md")
    temp_file = "/tmp/clusterapps-deps.txt"

    # Get script directory to find repo root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    os.chdir(repo_root)

    print(f"Fetching ClusterApps from management cluster...")
    print(f"Kubeconfig: {kubeconfig}")

    # Fetch ClusterApps from cluster
    cmd = [
        "kubectl",
        f"--kubeconfig={kubeconfig}",
        "get", "clusterapps", "-A", "-o", "json"
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )

        # Parse JSON and extract dependencies
        data = json.loads(result.stdout)

        with open(temp_file, 'w') as f:
            for item in data.get('items', []):
                app_name = item['metadata']['name']
                deps = (
                    item['metadata'].get('annotations', {}).get('apps.kommander.d2iq.io/dependencies') or
                    item['metadata'].get('annotations', {}).get('apps.kommander.d2iq.io/required-dependencies') or
                    ""
                )
                f.write(f"{app_name}|{deps}\n")

        print(f"Found ClusterApps, parsing dependencies...")
        apps, dependents = parse_clusterapps(temp_file)

        print(f"Found {len(apps)} ClusterApps")
        print(f"Creating block diagram...")

        diagram = create_block_diagram(apps, dependents)

        # Ensure output directory exists
        os.makedirs(output_dir, exist_ok=True)

        print(f"Writing to {output_file}...")
        with open(output_file, 'w') as f:
            f.write(diagram)

        print(f"Done! Block diagram saved to {output_file}")

        # Cleanup
        if os.path.exists(temp_file):
            os.remove(temp_file)

    except subprocess.CalledProcessError as e:
        print(f"Error fetching ClusterApps: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

