#!/usr/bin/env python3
"""
Generate translation tasks by comparing English source files with target locale.

Groups sibling keys by parent path (e.g., web.COMMON.buttons.submit and
web.COMMON.buttons.cancel become a single task for web.COMMON.buttons).
Each task contains all sibling keys as a JSON object for batch translation.

Usage:
    python create.py LOCALE [--dry-run]

Examples:
    python create.py fr_CA                # Generate tasks for Canadian French
    python create.py eo --dry-run         # Preview without writing
"""

import argparse
import json
import sqlite3
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

# Add parent scripts directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from keys import load_json_file, walk_keys

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent.parent  # tasks/ -> scripts/ -> locales/
CONTENT_DIR = LOCALES_DIR / "content"
EN_DIR = CONTENT_DIR / "en"
DB_DIR = LOCALES_DIR / "db"
DB_FILE = DB_DIR / "tasks.db"


@dataclass(frozen=True)
class TranslationTask:
    """Immutable record for a translation task.

    Groups sibling keys under a common parent path (level).
    For example, keys web.COMMON.buttons.submit and web.COMMON.buttons.cancel
    belong to level_path "web.COMMON.buttons".
    """

    file: str
    level_path: str
    locale: str
    keys_json: str  # JSON string: {"key_name": "English text", ...}


def get_parent_level(key_path: str) -> str:
    """Extract the parent level from a full key path.

    Args:
        key_path: Full dot-notation path (e.g., 'web.COMMON.buttons.submit')

    Returns:
        Parent level path (e.g., 'web.COMMON.buttons')
    """
    parts = key_path.rsplit(".", 1)
    return parts[0] if len(parts) > 1 else ""


def get_leaf_key(key_path: str) -> str:
    """Extract the leaf key name from a full key path.

    Args:
        key_path: Full dot-notation path (e.g., 'web.COMMON.buttons.submit')

    Returns:
        Leaf key name (e.g., 'submit')
    """
    parts = key_path.rsplit(".", 1)
    return parts[-1]


def group_keys_by_level(
    keys: dict[str, str]
) -> dict[str, dict[str, str]]:
    """Group keys by their parent level.

    Args:
        keys: Dictionary mapping full key paths to English text.

    Returns:
        Dictionary mapping level_path to {leaf_key: source}.
    """
    levels: dict[str, dict[str, str]] = defaultdict(dict)
    for key_path, source in keys.items():
        level_path = get_parent_level(key_path)
        leaf_key = get_leaf_key(key_path)
        levels[level_path][leaf_key] = source
    return dict(levels)


def get_keys_from_file(file_path: Path) -> dict[str, str]:
    """Load a JSON file and return a dict of key_path -> value.

    Args:
        file_path: Path to JSON file.

    Returns:
        Dictionary mapping dot-notation key paths to string values.
    """
    data = load_json_file(file_path)
    return dict(walk_keys(data))


def generate_tasks(
    locale: str,
    dry_run: bool = False,
) -> tuple[list[TranslationTask], dict[str, int]]:
    """Generate translation tasks from English source files.

    Groups keys by their parent level (e.g., web.COMMON.buttons) and
    creates one task per level per locale. Each task contains all sibling
    keys at that level as a JSON object.

    Args:
        locale: Target locale code (e.g., 'eo').
        dry_run: If True, only report what would be generated.

    Returns:
        Tuple of (list of TranslationTask records, stats dict).
    """
    if not EN_DIR.exists():
        print(f"Error: English directory not found: {EN_DIR}", file=sys.stderr)
        sys.exit(1)

    tasks: list[TranslationTask] = []
    stats = {
        "total_files": 0,
        "total_levels": 0,
        "total_keys": 0,
    }

    # Get all English JSON files
    en_files = sorted(EN_DIR.glob("*.json"))

    for en_file in en_files:
        file_name = en_file.name
        stats["total_files"] += 1

        # Get English keys
        en_keys = get_keys_from_file(en_file)
        stats["total_keys"] += len(en_keys)

        # Group keys by level
        levels = group_keys_by_level(en_keys)

        for level_path, keys_dict in sorted(levels.items()):
            stats["total_levels"] += 1

            if dry_run:
                print(f"LEVEL: {file_name}:{level_path} ({len(keys_dict)} keys)")

            tasks.append(TranslationTask(
                file=file_name,
                level_path=level_path,
                locale=locale,
                keys_json=json.dumps(keys_dict, ensure_ascii=False),
            ))

    return tasks, stats


def insert_tasks(tasks: list[TranslationTask]) -> tuple[sqlite3.Connection, int]:
    """Insert translation tasks into the database.

    Uses INSERT OR REPLACE to handle existing levels (updates them).

    Args:
        tasks: List of TranslationTask records to insert.

    Returns:
        Tuple of (connection, count of inserted/updated rows).
        Caller is responsible for closing the connection.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python store.py migrate' to create it first."
        )

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    count = 0

    for task in tasks:
        try:
            cursor.execute(
                """
                INSERT INTO translation_tasks (file, level_path, locale, keys_json)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(file, level_path, locale) DO UPDATE SET
                    keys_json = excluded.keys_json,
                    updated_at = datetime('now')
                """,
                (task.file, task.level_path, task.locale, task.keys_json),
            )
            count += 1
        except sqlite3.Error as e:
            print(f"Warning: SQL error: {e}", file=sys.stderr)

    conn.commit()
    return conn, count


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Generate translation tasks by comparing locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python create.py fr_CA           # Generate tasks for Canadian French
    python create.py eo --dry-run    # Preview without writing
        """,
    )

    parser.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'fr_CA', 'de')",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without writing",
    )

    args = parser.parse_args()

    print(f"Generating translation tasks for '{args.locale}'")
    print()

    tasks, stats = generate_tasks(
        locale=args.locale,
        dry_run=args.dry_run,
    )

    print()
    print("Summary:")
    print(f"  Files: {stats['total_files']}")
    print(f"  Levels: {stats['total_levels']}")
    print(f"  Keys: {stats['total_keys']}")

    if args.dry_run:
        print()
        print("Dry run - no changes made.")
        return

    if not tasks:
        print()
        print("No tasks to generate.")
        return

    # Insert into database
    try:
        conn, count = insert_tasks(tasks)
    except FileNotFoundError as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        print(f"\nInserted/updated {count} tasks into {DB_FILE}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
