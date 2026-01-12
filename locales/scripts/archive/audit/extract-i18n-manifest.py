#!/usr/bin/env python3
"""
Extract comprehensive i18n key manifest for Phase 1 safety infrastructure.

This script:
1. Extracts all t() and $t() calls from Vue/TS files
2. Extracts all I18n.t() calls from Ruby files
3. Parses all locale JSON files to build key inventory
4. Cross-references to identify missing, orphaned, and shared keys

Usage:
    python3 src/scripts/locales/audit/extract-i18n-manifest.py

Output:
    - /tmp/i18n_manifest.txt (human-readable report)
    - /tmp/i18n_manifest.json (machine-readable data)
"""

import json
import os
import re
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Set, Tuple

# Dynamically determine project root from script location
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parents[3]  # Go up 4 levels: audit -> locales -> scripts -> src -> project
SRC_DIR = PROJECT_ROOT / "src"
APPS_DIR = PROJECT_ROOT / "apps"
LIB_DIR = PROJECT_ROOT / "lib"
LOCALES_DIR = SRC_DIR / "locales" / "en"

# Patterns for extraction
VUE_TS_PATTERN = re.compile(r'''(?:\$?t\s*\(\s*)(['"])([\\w.]+)\1''')
RUBY_PATTERN = re.compile(r'''I18n\.t\s*\(\s*(['"])([\\w.]+)\1''')

# File extensions
VUE_TS_EXTENSIONS = {'.vue', '.ts', '.tsx', '.js', '.jsx'}
RUBY_EXTENSIONS = {'.rb'}

# Directories to skip
SKIP_DIRS = {'node_modules', 'dist', '.git', '__pycache__', 'public', 'tmp', 'coverage'}


def extract_keys_from_file(filepath: Path, pattern: re.Pattern) -> List[Tuple[str, int, str]]:
    """Extract i18n keys from a file with line numbers."""
    keys = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                matches = pattern.findall(line)
                for match in matches:
                    # match is (quote, key)
                    key = match[1] if isinstance(match, tuple) else match
                    keys.append((key, line_num, line.strip()[:80]))
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
    return keys


def find_vue_ts_keys(root_dir: Path) -> Dict[str, List[Tuple[Path, int, str]]]:
    """Find all t() and $t() calls in Vue/TS files."""
    keys_map = defaultdict(list)

    for root, dirs, files in os.walk(root_dir):
        # Skip unwanted directories
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

        for filename in files:
            filepath = Path(root) / filename
            if filepath.suffix in VUE_TS_EXTENSIONS:
                keys = extract_keys_from_file(filepath, VUE_TS_PATTERN)
                for key, line_num, line_text in keys:
                    keys_map[key].append((filepath, line_num, line_text))

    return keys_map


def find_ruby_keys(root_dirs: List[Path]) -> Dict[str, List[Tuple[Path, int, str]]]:
    """Find all I18n.t() calls in Ruby files."""
    keys_map = defaultdict(list)

    for root_dir in root_dirs:
        if not root_dir.exists():
            continue

        for root, dirs, files in os.walk(root_dir):
            # Skip unwanted directories
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

            for filename in files:
                filepath = Path(root) / filename
                if filepath.suffix in RUBY_EXTENSIONS:
                    keys = extract_keys_from_file(filepath, RUBY_PATTERN)
                    for key, line_num, line_text in keys:
                        keys_map[key].append((filepath, line_num, line_text))

    return keys_map


def flatten_json(data: dict, prefix: str = '') -> Set[str]:
    """Recursively flatten nested JSON structure to dot-notation keys."""
    keys = set()

    for key, value in data.items():
        # Skip metadata keys
        if key.startswith('_'):
            continue

        full_key = f"{prefix}.{key}" if prefix else key

        if isinstance(value, dict):
            # Recurse into nested objects
            keys.update(flatten_json(value, full_key))
        else:
            # Leaf node - this is a translatable key
            keys.add(full_key)

    return keys


def load_locale_keys() -> Set[str]:
    """Load all keys from locale JSON files."""
    all_keys = set()

    if not LOCALES_DIR.exists():
        print(f"Warning: Locales directory not found: {LOCALES_DIR}")
        return all_keys

    for json_file in LOCALES_DIR.glob("*.json"):
        try:
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                keys = flatten_json(data)
                all_keys.update(keys)
                print(f"Loaded {len(keys)} keys from {json_file.name}")
        except Exception as e:
            print(f"Error loading {json_file}: {e}")

    return all_keys


def analyze_keys(vue_ts_keys: Dict, ruby_keys: Dict, locale_keys: Set) -> Dict:
    """Cross-reference and analyze all keys."""

    # Get unique keys used in code
    vue_ts_used = set(vue_ts_keys.keys())
    ruby_used = set(ruby_keys.keys())
    all_used = vue_ts_used | ruby_used

    # Find missing keys (used in code but not in locale files)
    missing_keys = all_used - locale_keys

    # Find orphaned keys (in locale files but not used in code)
    orphaned_keys = locale_keys - all_used

    # Find shared keys (used in both frontend and backend)
    shared_keys = vue_ts_used & ruby_used

    # Only Vue/TS keys
    vue_ts_only = vue_ts_used - ruby_used

    # Only Ruby keys
    ruby_only = ruby_used - vue_ts_used

    return {
        'vue_ts_keys': vue_ts_keys,
        'ruby_keys': ruby_keys,
        'locale_keys': locale_keys,
        'vue_ts_used': vue_ts_used,
        'ruby_used': ruby_used,
        'all_used': all_used,
        'missing_keys': missing_keys,
        'orphaned_keys': orphaned_keys,
        'shared_keys': shared_keys,
        'vue_ts_only': vue_ts_only,
        'ruby_only': ruby_only,
    }


def generate_report(analysis: Dict) -> str:
    """Generate comprehensive manifest report."""

    report_lines = []

    report_lines.append("=" * 80)
    report_lines.append("I18N KEY USAGE MANIFEST - Phase 1 Safety Infrastructure")
    report_lines.append("=" * 80)
    report_lines.append("")

    # Summary statistics
    report_lines.append("SUMMARY STATISTICS")
    report_lines.append("-" * 80)
    report_lines.append(f"Total keys in locale files:        {len(analysis['locale_keys'])}")
    report_lines.append(f"Total keys used in Vue/TS:         {len(analysis['vue_ts_used'])}")
    report_lines.append(f"Total keys used in Ruby:           {len(analysis['ruby_used'])}")
    report_lines.append(f"Total unique keys used:            {len(analysis['all_used'])}")
    report_lines.append("")
    report_lines.append(f"Keys used in Vue/TS only:          {len(analysis['vue_ts_only'])}")
    report_lines.append(f"Keys used in Ruby only:            {len(analysis['ruby_only'])}")
    report_lines.append(f"Keys shared (frontend + backend):  {len(analysis['shared_keys'])} ⚠️  CRITICAL")
    report_lines.append("")
    report_lines.append(f"Missing keys (used but not in locale): {len(analysis['missing_keys'])} ❌")
    report_lines.append(f"Orphaned keys (in locale but unused):  {len(analysis['orphaned_keys'])} ⚠️")
    report_lines.append("")

    # Shared keys section (CRITICAL for migration)
    if analysis['shared_keys']:
        report_lines.append("=" * 80)
        report_lines.append("SHARED KEYS (Used in BOTH frontend and backend) - CRITICAL FOR MIGRATION")
        report_lines.append("=" * 80)
        report_lines.append("These keys are used in both Vue/TS and Ruby code.")
        report_lines.append("Changes to these keys require updates in BOTH codebases!")
        report_lines.append("")

        for key in sorted(analysis['shared_keys']):
            report_lines.append(f"\n  {key}")

            # Frontend usage
            report_lines.append(f"    Frontend: {len(analysis['vue_ts_keys'][key])} usage(s)")
            for filepath, line_num, _ in analysis['vue_ts_keys'][key][:2]:
                rel_path = filepath.relative_to(PROJECT_ROOT)
                report_lines.append(f"      - {rel_path}:{line_num}")
            if len(analysis['vue_ts_keys'][key]) > 2:
                report_lines.append(f"      ... and {len(analysis['vue_ts_keys'][key]) - 2} more")

            # Backend usage
            report_lines.append(f"    Backend:  {len(analysis['ruby_keys'][key])} usage(s)")
            for filepath, line_num, _ in analysis['ruby_keys'][key][:2]:
                rel_path = filepath.relative_to(PROJECT_ROOT)
                report_lines.append(f"      - {rel_path}:{line_num}")
            if len(analysis['ruby_keys'][key]) > 2:
                report_lines.append(f"      ... and {len(analysis['ruby_keys'][key]) - 2} more")
        report_lines.append("")

    # Missing keys section
    if analysis['missing_keys']:
        report_lines.append("=" * 80)
        report_lines.append("MISSING KEYS (Used in code but NOT in locale files)")
        report_lines.append("=" * 80)
        for key in sorted(list(analysis['missing_keys']))[:50]:
            report_lines.append(f"  - {key}")
        if len(analysis['missing_keys']) > 50:
            report_lines.append(f"\n  ... and {len(analysis['missing_keys']) - 50} more missing keys")
        report_lines.append("")

    # Orphaned keys section (first 50)
    if analysis['orphaned_keys']:
        report_lines.append("=" * 80)
        report_lines.append(f"ORPHANED KEYS (In locale files but NOT used in code) - First 50 of {len(analysis['orphaned_keys'])}")
        report_lines.append("=" * 80)
        for key in sorted(list(analysis['orphaned_keys']))[:50]:
            report_lines.append(f"  - {key}")
        if len(analysis['orphaned_keys']) > 50:
            report_lines.append(f"\n  ... and {len(analysis['orphaned_keys']) - 50} more orphaned keys")
        report_lines.append("")

    report_lines.append("=" * 80)
    report_lines.append("END OF MANIFEST")
    report_lines.append("=" * 80)

    return "\n".join(report_lines)


def save_detailed_json(analysis: Dict, output_path: Path):
    """Save detailed analysis as JSON for programmatic access."""

    # Convert sets and complex types to serializable formats
    serializable = {
        'summary': {
            'total_locale_keys': len(analysis['locale_keys']),
            'total_vue_ts_keys': len(analysis['vue_ts_used']),
            'total_ruby_keys': len(analysis['ruby_used']),
            'total_unique_used': len(analysis['all_used']),
            'vue_ts_only': len(analysis['vue_ts_only']),
            'ruby_only': len(analysis['ruby_only']),
            'shared_keys': len(analysis['shared_keys']),
            'missing_keys': len(analysis['missing_keys']),
            'orphaned_keys': len(analysis['orphaned_keys']),
        },
        'missing_keys': sorted(list(analysis['missing_keys'])),
        'orphaned_keys': sorted(list(analysis['orphaned_keys'])),
        'shared_keys': sorted(list(analysis['shared_keys'])),
        'vue_ts_only_keys': sorted(list(analysis['vue_ts_only'])),
        'ruby_only_keys': sorted(list(analysis['ruby_only'])),
        'locale_keys': sorted(list(analysis['locale_keys'])),

        # Detailed usage information
        'vue_ts_usage': {
            key: [
                {
                    'file': str(filepath.relative_to(PROJECT_ROOT)),
                    'line': line_num,
                    'text': text
                }
                for filepath, line_num, text in usages
            ]
            for key, usages in analysis['vue_ts_keys'].items()
        },
        'ruby_usage': {
            key: [
                {
                    'file': str(filepath.relative_to(PROJECT_ROOT)),
                    'line': line_num,
                    'text': text
                }
                for filepath, line_num, text in usages
            ]
            for key, usages in analysis['ruby_keys'].items()
        },
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(serializable, f, indent=2, ensure_ascii=False)

    print(f"Detailed JSON saved to: {output_path}")


def main():
    print("I18n Key Manifest Generator")
    print("=" * 60)
    print(f"Project root: {PROJECT_ROOT}")
    print("")

    # Extract Vue/TS keys
    print("Extracting Vue/TS keys...")
    vue_ts_keys = find_vue_ts_keys(SRC_DIR)
    print(f"Found {len(vue_ts_keys)} unique Vue/TS keys")
    print("")

    # Extract Ruby keys
    print("Extracting Ruby keys...")
    ruby_keys = find_ruby_keys([APPS_DIR, LIB_DIR])
    print(f"Found {len(ruby_keys)} unique Ruby keys")
    print("")

    # Load locale keys
    print("Loading locale file keys...")
    locale_keys = load_locale_keys()
    print(f"Found {len(locale_keys)} keys in locale files")
    print("")

    # Analyze and cross-reference
    print("Analyzing and cross-referencing...")
    analysis = analyze_keys(vue_ts_keys, ruby_keys, locale_keys)
    print("")

    # Generate report
    report = generate_report(analysis)

    # Save outputs
    output_txt = Path("/tmp/i18n_manifest.txt")
    output_json = Path("/tmp/i18n_manifest.json")

    with open(output_txt, 'w', encoding='utf-8') as f:
        f.write(report)
    print(f"Text report saved to: {output_txt}")

    save_detailed_json(analysis, output_json)

    # Print report to console
    print("\n" + report)


if __name__ == '__main__':
    main()
