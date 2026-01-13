#!/usr/bin/env python3
"""
Export completed translations from SQLite to historical JSON files.

Reads completed level_tasks from the database and writes translations
back to locales/translations/{locale}/*.json in historical format.

Historical format example:
{
  "web.COMMON.tagline": {
    "en": "Secure links that only work once",
    "translation": "Sekuraj ligiloj kiuj funkcias nur unufoje"
  }
}

Usage:
    python export_to_historical.py LOCALE [OPTIONS]

Examples:
    python export_to_historical.py eo --dry-run
    python export_to_historical.py eo
    python export_to_historical.py eo --file _common.json
"""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from utils import load_json_file, save_json_file

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
DB_DIR = LOCALES_DIR / "db"
DB_FILE = DB_DIR / "tasks.db"
TRANSLATIONS_DIR = LOCALES_DIR / "translations"


def get_completed_tasks(
    locale: str,
    file_filter: str | None = None,
) -> list[dict]:
    """Get all completed level_tasks for a locale.

    Args:
        locale: Target locale code.
        file_filter: Optional file name to filter by.

    Returns:
        List of task dicts with file, level_path, keys_json, translations_json.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(f"Database not found: {DB_FILE}")

    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row

    try:
        cursor = conn.cursor()

        query = """
            SELECT file, level_path, keys_json, translations_json
            FROM level_tasks
            WHERE locale = ? AND status = 'completed' AND translations_json IS NOT NULL
        """
        params: list = [locale]

        if file_filter:
            query += " AND file = ?"
            params.append(file_filter)

        query += " ORDER BY file, level_path"

        cursor.execute(query, params)
        return [dict(row) for row in cursor.fetchall()]

    finally:
        conn.close()


def export_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
) -> dict[str, int]:
    """Export completed translations to historical JSON files.

    Args:
        locale: Target locale code.
        file_filter: Optional file name to filter by.
        dry_run: If True, only report what would be done.
        verbose: If True, show detailed output.

    Returns:
        Stats dict with counts per file.
    """
    tasks = get_completed_tasks(locale, file_filter)

    if not tasks:
        print(f"No completed tasks to export for '{locale}'")
        return {}

    # Group tasks by file
    by_file: dict[str, list[dict]] = {}
    for task in tasks:
        file_name = task["file"]
        if file_name not in by_file:
            by_file[file_name] = []
        by_file[file_name].append(task)

    stats: dict[str, int] = {}
    translations_dir = TRANSLATIONS_DIR / locale

    for file_name, file_tasks in sorted(by_file.items()):
        historical_file = translations_dir / file_name

        if not historical_file.exists():
            print(f"Warning: Historical file not found: {historical_file}")
            continue

        # Load existing historical data
        historical = load_json_file(historical_file)

        # Count keys to update
        key_count = 0

        for task in file_tasks:
            keys = json.loads(task["keys_json"])
            translations = json.loads(task["translations_json"])

            for key, english in keys.items():
                if key not in translations:
                    continue

                # Build full key path: level_path + key
                level_path = task["level_path"]
                full_key = f"{level_path}.{key}"

                translation = translations[key]

                if full_key in historical:
                    # Update existing entry
                    historical[full_key]["translation"] = translation
                    # Remove skip flag if present
                    if "skip" in historical[full_key]:
                        del historical[full_key]["skip"]
                else:
                    # Create new entry
                    historical[full_key] = {
                        "en": english,
                        "translation": translation,
                    }

                key_count += 1

        stats[file_name] = key_count

        if dry_run:
            print(f"[DRY-RUN] Would update {file_name}: {key_count} keys")
            if verbose:
                for task in file_tasks[:2]:
                    translations = json.loads(task["translations_json"])
                    sample = list(translations.items())[:2]
                    for k, v in sample:
                        print(f"  {task['level_path']}.{k}: {v[:40]}...")
        else:
            save_json_file(historical_file, historical)
            print(f"Updated {file_name}: {key_count} keys")

            if verbose:
                for task in file_tasks[:2]:
                    translations = json.loads(task["translations_json"])
                    sample = list(translations.items())[:2]
                    for k, v in sample:
                        print(f"  {task['level_path']}.{k}: {v[:40]}...")

    return stats


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Export completed translations from SQLite to historical JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python export_to_historical.py eo --dry-run
    python export_to_historical.py eo
    python export_to_historical.py eo --file _common.json
        """,
    )

    parser.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    parser.add_argument(
        "--file",
        dest="file_filter",
        help="Only export this file (e.g., '_common.json')",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be exported without making changes",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    try:
        print(f"Exporting completed translations for '{args.locale}'")
        print(f"  From: {DB_FILE}")
        print(f"  To:   {TRANSLATIONS_DIR / args.locale}")
        print()

        stats = export_locale(
            locale=args.locale,
            file_filter=args.file_filter,
            dry_run=args.dry_run,
            verbose=args.verbose,
        )

        if stats and not args.dry_run:
            total = sum(stats.values())
            print(f"\nExported {total} translations across {len(stats)} files")

        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
