#!/usr/bin/env python3
"""
Generate translation tasks by comparing English source files with target locale.

Supports two modes:
1. Key-based (legacy): One task per key - detects missing/empty keys
2. Level-based: Groups sibling keys by parent path (e.g., web.COMMON.buttons)

Key-based mode detects:
- Missing files (file exists in en/ but not in locale/)
- Missing keys (key exists in en/ file but not in locale/ file)
- Empty translations (key exists but value is empty string)

Level-based mode:
- Groups keys by parent level (e.g., web.COMMON.buttons.submit -> web.COMMON.buttons)
- Creates one task row per level per locale
- Stores keys_json as {key_name: source_text} for the level

Usage:
    python generate_tasks.py LOCALE [--batch BATCH_NAME] [--dry-run]
    python generate_tasks.py LOCALE --levels [--dry-run]

Examples:
    python generate_tasks.py eo --batch 2026-01-12          # Key-based tasks
    python generate_tasks.py eo --levels --dry-run          # Level-based preview
    python generate_tasks.py eo --levels                    # Level-based tasks
"""

import argparse
import json
import sqlite3
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Iterator

# Add parent scripts directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from keys import load_json_file, walk_keys

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent.parent  # tasks/ -> scripts/ -> locales/
CONTENT_DIR = LOCALES_DIR / "content"
EN_DIR = CONTENT_DIR / "en"
DB_DIR = LOCALES_DIR / "db"
TASKS_FILE = DB_DIR / "tasks.sql"
DB_FILE = DB_DIR / "tasks.db"


@dataclass(frozen=True)
class TaskData:
    """Immutable record for a translation task (key-based)."""

    batch: str
    locale: str
    file: str
    key: str
    source: str


@dataclass(frozen=True)
class LevelTask:
    """Immutable record for a level-based translation task.

    A level groups sibling keys under a common parent path.
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


def compare_locale(
    locale: str,
    batch: str,
    dry_run: bool = False,
) -> tuple[list[TaskData], dict[str, int]]:
    """Compare English source with target locale and generate tasks.

    Args:
        locale: Target locale code (e.g., 'eo').
        batch: Batch name for grouping tasks.
        dry_run: If True, only report what would be generated.

    Returns:
        Tuple of (list of TaskData records, stats dict).
    """
    locale_dir = CONTENT_DIR / locale

    if not locale_dir.exists():
        print(f"Error: Locale directory not found: {locale_dir}", file=sys.stderr)
        sys.exit(1)

    if not EN_DIR.exists():
        print(f"Error: English directory not found: {EN_DIR}", file=sys.stderr)
        sys.exit(1)

    tasks: list[TaskData] = []
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

            for key, source in en_keys.items():
                tasks.append(TaskData(
                    batch=batch,
                    locale=locale,
                    file=file_name,
                    key=key,
                    source=source,
                ))
                stats["total_tasks"] += 1
        else:
            # File exists - compare keys
            locale_keys = get_keys_from_file(locale_file)

            for key, source in en_keys.items():
                if key not in locale_keys:
                    # Missing key
                    stats["missing_keys"] += 1
                    if dry_run:
                        print(f"MISSING KEY: {file_name}:{key}")
                    tasks.append(TaskData(
                        batch=batch,
                        locale=locale,
                        file=file_name,
                        key=key,
                        source=source,
                    ))
                    stats["total_tasks"] += 1
                elif locale_keys[key] == "":
                    # Empty translation
                    stats["empty_translations"] += 1
                    if dry_run:
                        print(f"EMPTY VALUE: {file_name}:{key}")
                    tasks.append(TaskData(
                        batch=batch,
                        locale=locale,
                        file=file_name,
                        key=key,
                        source=source,
                    ))
                    stats["total_tasks"] += 1

    return tasks, stats


def generate_level_tasks(
    locale: str,
    dry_run: bool = False,
) -> tuple[list[LevelTask], dict[str, int]]:
    """Generate level-based translation tasks from English source files.

    Groups keys by their parent level (e.g., web.COMMON.buttons) and
    creates one task per level per locale. Each task contains all sibling
    keys at that level as a JSON object.

    Args:
        locale: Target locale code (e.g., 'eo').
        dry_run: If True, only report what would be generated.

    Returns:
        Tuple of (list of LevelTask records, stats dict).
    """
    if not EN_DIR.exists():
        print(f"Error: English directory not found: {EN_DIR}", file=sys.stderr)
        sys.exit(1)

    tasks: list[LevelTask] = []
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

            tasks.append(LevelTask(
                file=file_name,
                level_path=level_path,
                locale=locale,
                keys_json=json.dumps(keys_dict, ensure_ascii=False),
            ))

    return tasks, stats


def insert_level_tasks(tasks: list[LevelTask]) -> tuple[sqlite3.Connection, int]:
    """Insert level-based tasks into the database.

    Uses INSERT OR REPLACE to handle existing levels (updates them).

    Args:
        tasks: List of LevelTask records to insert.

    Returns:
        Tuple of (connection, count of inserted/updated rows).
        Caller is responsible for closing the connection.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python db.py hydrate' to create it first."
        )

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    count = 0

    for task in tasks:
        try:
            cursor.execute(
                """
                INSERT INTO level_tasks (file, level_path, locale, keys_json)
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


def export_tasks_to_sql(conn: sqlite3.Connection, task_ids: list[int]) -> list[str]:
    """Generate INSERT statements for SQL export.

    Fetches data using parameterized query, then formats SQL statements
    using SQLite's quote() for each value individually. This separates
    data retrieval from SQL generation for clarity and safety.

    Args:
        conn: Database connection.
        task_ids: List of task IDs to export.

    Returns:
        List of properly escaped INSERT statements.
    """
    if not task_ids:
        return []

    placeholders = ",".join("?" * len(task_ids))
    query = (
        "SELECT batch, locale, file, key, source "
        "FROM translation_tasks "
        f"WHERE id IN ({placeholders}) "
        "ORDER BY id"
    )

    statements = []
    for row in conn.execute(query, task_ids):
        # Use SQLite's quote() for each value individually
        quoted = [conn.execute("SELECT quote(?)", (v,)).fetchone()[0] for v in row]
        stmt = (
            "INSERT INTO translation_tasks "
            "(batch, locale, file, key, source) "
            f"VALUES ({', '.join(quoted)});"
        )
        statements.append(stmt)

    return statements


def append_to_sql_file(statements: list[str]) -> None:
    """Append SQL statements to tasks.sql."""
    if not statements:
        return
    with open(TASKS_FILE, "a", encoding="utf-8") as f:
        f.write("\n")
        for stmt in statements:
            f.write(stmt + "\n")


def insert_into_db(tasks: list[TaskData]) -> tuple[sqlite3.Connection, list[int]]:
    """Insert tasks directly into database using parameterized queries.

    Uses parameterized queries to prevent SQL injection and ensure
    proper escaping of all values.

    Args:
        tasks: List of TaskData records to insert.

    Returns:
        Tuple of (connection, list of inserted row IDs).
        Caller is responsible for closing the connection.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python db.py hydrate' to create it first."
        )

    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    inserted_ids: list[int] = []

    for task in tasks:
        try:
            cursor.execute(
                "INSERT INTO translation_tasks "
                "(batch, locale, file, key, source) VALUES (?, ?, ?, ?, ?)",
                (task.batch, task.locale, task.file, task.key, task.source),
            )
            if cursor.lastrowid is not None:
                inserted_ids.append(cursor.lastrowid)
        except sqlite3.IntegrityError:
            # Duplicate key - skip silently (UNIQUE constraint)
            pass
        except sqlite3.Error as e:
            print(f"Warning: SQL error: {e}", file=sys.stderr)

    conn.commit()
    return conn, inserted_ids


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Generate translation tasks by comparing locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python generate_tasks.py eo                    # Key-based tasks for Esperanto
    python generate_tasks.py eo --batch 2026-01-12 # Custom batch name
    python generate_tasks.py eo --dry-run          # Preview without writing
    python generate_tasks.py eo --levels           # Level-based tasks
    python generate_tasks.py eo --levels --dry-run # Level-based preview
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
        "--levels",
        action="store_true",
        help="Generate level-based tasks (group sibling keys by parent path)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without writing",
    )

    args = parser.parse_args()

    # Level-based mode
    if args.levels:
        print(f"Generating level-based tasks for '{args.locale}'")
        print()

        tasks, stats = generate_level_tasks(
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
            conn, count = insert_level_tasks(tasks)
        except FileNotFoundError as e:
            print(f"\nError: {e}", file=sys.stderr)
            sys.exit(1)

        try:
            print(f"\nInserted/updated {count} level tasks into {DB_FILE}")
        finally:
            conn.close()

        return

    # Key-based mode (legacy)
    print(f"Comparing en/ with {args.locale}/")
    print(f"Batch: {args.batch}")
    print()

    tasks, stats = compare_locale(
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

    if not tasks:
        print()
        print("No tasks to generate.")
        return

    # Database is required - insert first, then export to SQL file
    try:
        conn, inserted_ids = insert_into_db(tasks)
    except FileNotFoundError as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        print(f"\nInserted {len(inserted_ids)} rows into {DB_FILE}")
        if len(inserted_ids) < len(tasks):
            print(f"  ({len(tasks) - len(inserted_ids)} duplicates skipped)")

        # Export inserted tasks to SQL file using SQLite's quote() for proper escaping
        if inserted_ids:
            statements = export_tasks_to_sql(conn, inserted_ids)
            append_to_sql_file(statements)
            print(f"Appended {len(statements)} INSERT statements to {TASKS_FILE}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
