#!/usr/bin/env python3
"""
Atomic camelCase to snake_case Key Migration for Locale Files

This script performs atomic renaming of camelCase keys to snake_case across
all locale directories. It handles nested JSON structures and ensures
consistency across all locales.

Usage:
    python src/scripts/locales/migrate/migrate-camel-to-snake.py [--dry-run]

Options:
    --dry-run    Preview changes without modifying files

Output:
    - Creates backup at src/locales/.backup-camel-to-snake/
    - Generates report at src/scripts/locales/migrate/camel-to-snake-report.json
"""

import argparse
import json
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


# Known duplicates to delete (camelCase versions that duplicate snake_case)
# These are keys where both camelCase and snake_case versions exist.
# The camelCase version will be deleted, keeping the snake_case version.
DUPLICATES_TO_DELETE: set[str] = set()


def is_camel_case(key: str) -> bool:
    """Check if a key is camelCase (lowercase start, contains uppercase letters).

    Examples that match:
        - firstName -> True
        - lastName -> True
        - myAPIKey -> True
        - getUserData -> True

    Examples that don't match:
        - first_name -> False (snake_case)
        - FirstName -> False (PascalCase)
        - CONSTANT -> False (all uppercase)
        - lowercase -> False (no uppercase)
    """
    # Must start with lowercase, contain at least one uppercase letter
    # Exclude keys that are all lowercase or start with uppercase
    return bool(re.match(r"^[a-z]", key) and re.search(r"[A-Z]", key))


def camel_to_snake(key: str) -> str:
    """Convert a camelCase key to snake_case.

    Examples:
        - firstName -> first_name
        - lastName -> last_name
        - myAPIKey -> my_api_key
        - getUserData -> get_user_data
        - HTMLParser -> html_parser
    """
    # Insert underscore before uppercase letters and lowercase them
    # Handle consecutive uppercase (like API, HTML) specially
    s1 = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", key)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s1).lower()


def get_full_key_path(path: list[str], key: str) -> str:
    """Build a full dotted key path."""
    return ".".join(path + [key])


def find_camel_keys(
    obj: dict[str, Any],
    path: list[str] | None = None,
    results: list[dict] | None = None,
) -> list[dict]:
    """
    Recursively find all camelCase keys in a nested JSON structure.

    Returns a list of dicts with:
        - full_path: dotted path to the key
        - old_key: the original key name
        - new_key: the snake_case version
        - parent_path: path to parent object
    """
    if path is None:
        path = []
    if results is None:
        results = []

    for key, value in obj.items():
        full_path = get_full_key_path(path, key)

        if is_camel_case(key):
            new_key = camel_to_snake(key)
            results.append(
                {
                    "full_path": full_path,
                    "old_key": key,
                    "new_key": new_key,
                    "parent_path": path.copy(),
                }
            )

        if isinstance(value, dict):
            find_camel_keys(value, path + [key], results)

    return results


def transform_keys(
    obj: dict[str, Any],
    key_mapping: dict[str, str],
    keys_to_delete: set[str] | None = None,
) -> dict[str, Any]:
    """
    Recursively transform all keys in a nested JSON structure using the provided mapping.
    Also handles deletion of duplicate keys and conflict resolution.

    Args:
        obj: The JSON object to transform
        key_mapping: Dict mapping old_key -> new_key
        keys_to_delete: Set of camelCase keys to delete (conflicts)
    """
    if keys_to_delete is None:
        keys_to_delete = set()

    result = {}

    for key, value in obj.items():
        # Skip keys explicitly marked for deletion
        if key in keys_to_delete:
            continue

        # Check if this is a camelCase key that needs transformation
        if key in key_mapping:
            new_key = key_mapping[key]
            # If snake_case version already exists in the object, skip this camelCase key
            # (it's a duplicate and should be deleted)
            if new_key in obj:
                continue
            # Otherwise, rename it
            if isinstance(value, dict):
                result[new_key] = transform_keys(value, key_mapping, keys_to_delete)
            else:
                result[new_key] = value
        else:
            # Keep the key as-is, but recursively process nested objects
            if isinstance(value, dict):
                result[key] = transform_keys(value, key_mapping, keys_to_delete)
            else:
                result[key] = value

    return result


def check_for_conflicts(
    obj: dict[str, Any], camel_keys: list[dict]
) -> list[dict]:
    """
    Check if any snake_case target keys already exist (potential conflicts).
    """
    conflicts = []

    for key_info in camel_keys:
        # Navigate to parent
        parent = obj
        for p in key_info["parent_path"]:
            parent = parent.get(p, {})

        # Check if snake_case version already exists
        if key_info["new_key"] in parent and key_info["old_key"] in parent:
            conflicts.append(
                {
                    "path": key_info["full_path"],
                    "old_key": key_info["old_key"],
                    "new_key": key_info["new_key"],
                    "old_value": parent.get(key_info["old_key"]),
                    "existing_value": parent.get(key_info["new_key"]),
                }
            )

    return conflicts


def build_key_mapping_from_analysis(camel_keys: list[dict]) -> dict[str, str]:
    """
    Build a simple key-to-key mapping from the analysis results.
    """
    mapping = {}
    for key_info in camel_keys:
        mapping[key_info["old_key"]] = key_info["new_key"]
    return mapping


def process_locale_file(
    file_path: Path, key_mapping: dict[str, str], keys_to_delete: set[str]
) -> tuple[dict[str, Any], list[dict], list[dict]]:
    """
    Process a single locale JSON file.

    Returns:
        - transformed: The transformed JSON object
        - changes: List of changes made
        - conflicts_resolved: List of conflicts that were auto-resolved (duplicates deleted)
    """
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Find all camelCase keys in this file
    camel_keys = find_camel_keys(data)

    # Check for conflicts (where both camelCase and snake_case versions exist)
    conflicts = check_for_conflicts(data, camel_keys)

    # Transform the data - this will automatically:
    # 1. Rename camelCase keys to snake_case
    # 2. Skip (delete) camelCase keys if snake_case version already exists
    # 3. Skip keys explicitly marked for deletion
    transformed = transform_keys(data, key_mapping, keys_to_delete)

    # Build changes list
    changes = []
    conflicts_resolved = []

    for key_info in camel_keys:
        full_path = key_info["full_path"]
        old_key = key_info["old_key"]
        new_key = key_info["new_key"]

        # Check if this key is explicitly marked for deletion
        if old_key in keys_to_delete:
            changes.append(
                {
                    "action": "delete",
                    "path": full_path,
                    "reason": "explicitly marked for deletion",
                }
            )
        # Check if this is a conflict (snake_case version exists)
        elif any(c["old_key"] == old_key for c in conflicts):
            changes.append(
                {
                    "action": "delete",
                    "path": full_path,
                    "reason": "duplicate - snake_case version already exists",
                }
            )
            conflicts_resolved.append(
                {
                    "path": full_path,
                    "old_key": old_key,
                    "new_key": new_key,
                    "action": "deleted camelCase duplicate",
                }
            )
        else:
            changes.append(
                {
                    "action": "rename",
                    "old_path": full_path,
                    "new_path": get_full_key_path(
                        key_info["parent_path"], new_key
                    ),
                }
            )

    return transformed, changes, conflicts_resolved


def main():
    parser = argparse.ArgumentParser(
        description="Migrate camelCase keys to snake_case across all locale files"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without modifying files",
    )
    args = parser.parse_args()

    # Paths
    script_dir = Path(__file__).parent
    project_root = script_dir.parent.parent.parent.parent
    locales_dir = project_root / "src" / "locales"
    backup_dir = locales_dir / ".backup-camel-to-snake"
    report_path = script_dir / "camel-to-snake-report.json"

    # Auto-discover locale directories (all subdirectories in locales_dir)
    locale_dirs = sorted([
        d.name for d in locales_dir.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    ])

    print("Locale files migration: camelCase -> snake_case")
    print(f"Mode: {'DRY RUN' if args.dry_run else 'LIVE'}")
    print(f"Locales directory: {locales_dir}")
    print(f"Found {len(locale_dirs)} locale directories")
    print()

    # Step 1: Analyze English locale to build master key mapping
    print("Step 1: Analyzing English locale to build key mapping...")
    en_dir = locales_dir / "en"

    if not en_dir.exists():
        print(f"ERROR: English locale directory not found: {en_dir}")
        sys.exit(1)

    master_mapping = {}
    total_camel_keys = 0

    for json_file in en_dir.glob("*.json"):
        with open(json_file, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError as e:
                print(f"  WARNING: Failed to parse {json_file.name}: {e}")
                continue

        camel_keys = find_camel_keys(data)
        file_mapping = build_key_mapping_from_analysis(camel_keys)
        master_mapping.update(file_mapping)
        total_camel_keys += len(camel_keys)
        if camel_keys:
            print(f"  {json_file.name}: {len(camel_keys)} camelCase keys")

    print(f"\nTotal unique camelCase keys found: {len(master_mapping)}")
    print(f"Total camelCase key occurrences: {total_camel_keys}")

    if not master_mapping:
        print("\nNo camelCase keys found. Nothing to migrate.")
        return 0

    # Show sample mappings
    print("\nSample key transformations:")
    for i, (old, new) in enumerate(sorted(master_mapping.items())[:10]):
        print(f"  {old} -> {new}")
    if len(master_mapping) > 10:
        print(f"  ... and {len(master_mapping) - 10} more")

    # Keys to delete (explicitly marked duplicates)
    keys_to_delete = set(DUPLICATES_TO_DELETE)

    if keys_to_delete:
        print(f"\nExplicitly marked duplicates to delete: {sorted(keys_to_delete)}")

    # Step 2: Create backup if not dry run
    if not args.dry_run:
        print(f"\nStep 2: Creating backup at {backup_dir}...")
        if backup_dir.exists():
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            old_backup = backup_dir.with_name(f".backup-camel-to-snake-{timestamp}")
            shutil.move(backup_dir, old_backup)
            print(f"  Moved existing backup to {old_backup.name}")

        backup_dir.mkdir(parents=True, exist_ok=True)

        for locale in locale_dirs:
            locale_path = locales_dir / locale
            if locale_path.exists():
                backup_locale_path = backup_dir / locale
                shutil.copytree(locale_path, backup_locale_path)

        print("  Backup created successfully")
    else:
        print("\nStep 2: Skipping backup (dry run)")

    # Step 3: Process all locale directories
    print(f"\nStep 3: Processing {len(locale_dirs)} locale directories...")

    report = {
        "timestamp": datetime.now().isoformat(),
        "mode": "dry_run" if args.dry_run else "live",
        "master_mapping": master_mapping,
        "duplicates_deleted": list(DUPLICATES_TO_DELETE),
        "locales_processed": [],
        "summary": {
            "total_files": 0,
            "total_changes": 0,
            "total_conflicts_resolved": 0,
            "files_with_changes": 0,
        },
    }

    all_conflicts_resolved = []

    for locale in locale_dirs:
        locale_path = locales_dir / locale
        if not locale_path.exists():
            print(f"  WARNING: Locale directory not found: {locale}")
            continue

        locale_report = {
            "locale": locale,
            "files": [],
            "total_changes": 0,
            "total_conflicts_resolved": 0,
        }

        json_files = list(locale_path.glob("*.json"))
        for json_file in json_files:
            try:
                transformed, changes, conflicts_resolved = process_locale_file(
                    json_file, master_mapping, keys_to_delete
                )

                file_report = {
                    "file": json_file.name,
                    "changes": len(changes),
                    "conflicts_resolved": len(conflicts_resolved),
                    "change_details": changes if changes else None,
                }

                if conflicts_resolved:
                    file_report["conflicts_resolved_details"] = conflicts_resolved
                    all_conflicts_resolved.extend(conflicts_resolved)

                locale_report["files"].append(file_report)
                locale_report["total_changes"] += len(changes)
                locale_report["total_conflicts_resolved"] += len(conflicts_resolved)
                report["summary"]["total_files"] += 1
                report["summary"]["total_changes"] += len(changes)

                if changes:
                    report["summary"]["files_with_changes"] += 1

                # Write transformed file if not dry run and there are changes
                if not args.dry_run and changes:
                    with open(json_file, "w", encoding="utf-8") as f:
                        json.dump(transformed, f, indent=2, ensure_ascii=False)
                        f.write("\n")  # Add trailing newline

            except json.JSONDecodeError as e:
                print(f"  ERROR: Failed to parse {json_file}: {e}")
                continue
            except Exception as e:
                print(f"  ERROR: Failed to process {json_file}: {e}")
                continue

        report["locales_processed"].append(locale_report)

        if locale_report["total_changes"] > 0:
            print(f"  {locale}: {locale_report['total_changes']} changes in {len([f for f in locale_report['files'] if f['changes'] > 0])} files")
        else:
            print(f"  {locale}: no changes")

    report["summary"]["total_conflicts_resolved"] = len(all_conflicts_resolved)

    # Step 4: Write report
    print(f"\nStep 4: Writing report to {report_path}...")
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # Summary
    print("\n" + "=" * 60)
    print("MIGRATION SUMMARY")
    print("=" * 60)
    print(f"Mode:                    {'DRY RUN (no files modified)' if args.dry_run else 'LIVE'}")
    print(f"Locales processed:       {len(report['locales_processed'])}")
    print(f"Files processed:         {report['summary']['total_files']}")
    print(f"Files with changes:      {report['summary']['files_with_changes']}")
    print(f"Total key changes:       {report['summary']['total_changes']}")
    print(f"Conflicts auto-resolved: {report['summary']['total_conflicts_resolved']}")
    print()

    if all_conflicts_resolved:
        print("CONFLICTS RESOLVED (camelCase duplicates deleted):")
        unique_conflicts = set()
        for conflict in all_conflicts_resolved:
            unique_conflicts.add(conflict['path'])
        for path in sorted(unique_conflicts)[:10]:
            print(f"  - {path}")
        if len(unique_conflicts) > 10:
            print(f"  ... and {len(unique_conflicts) - 10} more (see report)")
        print()

    if args.dry_run:
        print("To apply changes, run without --dry-run:")
        print(f"  python {Path(__file__).relative_to(project_root)}")
    else:
        print(f"Backup saved to: {backup_dir}")
        print(f"Report saved to: {report_path}")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
