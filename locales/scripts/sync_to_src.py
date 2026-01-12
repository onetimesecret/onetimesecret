#!/usr/bin/env python3
"""
Sync completed translations from database to src/locales JSON files.

Reads completed translations from the database and writes them to
the appropriate JSON files in src/locales/{locale}/.

Usage:
    python sync_to_src.py LOCALE [OPTIONS]

Examples:
    python sync_to_src.py eo --dry-run
    python sync_to_src.py eo --file auth.json
    python sync_to_src.py eo
"""

import argparse
import json
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
DB_DIR = LOCALES_DIR / "db"
DB_FILE = DB_DIR / "tasks.db"
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"


@dataclass
class CompletedTask:
    """A completed translation task from the database."""

    id: int
    file: str
    key: str
    translation: str


def get_completed_translations(
    locale: str,
    file_filter: Optional[str] = None,
) -> list[CompletedTask]:
    """Query completed translations from the database.

    Args:
        locale: Target locale code.
        file_filter: Optional file name to filter by.

    Returns:
        List of CompletedTask objects.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python db.py hydrate' first."
        )

    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row

    query = """
        SELECT id, file, key, translation
        FROM translation_tasks
        WHERE locale = ? AND status = 'completed' AND translation IS NOT NULL
    """
    params: list = [locale]

    if file_filter:
        query += " AND file = ?"
        params.append(file_filter)

    query += " ORDER BY file, key"

    cursor = conn.cursor()
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    return [
        CompletedTask(
            id=row["id"],
            file=row["file"],
            key=row["key"],
            translation=row["translation"],
        )
        for row in rows
    ]


def set_nested_value(obj: dict, key_path: str, value: str) -> None:
    """Set a value in a nested dict using dot-notation key path.

    Args:
        obj: Dictionary to modify.
        key_path: Dot-notation path (e.g., 'web.COMMON.tagline').
        value: Value to set.
    """
    parts = key_path.split(".")
    current = obj

    # Navigate/create nested structure
    for part in parts[:-1]:
        if part not in current:
            current[part] = {}
        elif not isinstance(current[part], dict):
            # Key exists but is not a dict - overwrite
            current[part] = {}
        current = current[part]

    # Set the final value
    current[parts[-1]] = value


def load_json_file(file_path: Path) -> dict:
    """Load a JSON file, returning empty dict if not found."""
    if file_path.exists():
        try:
            with open(file_path, encoding="utf-8") as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"Warning: Invalid JSON in {file_path}: {e}", file=sys.stderr)
            return {}
    return {}


def save_json_file(file_path: Path, data: dict) -> None:
    """Save a dictionary to a JSON file with consistent formatting."""
    # Ensure parent directory exists
    file_path.parent.mkdir(parents=True, exist_ok=True)

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")  # Trailing newline


def sync_locale(
    locale: str,
    file_filter: Optional[str] = None,
    dry_run: bool = False,
    verbose: bool = False,
) -> dict[str, int]:
    """Sync completed translations to JSON files.

    Args:
        locale: Target locale code.
        file_filter: Optional file name to filter by.
        dry_run: If True, only report what would be done.
        verbose: If True, show detailed output.

    Returns:
        Stats dict with counts per file.
    """
    translations = get_completed_translations(locale, file_filter)

    if not translations:
        print(f"No completed translations found for '{locale}'")
        return {}

    # Group by file
    by_file: dict[str, list[CompletedTask]] = {}
    for task in translations:
        by_file.setdefault(task.file, []).append(task)

    locale_dir = SRC_LOCALES_DIR / locale
    stats: dict[str, int] = {}

    for file_name, tasks in sorted(by_file.items()):
        file_path = locale_dir / file_name
        stats[file_name] = len(tasks)

        if dry_run:
            print(f"\n[DRY-RUN] Would update {file_name} ({len(tasks)} keys)")
            if verbose:
                for task in tasks[:5]:
                    print(f"  {task.key}: {task.translation[:50]}...")
                if len(tasks) > 5:
                    print(f"  ... and {len(tasks) - 5} more")
            continue

        # Load existing file (or start fresh)
        data = load_json_file(file_path)

        # Apply translations
        for task in tasks:
            set_nested_value(data, task.key, task.translation)

        # Save
        save_json_file(file_path, data)
        print(f"Updated {file_path}: {len(tasks)} keys")

        if verbose:
            for task in tasks[:3]:
                print(f"  {task.key}: {task.translation[:40]}...")

    return stats


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Sync completed translations to JSON files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python sync_to_src.py eo --dry-run
    python sync_to_src.py eo --file auth.json
    python sync_to_src.py eo
        """,
    )

    parser.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    parser.add_argument(
        "--file",
        dest="file_filter",
        help="Only sync this file (e.g., 'auth.json')",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be synced without making changes",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    try:
        stats = sync_locale(
            locale=args.locale,
            file_filter=args.file_filter,
            dry_run=args.dry_run,
            verbose=args.verbose,
        )
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    if stats and not args.dry_run:
        total = sum(stats.values())
        print(f"\nSynced {total} translations across {len(stats)} files")

    return 0


if __name__ == "__main__":
    sys.exit(main())
