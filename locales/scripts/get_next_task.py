#!/usr/bin/env python3
"""
Get the next pending translation task for a locale.

Queries the level_tasks table for the next pending task and optionally
marks it as in_progress. Outputs task details for translation workflow.

Usage:
    python get_next_task.py LOCALE [OPTIONS]

Examples:
    python get_next_task.py eo                    # Show next pending task
    python get_next_task.py eo --claim            # Claim task (mark in_progress)
    python get_next_task.py eo --json             # Output as JSON
    python get_next_task.py eo --file auth.json   # Filter by file
"""

import argparse
import json
import sqlite3
import sys
from io import StringIO
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.table import Table

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
DB_DIR = LOCALES_DIR / "db"
DB_FILE = DB_DIR / "tasks.db"


def get_next_task(
    locale: str,
    file_filter: Optional[str] = None,
    path_filter: Optional[str] = None,
    claim: bool = False,
) -> Optional[dict]:
    """Get the next pending task for a locale.

    Args:
        locale: Target locale code (e.g., 'eo').
        file_filter: Optional file name to filter by.
        path_filter: Optional key path prefix to filter by (e.g., 'web.COMMON').
        claim: If True, mark the task as in_progress.

    Returns:
        Task dict with id, file, level_path, keys_json, etc., or None if no tasks.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python db.py hydrate' to create it first."
        )

    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row

    try:
        cursor = conn.cursor()

        # Build query with optional filters
        query = """
            SELECT id, file, level_path, locale, status, keys_json,
                   translations_json, notes, created_at, updated_at
            FROM level_tasks
            WHERE locale = ? AND status = 'pending'
        """
        params: list = [locale]

        if file_filter:
            query += " AND file = ?"
            params.append(file_filter)

        if path_filter:
            # Match paths that start with the filter or equal it exactly
            query += " AND (level_path = ? OR level_path LIKE ?)"
            params.append(path_filter)
            params.append(f"{path_filter}.%")

        query += " ORDER BY file, level_path LIMIT 1"

        cursor.execute(query, params)
        row = cursor.fetchone()

        if not row:
            return None

        task = dict(row)

        # Parse keys_json for convenience
        if task.get("keys_json"):
            task["keys"] = json.loads(task["keys_json"])

        # Parse translations_json if present
        if task.get("translations_json"):
            task["translations"] = json.loads(task["translations_json"])

        # Claim the task if requested
        if claim:
            cursor.execute(
                """
                UPDATE level_tasks
                SET status = 'in_progress', updated_at = datetime('now')
                WHERE id = ?
                """,
                (task["id"],),
            )
            conn.commit()
            task["status"] = "in_progress"

        return task

    finally:
        conn.close()


def get_task_by_id(task_id: int) -> Optional[dict]:
    """Get a specific task by ID.

    Args:
        task_id: The task ID.

    Returns:
        Task dict or None if not found.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(f"Database not found: {DB_FILE}")

    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row

    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT id, file, level_path, locale, status, keys_json,
                   translations_json, notes, created_at, updated_at
            FROM level_tasks
            WHERE id = ?
            """,
            (task_id,),
        )
        row = cursor.fetchone()

        if not row:
            return None

        task = dict(row)

        if task.get("keys_json"):
            task["keys"] = json.loads(task["keys_json"])
        if task.get("translations_json"):
            task["translations"] = json.loads(task["translations_json"])

        return task

    finally:
        conn.close()


def get_task_stats(locale: str) -> dict:
    """Get task statistics for a locale.

    Args:
        locale: Target locale code.

    Returns:
        Dict with counts by status.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(f"Database not found: {DB_FILE}")

    conn = sqlite3.connect(DB_FILE)

    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT status, COUNT(*) as count
            FROM level_tasks
            WHERE locale = ?
            GROUP BY status
            """,
            (locale,),
        )
        rows = cursor.fetchall()
        return {row[0]: row[1] for row in rows}

    finally:
        conn.close()


def format_task_human(task: dict) -> str:
    """Format a task for human-readable output with rich table.

    Args:
        task: Task dictionary.

    Returns:
        Formatted string with title line and key/english/translation table.
    """
    keys = task.get("keys", {})
    num_keys = len(keys)

    # Title line: Task # · file · path · key count
    title = f"**Task {task['id']}** · `{task['file']}` · `{task['level_path']}` · {num_keys} keys"

    # Build table with rich
    table = Table(show_header=True, header_style="bold", box=None, pad_edge=False)
    table.add_column("Key", justify="right", style="cyan", min_width=28)
    table.add_column("English", justify="left", width=60, overflow="fold")
    table.add_column("Esperanto", justify="left", width=60, overflow="fold")

    # Sort by length of english text for visual grouping
    sorted_keys = sorted(keys.items(), key=lambda x: len(x[1]))

    translations = task.get("translations", {})
    for key, english_text in sorted_keys:
        translation = translations.get(key, "")
        table.add_row(key, english_text, translation)

    # Render table to string
    output = StringIO()
    console = Console(file=output, force_terminal=False, width=160)
    console.print(table)
    table_str = output.getvalue()

    lines = [title, "", table_str.rstrip()]

    if task.get("notes"):
        lines.append(f"\nNotes: {task['notes']}")

    return "\n".join(lines)


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Get the next pending translation task for a locale.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python get_next_task.py eo                    # Show next pending task
    python get_next_task.py eo --claim            # Claim task (mark in_progress)
    python get_next_task.py eo --json             # Output as JSON
    python get_next_task.py eo --file auth.json   # Filter by file
    python get_next_task.py eo --filter web.COMMON  # Filter by key path prefix
    python get_next_task.py eo --stats            # Show task statistics
    python get_next_task.py eo --id 42            # Get specific task by ID
        """,
    )

    parser.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    parser.add_argument(
        "--claim",
        action="store_true",
        help="Mark the task as in_progress (claim it)",
    )
    parser.add_argument(
        "--file",
        dest="file_filter",
        help="Filter tasks by file name (e.g., 'auth.json')",
    )
    parser.add_argument(
        "--filter",
        dest="path_filter",
        help="Filter tasks by key path prefix (e.g., 'web.COMMON')",
    )
    parser.add_argument(
        "--json", "-j",
        action="store_true",
        help="Output as JSON",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show task statistics instead of next task",
    )
    parser.add_argument(
        "--id",
        type=int,
        dest="task_id",
        help="Get a specific task by ID",
    )

    args = parser.parse_args()

    try:
        # Stats mode
        if args.stats:
            stats = get_task_stats(args.locale)
            if args.json:
                print(json.dumps(stats, indent=2))
            else:
                print(f"Task statistics for '{args.locale}':")
                total = sum(stats.values())
                for status, count in sorted(stats.items()):
                    print(f"  {status}: {count}")
                print(f"  total: {total}")
            return 0

        # Get specific task by ID
        if args.task_id:
            task = get_task_by_id(args.task_id)
            if not task:
                print(f"Task {args.task_id} not found.", file=sys.stderr)
                return 1
            if args.json:
                print(json.dumps(task, indent=2, default=str))
            else:
                print(format_task_human(task))
            return 0

        # Get next pending task
        task = get_next_task(
            locale=args.locale,
            file_filter=args.file_filter,
            path_filter=args.path_filter,
            claim=args.claim,
        )

        if not task:
            if args.json:
                print(json.dumps({"message": "No pending tasks"}))
            else:
                print(f"No pending tasks for locale '{args.locale}'")
            return 0

        if args.json:
            print(json.dumps(task, indent=2, default=str))
        else:
            if args.claim:
                print("Claimed task:")
                print()
            print(format_task_human(task))

        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except sqlite3.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
