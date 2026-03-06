#!/usr/bin/env python3
"""
One-shot migration: rename "sha256" field in locale JSON files.

  - Source locale (default: en): "sha256" → "content_hash"
  - Translation locales: "sha256" → "source_hash"

Field ordering is preserved — the new field occupies the same position
as the old one. Hash values are unchanged; only the key name differs.

The source locale is determined by I18N_DEFAULT_LOCALE env var (default: "en").

Usage:
    python migrate_hash_fields.py              # Dry-run (default)
    python migrate_hash_fields.py --dry-run    # Same as above
    python migrate_hash_fields.py --apply      # Apply changes
"""

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
CONTENT_DIR = SCRIPT_DIR.parent / "content"
SOURCE_LOCALE = os.environ.get("I18N_DEFAULT_LOCALE", "en")


def rename_field_in_entry(entry: dict, old_name: str, new_name: str) -> dict:
    """Rename a field in a dict, preserving insertion order."""
    if old_name not in entry:
        return entry

    new_entry: dict = {}
    for k, v in entry.items():
        if k == old_name:
            new_entry[new_name] = v
        else:
            new_entry[k] = v
    return new_entry


def migrate_file(
    file_path: Path, old_field: str, new_field: str, *, dry_run: bool
) -> int:
    """Rename a field in all entries of a locale JSON file.

    Returns the number of entries modified.
    """
    with open(file_path, encoding="utf-8") as f:
        data = json.load(f)

    count = 0
    for key, entry in list(data.items()):
        if not isinstance(entry, dict):
            continue
        if old_field not in entry:
            continue

        data[key] = rename_field_in_entry(entry, old_field, new_field)
        count += 1

    if count > 0 and not dry_run:
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")

    return count


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Rename "sha256" field to "content_hash" (source) / "source_hash" (translations).'
    )
    parser.add_argument(
        "--apply", action="store_true", help="Write changes (default is dry-run)"
    )
    parser.add_argument(
        "--dry-run",
        "-n",
        action="store_true",
        default=True,
        help="Preview changes without writing (default)",
    )
    args = parser.parse_args()
    dry_run = not args.apply

    print(f"Source locale: {SOURCE_LOCALE}")
    print(f"Content dir:   {CONTENT_DIR}")
    print(f"Mode:          {'DRY RUN' if dry_run else 'APPLYING'}")
    print()

    if not CONTENT_DIR.exists():
        print(f"Error: content dir not found: {CONTENT_DIR}", file=sys.stderr)
        sys.exit(1)

    source_dir = CONTENT_DIR / SOURCE_LOCALE
    if not source_dir.exists():
        print(f"Error: source locale not found: {source_dir}", file=sys.stderr)
        sys.exit(1)

    # Phase 1: Source locale — sha256 → content_hash
    print(f"=== Source locale ({SOURCE_LOCALE}): sha256 → content_hash ===")
    source_total = 0
    for json_file in sorted(source_dir.glob("*.json")):
        count = migrate_file(json_file, "sha256", "content_hash", dry_run=dry_run)
        if count > 0:
            action = "would rename" if dry_run else "renamed"
            print(f"  {json_file.name}: {action} {count} entries")
        source_total += count
    print(f"  Total: {source_total} entries")

    # Phase 2: Translation locales — sha256 → source_hash
    print(f"\n=== Translation locales: sha256 → source_hash ===")
    translation_total = 0
    locale_dirs = sorted(
        d
        for d in CONTENT_DIR.iterdir()
        if d.is_dir() and d.name != SOURCE_LOCALE and not d.name.startswith(".")
    )

    for locale_dir in locale_dirs:
        locale_count = 0
        for json_file in sorted(locale_dir.glob("*.json")):
            count = migrate_file(json_file, "sha256", "source_hash", dry_run=dry_run)
            locale_count += count
        if locale_count > 0:
            action = "would rename" if dry_run else "renamed"
            print(f"  {locale_dir.name}: {action} {locale_count} entries")
        translation_total += locale_count
    print(f"  Total: {translation_total} entries")

    # Summary
    grand_total = source_total + translation_total
    print(f"\n{'Would rename' if dry_run else 'Renamed'} {grand_total} entries total.")
    if dry_run and grand_total > 0:
        print("Re-run with --apply to write changes.")


if __name__ == "__main__":
    main()
