#!/usr/bin/env python3
"""
Vue Component i18n Key Migration Script

Uses the kebab-to-snake-report.json master_mapping to find and fix
$t() and t() calls in Vue components that still reference old kebab-case keys.

Usage:
    python src/scripts/locales/migrate-vue-i18n-keys.py [--dry-run] [--verify-only]

Options:
    --dry-run       Preview changes without modifying files
    --verify-only   Only verify JSON files have no kebab-case keys, skip Vue migration

Output:
    - Console report of findings
    - Modified Vue files (unless --dry-run)
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def load_master_mapping(report_path: Path) -> dict[str, str]:
    """Load the kebab→snake mapping from the migration report."""
    if not report_path.exists():
        print(f"ERROR: Report not found at {report_path}")
        sys.exit(1)

    with open(report_path, "r", encoding="utf-8") as f:
        report = json.load(f)

    return report.get("master_mapping", {})


def is_kebab_case(key: str) -> bool:
    """Check if a key contains kebab-case patterns."""
    return bool(re.search(r"[a-z0-9]-[a-z0-9]", key))


def find_kebab_keys_in_json(json_path: Path) -> list[tuple[str, str]]:
    """Find any remaining kebab-case keys in a JSON locale file.

    Returns list of (key_path, key_name) tuples.
    """
    kebab_keys = []

    def scan_object(obj: Any, path: str = "") -> None:
        if isinstance(obj, dict):
            for key, value in obj.items():
                current_path = f"{path}.{key}" if path else key
                if is_kebab_case(key):
                    kebab_keys.append((current_path, key))
                scan_object(value, current_path)

    try:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        scan_object(data)
    except json.JSONDecodeError as e:
        print(f"  WARNING: Invalid JSON in {json_path}: {e}")

    return kebab_keys


def verify_json_files(locales_dir: Path) -> tuple[int, int]:
    """Verify all JSON locale files have no kebab-case keys.

    Returns (total_files, files_with_issues).
    """
    print("\n" + "=" * 60)
    print("PHASE 1: Verifying JSON Locale Files")
    print("=" * 60)

    total_files = 0
    files_with_issues = 0
    all_kebab_keys = []

    for locale_dir in sorted(locales_dir.iterdir()):
        if not locale_dir.is_dir() or locale_dir.name.startswith("."):
            continue

        for json_file in sorted(locale_dir.glob("*.json")):
            total_files += 1
            kebab_keys = find_kebab_keys_in_json(json_file)

            if kebab_keys:
                files_with_issues += 1
                rel_path = json_file.relative_to(locales_dir.parent.parent.parent)
                print(f"\n  {rel_path}:")
                for key_path, key_name in kebab_keys[:5]:  # Show first 5
                    print(f"    - {key_path}")
                if len(kebab_keys) > 5:
                    print(f"    ... and {len(kebab_keys) - 5} more")
                all_kebab_keys.extend(kebab_keys)

    print(f"\n  Summary: {total_files} files checked")
    if files_with_issues == 0:
        print("  ✅ All JSON files have snake_case keys")
    else:
        print(f"  ❌ {files_with_issues} files still have kebab-case keys")
        print(f"     Total kebab-case keys found: {len(all_kebab_keys)}")

    return total_files, files_with_issues


def find_i18n_calls_in_vue(vue_path: Path, mapping: dict[str, str]) -> list[dict]:
    """Find $t() and t() calls in a Vue file that use old kebab-case keys.

    Returns list of dicts with: line_num, old_key, new_key, line_content, match_start, match_end
    """
    findings = []

    try:
        content = vue_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"  WARNING: Could not read {vue_path}: {e}")
        return findings

    lines = content.split("\n")

    # Pattern to match $t('key') or t('key') with various quote styles
    # Captures: the t function call, the quote char, and the key
    pattern = re.compile(r"""
        (\$?t)\s*\(\s*      # $t( or t( with optional whitespace
        (['"`])             # Opening quote
        ([^'"`]+)           # The key (captured)
        \2                  # Matching closing quote
    """, re.VERBOSE)

    for line_num, line in enumerate(lines, start=1):
        for match in pattern.finditer(line):
            full_key = match.group(3)

            # Extract just the final key segment for mapping lookup
            # e.g., "web.COMMON.some-key" -> check "some-key"
            key_parts = full_key.split(".")

            for i, part in enumerate(key_parts):
                if part in mapping:
                    # Found a kebab-case key that needs updating
                    new_parts = key_parts.copy()
                    new_parts[i] = mapping[part]
                    new_key = ".".join(new_parts)

                    findings.append({
                        "line_num": line_num,
                        "old_key": full_key,
                        "new_key": new_key,
                        "line_content": line.strip(),
                        "match_start": match.start(),
                        "match_end": match.end(),
                    })
                    break  # Only report once per key

    return findings


def apply_fixes_to_vue(vue_path: Path, mapping: dict[str, str]) -> tuple[int, str]:
    """Apply kebab→snake fixes to a Vue file.

    Returns (num_fixes, new_content).
    """
    try:
        content = vue_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"  WARNING: Could not read {vue_path}: {e}")
        return 0, ""

    original_content = content
    num_fixes = 0

    # Pattern to match $t('key') or t('key') - we'll replace the key inside
    pattern = re.compile(r"""
        (\$?t\s*\(\s*)       # $t( or t( - group 1
        (['"`])              # Opening quote - group 2
        ([^'"`]+)            # The key - group 3
        (\2)                 # Closing quote - group 4
    """, re.VERBOSE)

    def replace_key(match):
        nonlocal num_fixes
        prefix = match.group(1)
        quote = match.group(2)
        full_key = match.group(3)

        # Check each part of the key path
        key_parts = full_key.split(".")
        modified = False

        for i, part in enumerate(key_parts):
            if part in mapping:
                key_parts[i] = mapping[part]
                modified = True

        if modified:
            num_fixes += 1
            new_key = ".".join(key_parts)
            return f"{prefix}{quote}{new_key}{quote}"

        return match.group(0)

    new_content = pattern.sub(replace_key, content)

    return num_fixes, new_content


def migrate_vue_files(src_dir: Path, mapping: dict[str, str], dry_run: bool) -> tuple[int, int, int]:
    """Find and optionally fix Vue files with old kebab-case keys.

    Returns (total_files, files_with_issues, total_fixes).
    """
    print("\n" + "=" * 60)
    print("PHASE 2: Migrating Vue Component i18n Keys")
    print("=" * 60)

    if dry_run:
        print("  [DRY RUN MODE - No files will be modified]\n")

    vue_files = list(src_dir.rglob("*.vue"))
    total_files = len(vue_files)
    files_with_issues = 0
    total_fixes = 0

    files_to_fix = []

    # First pass: find all issues
    for vue_path in sorted(vue_files):
        findings = find_i18n_calls_in_vue(vue_path, mapping)

        if findings:
            files_with_issues += 1
            rel_path = vue_path.relative_to(src_dir.parent)
            files_to_fix.append((vue_path, findings))

            print(f"\n  {rel_path}: {len(findings)} key(s) to update")
            for f in findings[:3]:  # Show first 3
                print(f"    L{f['line_num']}: {f['old_key']} → {f['new_key']}")
            if len(findings) > 3:
                print(f"    ... and {len(findings) - 3} more")

    # Second pass: apply fixes (if not dry-run)
    if not dry_run and files_to_fix:
        print("\n" + "-" * 40)
        print("Applying fixes...")

        for vue_path, findings in files_to_fix:
            num_fixes, new_content = apply_fixes_to_vue(vue_path, mapping)
            if num_fixes > 0:
                vue_path.write_text(new_content, encoding="utf-8")
                total_fixes += num_fixes
                rel_path = vue_path.relative_to(src_dir.parent)
                print(f"  ✓ {rel_path}: {num_fixes} fix(es) applied")
    elif dry_run:
        # In dry-run, count what would be fixed
        for vue_path, findings in files_to_fix:
            total_fixes += len(findings)

    print(f"\n  Summary: {total_files} Vue files scanned")
    if files_with_issues == 0:
        print("  ✅ All Vue files use snake_case keys")
    else:
        if dry_run:
            print(f"  ⚠️  {files_with_issues} files have {total_fixes} key(s) to update")
            print("     Run without --dry-run to apply fixes")
        else:
            print(f"  ✅ Fixed {total_fixes} key(s) in {files_with_issues} files")

    return total_files, files_with_issues, total_fixes


def main():
    parser = argparse.ArgumentParser(
        description="Migrate Vue component i18n keys from kebab-case to snake_case"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without modifying files"
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Only verify JSON files, skip Vue migration"
    )
    args = parser.parse_args()

    # Paths
    script_dir = Path(__file__).parent
    project_root = script_dir.parent.parent.parent
    src_dir = project_root / "src"
    locales_dir = src_dir / "locales"
    report_path = script_dir / "kebab-to-snake-report.json"

    print("=" * 60)
    print("Vue i18n Key Migration Script")
    print("=" * 60)
    print(f"Project root: {project_root}")
    print(f"Report file: {report_path}")

    # Load mapping
    mapping = load_master_mapping(report_path)
    print(f"Loaded {len(mapping)} key mappings from report")

    # Phase 1: Verify JSON files
    json_total, json_issues = verify_json_files(locales_dir)

    if args.verify_only:
        print("\n[--verify-only specified, skipping Vue migration]")
        sys.exit(0 if json_issues == 0 else 1)

    # Phase 2: Migrate Vue files
    vue_total, vue_issues, vue_fixes = migrate_vue_files(src_dir, mapping, args.dry_run)

    # Final summary
    print("\n" + "=" * 60)
    print("FINAL SUMMARY")
    print("=" * 60)
    print(f"  JSON files: {json_total} checked, {json_issues} with issues")
    print(f"  Vue files:  {vue_total} scanned, {vue_issues} with issues")
    if args.dry_run:
        print(f"  Keys to fix: {vue_fixes}")
    else:
        print(f"  Keys fixed: {vue_fixes}")

    # Exit code
    if json_issues > 0 or (vue_issues > 0 and not args.dry_run):
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
