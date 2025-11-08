#!/usr/bin/env python3
import json
from pathlib import Path
from typing import Dict, Any

"""
Locale File Migration Utility

This script transforms existing locale JSON files from a legacy structure to a
standardized hierarchical format based on a template structure. It flattens the
existing structure, migrates keys to new naming conventions, and rebuilds a
properly categorized nested structure.

Usage:
    python migrate-locale.py

Input Files:
    - src/locales/en.json: Source locale file with existing translations
    - nested.json: Template file defining target structure

Output:
    - src/locales/en.new.json: Migrated locale file with preserved values in new structure
    - Console output with migration statistics and validation

Dependencies:
    - Python 3.6+
    - Standard library only (json, pathlib)

The migration process:
1. Flattens existing nested locale structure to dot notation
2. Applies key transformation rules to standardize naming
3. Categorizes keys into semantic groups (buttons, labels, status, etc.)
4. Rebuilds nested structure according to standardized format
5. Validates and outputs the new structure
"""


def flatten_dict(d: Dict[str, Any], parent_key: str = '', sep: str = '.') -> Dict[str, Any]:
    """
    Flatten a nested dictionary to dot notation, preserving arrays
    """
    items: list = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k

        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        elif isinstance(v, list):
            items.append((new_key, v))  # Preserve arrays
        else:
            items.append((new_key, v))
    return dict(items)

def nest_dict(flat_dict: Dict[str, Any], sep: str = '.') -> Dict[str, Any]:
    """
    Convert flat dot notation dictionary to nested structure, preserving arrays

    Example:
        Input: {'a.b.c': 'value'}
        Output: {'a': {'b': {'c': 'value'}}}
    """
    result = {}

    for key, value in flat_dict.items():
        current = result
        *parts, last = key.split(sep)

        # Create nested structure
        for part in parts:
            if part not in current:
                current[part] = {}
            elif not isinstance(current[part], dict):
                # Handle case where intermediate node is not a dict
                old_value = current[part]
                current[part] = {'_value': old_value}
            current = current[part]

        # Set final value
        current[last] = value

    return result


def simplify_key(old_key: str) -> str:
    """
    Simplify key names by removing unnecessary prefixes and standardizing format

    Examples:
        web.COMMON.title_home -> labels.title.home
        web.STATUS.active -> status.active
        web.LABELS.form_field -> labels.form.field
    """
    parts = old_key.lower().split('.')

    # Remove common prefixes that don't add value
    if parts[0] == 'web':
        parts.pop(0)

    if parts[0] in ['common', 'labels']:
        parts.pop(0)

    # Remove redundant words
    if 'title' in parts and parts[0] == 'title':
        parts.remove('title')

    # Clean up remaining parts
    clean_parts = []
    for part in parts:
        # Convert snake_case to camelCase
        words = part.split('_')
        if len(words) > 1:
            clean_part = words[0] + ''.join(word.capitalize() for word in words[1:])
        else:
            clean_part = part
        clean_parts.append(clean_part)

    return '.'.join(clean_parts)

def determine_category(key: str) -> str:
    """
    Determine category based on key content and patterns
    """
    key_lower = key.lower()

    # Direct category matches
    if any(word in key_lower for word in ['button', 'btn', 'submit', 'cancel']):
        return 'buttons'

    if any(word in key_lower for word in ['status', 'state', 'active']):
        return 'status'

    if any(word in key_lower for word in ['error', 'success', 'warning']):
        return 'feedback'

    if any(word in key_lower for word in ['title', 'label', 'heading']):
        return 'labels'

    if any(word in key_lower for word in ['login', 'register', 'password']):
        return 'features.authentication'

    if 'notification' in key_lower:
        return 'features.notifications'

    if any(word in key_lower for word in ['time', 'date', 'duration']):
        return 'time'

    if any(word in key_lower for word in ['format', 'locale']):
        return 'formats'

    return 'other'

def migrate_key(old_key: str, value: Any) -> tuple[str, Any]:
    """
    Migrate a single key to new structure

    Returns:
        tuple of (new_key, value)
    """
    # Simplify the key first
    simple_key = simplify_key(old_key)

    # Determine category
    category = determine_category(simple_key)

    # Construct final key
    if category == 'other':
        return (simple_key, value)
    else:
        return (f"{category}.{simple_key}", value)

def migrate_locale_file(
    source_file: Path,
    template_file: Path,
    output_file: Path
) -> tuple[Dict[str, Any], Dict[str, int]]:
    """
    Migrate locale file to new nested structure

    Returns:
        tuple of (migrated_structure, category_stats)
    """
    print("\nStarting migration...")

    # Load files
    with open(source_file) as f:
        current_locale = json.load(f)
        print(f"Loaded {len(current_locale)} keys from source file")

    with open(template_file) as f:
        template = json.load(f)
        print(f"Loaded template structure")

    # Flatten and migrate
    flat_current = flatten_dict(current_locale)
    print(f"\nFlattened {len(flat_current)} keys")

    new_locale = {}
    category_stats = {}

    print("\nMigrating keys...")
    for old_key, value in flat_current.items():
        new_key, new_value = migrate_key(old_key, value)
        new_locale[new_key] = new_value

        # Track category stats
        category = new_key.split('.')[0]
        category_stats[category] = category_stats.get(category, 0) + 1

    print(f"Migrated {len(new_locale)} keys")

    # Nest the dictionary
    print("\nNesting structure...")
    try:
        nested_locale = nest_dict(new_locale)
        print("Successfully nested structure")
    except Exception as e:
        print(f"Error nesting structure: {e}")
        print("Sample of problematic keys:")
        for k, v in list(new_locale.items())[:5]:
            print(f"  {k}: {v}")
        raise

    # Write output
    print(f"\nWriting to {output_file}")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(nested_locale, f, indent=2, ensure_ascii=False)

    return nested_locale, category_stats

def main():
    """
    Main execution function with error handling
    """
    try:
        # File paths
        base_dir = Path('src/locales')
        source_file = base_dir / 'en.json'
        template_file = Path('nested.json')
        output_file = base_dir / 'en.new.json'

        print(f"Processing files:")
        print(f"Source: {source_file}")
        print(f"Template: {template_file}")
        print(f"Output: {output_file}")

        # Perform migration
        nested_locale, category_stats = migrate_locale_file(
            source_file=source_file,
            template_file=template_file,
            output_file=output_file
        )

        print(f"\nMigration complete!")
        print("\nCategory statistics:")
        for category, count in sorted(category_stats.items()):
            print(f"  {category}: {count} keys")

        # Sample of migrated keys
        print("\nSample of migrated keys:")
        flat_result = flatten_dict(nested_locale)
        for key in list(flat_result.keys())[:5]:
            print(f"  {key}")

    except Exception as e:
        print(f"\nError during migration: {e}")
        raise

if __name__ == '__main__':
    main()
