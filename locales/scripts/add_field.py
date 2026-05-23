#!/usr/bin/env python3
"""
Add a field to all entries in locale content JSON files.

Inserts the field after "text" and before "content_hash"/"source_hash" for
consistent ordering. Entries that already have the field are skipped.

Usage:
    # Dry run (default)
    python3 locales/scripts/add_field.py --name renderer --value erb \\
        locales/content/*/email.json

    # Apply changes
    python3 locales/scripts/add_field.py --name renderer --value erb --apply \\
        locales/content/*/email.json

    # Null value (field present, value is null)
    python3 locales/scripts/add_field.py --name needs_review --apply \\
        locales/content/*/email.json
"""

import argparse
import json
import sys
from pathlib import Path


def add_field_to_file(
    path: Path,
    name: str,
    value: object,
    *,
    dry_run: bool = True,
) -> int:
    """Add a field to all entries in a locale JSON file.

    Returns count of entries modified.
    """
    data = json.loads(path.read_text(encoding="utf-8"))
    modified = 0

    for key, entry in data.items():
        if not isinstance(entry, dict):
            continue
        if name in entry:
            continue

        # Insert after "text" for consistent ordering
        new_entry: dict[str, object] = {}
        inserted = False
        for k, v in entry.items():
            new_entry[k] = v
            if k == "text" and not inserted:
                new_entry[name] = value
                inserted = True
        if not inserted:
            new_entry[name] = value

        data[key] = new_entry
        modified += 1

    if modified > 0 and not dry_run:
        path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    return modified


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Add a named field to every entry in the given locale JSON files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "files",
        nargs="+",
        type=Path,
        help="Locale JSON files to process.",
    )
    parser.add_argument(
        "--name",
        required=True,
        help="Field name to add.",
    )
    parser.add_argument(
        "--value",
        default=None,
        help="Field value. Omit for null.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write changes. Default is dry run.",
    )

    args = parser.parse_args()

    dry_run = not args.apply
    if dry_run:
        print("DRY RUN (use --apply to write changes)\n")

    total_modified = 0
    total_files = 0

    for path in args.files:
        if not path.exists():
            print(f"  {path}: not found, skipping")
            continue
        if not path.is_file():
            continue

        total_files += 1
        count = add_field_to_file(path, args.name, args.value, dry_run=dry_run)

        if count > 0:
            status = "would update" if dry_run else "updated"
            print(f"  {path}: {status} {count} entries")
        else:
            print(f"  {path}: no changes needed")

        total_modified += count

    label = "would modify" if dry_run else "modified"
    print(f"\nTotal: {label} {total_modified} entries across {total_files} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
