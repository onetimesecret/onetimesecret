#!/usr/bin/env python3
"""
Step 2: Apply key renames from mapping file.
Reads key-renames.json and renames keys in the target file.
"""
import json
import sys

def rename_keys(obj, renames_map):
    """Recursively rename keys in nested dict based on mapping."""
    if not isinstance(obj, dict):
        return obj

    result = {}
    for key, value in obj.items():
        # Check if this key needs renaming
        new_key = renames_map.get(key, key)

        # Recursively process nested objects
        if isinstance(value, dict):
            result[new_key] = rename_keys(value, renames_map)
        else:
            result[new_key] = value

    return result

def apply_renames(target_file, mapping_file, output_file=None):
    """Apply key renames from mapping file to target file."""

    # Load mapping
    with open(mapping_file) as f:
        renames = json.load(f)

    # Build simple key->key mapping (just the final component)
    renames_map = {}
    for r in renames:
        from_key = r['from'].split('.')[-1]
        to_key = r['to'].split('.')[-1]
        renames_map[from_key] = to_key

    # Load target file
    with open(target_file) as f:
        data = json.load(f)

    # Apply renames
    fixed_data = rename_keys(data, renames_map)

    # Write output
    output = output_file or target_file
    with open(output, 'w', encoding='utf-8') as f:
        json.dump(fixed_data, f, ensure_ascii=False, indent=2)

    print(f"Applied {len(renames)} key renames")
    print(f"Updated file: {output}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: apply-key-renames.py <target.json> [output.json]")
        print("  Reads key-renames.json and applies renames")
        print("  output.json: Optional (defaults to overwriting target)")
        sys.exit(1)

    target = sys.argv[1]
    output = sys.argv[2] if len(sys.argv) > 2 else None

    apply_renames(target, 'key-renames.json', output)
