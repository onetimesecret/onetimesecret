#!/usr/bin/env python3
"""
Add a field to all entries in locale content JSON files.

Inserts the field after "text" and before "content_hash"/"source_hash" for consistent
ordering. Entries that already have the field are skipped.

Usage:
    # Dry run (default)
    python3 locales/scripts/add_field.py --name renderer --value erb locales/content/*/email.json

    # Apply changes
    python3 locales/scripts/add_field.py --name renderer --value erb --apply locales/content/*/email.json

    # Null value (field present, value is null)
    python3 locales/scripts/add_field.py --name needs_review --apply locales/content/*/email.json
"""

import json
from pathlib import Path
from typing import Annotated

from cyclopts import App, Parameter

app = App(
    name="add_field",
    help="Add a field to all entries in locale content JSON files.",
)


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


@app.default
def main(
    *files: Annotated[Path, Parameter(help="Locale JSON files to process.")],
    name: Annotated[str, Parameter(help="Field name to add.")],
    value: Annotated[
        str | None,
        Parameter(help="Field value. Omit for null."),
    ] = None,
    apply: Annotated[
        bool,
        Parameter(help="Write changes. Default is dry run."),
    ] = False,
) -> None:
    """Add a named field to every entry in the given locale JSON files."""
    if not files:
        print("No files specified.")
        raise SystemExit(1)

    dry_run = not apply
    if dry_run:
        print("DRY RUN (use --apply to write changes)\n")

    total_modified = 0
    total_files = 0

    for path in files:
        if not path.exists():
            print(f"  {path}: not found, skipping")
            continue
        if not path.is_file():
            continue

        total_files += 1
        count = add_field_to_file(path, name, value, dry_run=dry_run)

        if count > 0:
            status = "would update" if dry_run else "updated"
            print(f"  {path}: {status} {count} entries")
        else:
            print(f"  {path}: no changes needed")

        total_modified += count

    label = "would modify" if dry_run else "modified"
    print(f"\nTotal: {label} {total_modified} entries across {total_files} files")


if __name__ == "__main__":
    app()
