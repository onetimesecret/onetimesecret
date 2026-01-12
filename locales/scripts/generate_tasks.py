#!/usr/bin/env python3
"""
Generate translation tasks by comparing English source files with target locale.

Detects:
1. Missing files (file exists in en/ but not in locale/)
2. Missing keys (key exists in en/ file but not in locale/ file)
3. Empty translations (key exists but value is empty string)

Usage:
    python generate_tasks.py LOCALE [--batch BATCH_NAME] [--dry-run]

Examples:
    python generate_tasks.py eo --batch 2026-01-12
    python generate_tasks.py eo --dry-run
"""

import argparse
import json
import sqlite3
import sys
from datetime import date
from pathlib import Path
from typing import Any, Iterator

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"
EN_DIR = SRC_LOCALES_DIR / "en"
DB_DIR = LOCALES_DIR / "db"
TASKS_FILE = DB_DIR / "tasks.sql"
DB_FILE = DB_DIR / "tasks.db"


def walk_keys(obj: dict[str, Any], prefix: str = "") -> Iterator[tuple[str, str]]:
    """Recursively walk a nested dict, yielding (key_path, value) tuples.

    Skips metadata keys (prefixed with '_').
    Only yields leaf string values.

    Args:
        obj: Dictionary to walk.
        prefix: Current key path prefix.

    Yields:
        Tuples of (full_key_path, string_value).
    """
    for key, value in obj.items():
        # Skip metadata keys
        if key.startswith("_"):
            continue

        full_key = f"{prefix}.{key}" if prefix else key

        if isinstance(value, dict):
            yield from walk_keys(value, full_key)
        elif isinstance(value, str):
            yield (full_key, value)
        # Skip non-string, non-dict values (arrays, numbers, etc.)


def get_keys_from_file(file_path: Path) -> dict[str, str]:
    """Load a JSON file and return a dict of key_path -> value.

    Args:
        file_path: Path to JSON file.

    Returns:
        Dictionary mapping dot-notation key paths to string values.
    """
    try:
        with open(file_path, encoding="utf-8") as f:
            data = json.load(f)
        return dict(walk_keys(data))
    except json.JSONDecodeError as e:
        print(f"Warning: Invalid JSON in {file_path}: {e}", file=sys.stderr)
        return {}
    except FileNotFoundError:
        return {}


def escape_sql_string(value: str) -> str:
    """Escape single quotes for SQL strings."""
    return value.replace("'", "''")


def generate_insert(
    batch: str,
    locale: str,
    file: str,
    key: str,
    english_text: str,
) -> str:
    """Generate an INSERT statement for a translation task."""
    return (
        f"INSERT INTO translation_tasks "
        f"(batch, locale, file, key, english_text) VALUES "
        f"('{escape_sql_string(batch)}', '{escape_sql_string(locale)}', "
        f"'{escape_sql_string(file)}', '{escape_sql_string(key)}', "
        f"'{escape_sql_string(english_text)}');"
    )


def compare_locale(
    locale: str,
    batch: str,
    dry_run: bool = False,
) -> tuple[list[str], dict[str, int]]:
    """Compare English source with target locale and generate tasks.

    Args:
        locale: Target locale code (e.g., 'eo').
        batch: Batch name for grouping tasks.
        dry_run: If True, only report what would be generated.

    Returns:
        Tuple of (list of INSERT statements, stats dict).
    """
    locale_dir = SRC_LOCALES_DIR / locale

    if not locale_dir.exists():
        print(f"Error: Locale directory not found: {locale_dir}", file=sys.stderr)
        sys.exit(1)

    if not EN_DIR.exists():
        print(f"Error: English directory not found: {EN_DIR}", file=sys.stderr)
        sys.exit(1)

    inserts: list[str] = []
    stats = {
        "missing_files": 0,
        "missing_keys": 0,
        "empty_translations": 0,
        "total_tasks": 0,
    }

    # Get all English JSON files
    en_files = sorted(EN_DIR.glob("*.json"))

    for en_file in en_files:
        file_name = en_file.name
        locale_file = locale_dir / file_name

        # Get English keys
        en_keys = get_keys_from_file(en_file)

        if not locale_file.exists():
            # Missing file - all keys are missing
            stats["missing_files"] += 1
            if dry_run:
                print(f"MISSING FILE: {file_name} ({len(en_keys)} keys)")

            for key, english_text in en_keys.items():
                inserts.append(generate_insert(
                    batch, locale, file_name, key, english_text
                ))
                stats["total_tasks"] += 1
        else:
            # File exists - compare keys
            locale_keys = get_keys_from_file(locale_file)

            for key, english_text in en_keys.items():
                if key not in locale_keys:
                    # Missing key
                    stats["missing_keys"] += 1
                    if dry_run:
                        print(f"MISSING KEY: {file_name}:{key}")
                    inserts.append(generate_insert(
                        batch, locale, file_name, key, english_text
                    ))
                    stats["total_tasks"] += 1
                elif locale_keys[key] == "":
                    # Empty translation
                    stats["empty_translations"] += 1
                    if dry_run:
                        print(f"EMPTY VALUE: {file_name}:{key}")
                    inserts.append(generate_insert(
                        batch, locale, file_name, key, english_text
                    ))
                    stats["total_tasks"] += 1

    return inserts, stats


def write_to_sql_file(inserts: list[str]) -> None:
    """Append INSERT statements to tasks.sql."""
    with open(TASKS_FILE, "a", encoding="utf-8") as f:
        f.write("\n")
        for stmt in inserts:
            f.write(stmt + "\n")


def insert_into_db(inserts: list[str]) -> int:
    """Insert tasks directly into database if it exists.

    Args:
        inserts: List of INSERT statements.

    Returns:
        Number of rows inserted.
    """
    if not DB_FILE.exists():
        return 0

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    inserted = 0

    for stmt in inserts:
        try:
            cursor.execute(stmt)
            inserted += 1
        except sqlite3.IntegrityError:
            # Duplicate key - skip silently (UNIQUE constraint)
            pass
        except sqlite3.Error as e:
            print(f"Warning: SQL error: {e}", file=sys.stderr)

    conn.commit()
    conn.close()
    return inserted


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Generate translation tasks by comparing locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python generate_tasks.py eo                    # Generate tasks for Esperanto
    python generate_tasks.py eo --batch 2026-01-12 # Custom batch name
    python generate_tasks.py eo --dry-run          # Preview without writing
        """,
    )

    parser.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'fr', 'de')",
    )
    parser.add_argument(
        "--batch",
        default=date.today().isoformat(),
        help="Batch name for grouping tasks (default: today's date)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without writing",
    )

    args = parser.parse_args()

    print(f"Comparing en/ with {args.locale}/")
    print(f"Batch: {args.batch}")
    print()

    inserts, stats = compare_locale(
        locale=args.locale,
        batch=args.batch,
        dry_run=args.dry_run,
    )

    print()
    print("Summary:")
    print(f"  Missing files: {stats['missing_files']}")
    print(f"  Missing keys: {stats['missing_keys']}")
    print(f"  Empty translations: {stats['empty_translations']}")
    print(f"  Total tasks: {stats['total_tasks']}")

    if args.dry_run:
        print()
        print("Dry run - no changes made.")
        return

    if not inserts:
        print()
        print("No tasks to generate.")
        return

    # Write to tasks.sql
    write_to_sql_file(inserts)
    print(f"\nAppended {len(inserts)} INSERT statements to {TASKS_FILE}")

    # Insert into database if it exists
    if DB_FILE.exists():
        inserted = insert_into_db(inserts)
        print(f"Inserted {inserted} rows into {DB_FILE}")
        if inserted < len(inserts):
            print(f"  ({len(inserts) - inserted} duplicates skipped)")
    else:
        print(f"Database not found ({DB_FILE}) - run 'python db.py hydrate' to create")


if __name__ == "__main__":
    main()
