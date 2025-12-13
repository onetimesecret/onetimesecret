#!/usr/bin/env python3
"""
Step 1: Identify keys that were renamed (dash <-> underscore changes).
Generates a mapping file for human review before applying fixes.
"""
import json
import sys
from pathlib import Path

def get_all_keys(obj, prefix=''):
    """Recursively get all key paths from nested dict."""
    keys = set()
    if isinstance(obj, dict):
        for key, value in obj.items():
            new_prefix = f"{prefix}.{key}" if prefix else key
            keys.add(new_prefix)
            if isinstance(value, dict):
                keys.update(get_all_keys(value, new_prefix))
    return keys

def normalize_key(key):
    """Normalize key for comparison (remove dashes and underscores)."""
    return key.replace('-', '').replace('_', '')

def find_renamed_keys(source_file, target_file):
    """Find keys that exist in both files but with different naming."""

    with open(source_file) as f:
        source_data = json.load(f)

    with open(target_file) as f:
        target_data = json.load(f)

    source_keys = get_all_keys(source_data)
    target_keys = get_all_keys(target_data)

    # Build normalized lookup
    source_normalized = {normalize_key(k): k for k in source_keys}
    target_normalized = {normalize_key(k): k for k in target_keys}

    renames = []

    for norm_key, source_key in source_normalized.items():
        if norm_key in target_normalized:
            target_key = target_normalized[norm_key]
            if source_key != target_key:
                renames.append({
                    'from': target_key,
                    'to': source_key
                })

    return renames

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: find-renamed-keys.py <source.json> <target.json>")
        print("  Generates key-renames.json mapping file")
        sys.exit(1)

    source = sys.argv[1]
    target = sys.argv[2]

    renames = find_renamed_keys(source, target)

    if not renames:
        print("No renamed keys found!")
        sys.exit(0)

    output_file = 'key-renames.json'
    with open(output_file, 'w') as f:
        json.dump(renames, f, indent=2)

    print(f"Found {len(renames)} renamed keys:")
    for r in renames:
        print(f"  {r['from']} → {r['to']}")

    print(f"\nMapping saved to: {output_file}")
    print("Review this file, then run: apply-key-renames.py")
