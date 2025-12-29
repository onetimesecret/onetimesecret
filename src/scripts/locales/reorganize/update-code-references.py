#!/usr/bin/env python3
"""
Update Vue/TypeScript code references from flat i18n keys to hierarchical keys.

This script reads the category-mapping.json and updates all t('flat-key') calls
to t('web.category.flat-key') format in the src/ directory.

Usage:
    python3 update-code-references.py [--dry-run] [--verbose]

Options:
    --dry-run   Show what would be changed without making changes
    --verbose   Show detailed output for each file
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

# Get the project root (4 levels up from this script)
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent.parent
SRC_DIR = PROJECT_ROOT / "src"
MAPPING_FILE = SCRIPT_DIR / "category-mapping.json"

# File extensions to process
EXTENSIONS = {'.vue', '.ts', '.tsx', '.js', '.jsx'}

# Directories to skip
SKIP_DIRS = {'node_modules', 'dist', '.git', '__pycache__', 'locales', 'scripts'}


def load_mappings() -> Dict[str, str]:
    """Load the category mapping and return a dict of source_key -> target_path."""
    with open(MAPPING_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    mappings = {}
    for entry in data['mappings']:
        source_key = entry['source_key']
        target_path = entry['target_path']
        mappings[source_key] = target_path

    return mappings


def find_files(directory: Path) -> List[Path]:
    """Find all Vue/TS files in the directory."""
    files = []
    for root, dirs, filenames in os.walk(directory):
        # Skip unwanted directories
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

        for filename in filenames:
            filepath = Path(root) / filename
            if filepath.suffix in EXTENSIONS:
                files.append(filepath)

    return files


def create_replacement_pattern(source_key: str) -> str:
    """Create a regex pattern to match the source key in t() calls."""
    # Escape special regex characters in the key
    escaped_key = re.escape(source_key)

    # Match t('key'), t("key"), $t('key'), $t("key")
    # Also handle optional whitespace
    pattern = rf'''(\$?t\s*\(\s*)(['"]){escaped_key}\2'''
    return pattern


def update_file_content(content: str, mappings: Dict[str, str], verbose: bool = False) -> Tuple[str, List[str]]:
    """Update all i18n references in the file content."""
    changes = []
    new_content = content

    # Sort keys by length descending to process longer keys first
    # This prevents incorrect partial replacements when one key is a substring of another
    sorted_keys = sorted(mappings.keys(), key=len, reverse=True)

    for source_key in sorted_keys:
        target_path = mappings[source_key]
        pattern = create_replacement_pattern(source_key)

        # Find all matches
        matches = list(re.finditer(pattern, new_content))

        if matches:
            # Replace each match
            for match in reversed(matches):  # Reverse to preserve positions
                full_match = match.group(0)
                prefix = match.group(1)  # $t( or t(
                quote = match.group(2)   # ' or "

                replacement = f"{prefix}{quote}{target_path}{quote}"

                start, end = match.span()
                new_content = new_content[:start] + replacement + new_content[end:]

                changes.append(f"  {source_key} -> {target_path}")

    return new_content, changes


def process_files(dry_run: bool = False, verbose: bool = False) -> Dict[str, any]:
    """Process all files and update i18n references."""
    mappings = load_mappings()
    files = find_files(SRC_DIR)

    stats = {
        'files_scanned': len(files),
        'files_modified': 0,
        'total_replacements': 0,
        'changes_by_file': {},
        'errors': []
    }

    print(f"Loaded {len(mappings)} key mappings")
    print(f"Found {len(files)} files to scan")
    print("-" * 60)

    for filepath in files:
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            new_content, changes = update_file_content(content, mappings, verbose)

            if changes:
                relative_path = filepath.relative_to(PROJECT_ROOT)
                stats['files_modified'] += 1
                stats['total_replacements'] += len(changes)
                stats['changes_by_file'][str(relative_path)] = changes

                if verbose:
                    print(f"\n{relative_path}:")
                    for change in changes:
                        print(change)
                else:
                    print(f"[{len(changes):3d} changes] {relative_path}")

                if not dry_run:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(new_content)

        except Exception as e:
            stats['errors'].append(f"{filepath}: {str(e)}")

    return stats


def main():
    dry_run = '--dry-run' in sys.argv
    verbose = '--verbose' in sys.argv

    if dry_run:
        print("=" * 60)
        print("DRY RUN MODE - No files will be modified")
        print("=" * 60)
    else:
        print("=" * 60)
        print("UPDATING CODE REFERENCES")
        print("=" * 60)

    print(f"\nProject root: {PROJECT_ROOT}")
    print(f"Source directory: {SRC_DIR}")
    print(f"Mapping file: {MAPPING_FILE}\n")

    stats = process_files(dry_run=dry_run, verbose=verbose)

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Files scanned:     {stats['files_scanned']}")
    print(f"Files modified:    {stats['files_modified']}")
    print(f"Total replacements: {stats['total_replacements']}")

    if stats['errors']:
        print(f"\nErrors ({len(stats['errors'])}):")
        for error in stats['errors']:
            print(f"  - {error}")

    if dry_run and stats['files_modified'] > 0:
        print("\nRun without --dry-run to apply changes.")

    return 0 if not stats['errors'] else 1


if __name__ == '__main__':
    sys.exit(main())
