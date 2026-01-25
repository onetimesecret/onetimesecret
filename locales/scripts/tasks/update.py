#!/usr/bin/env python3
"""
Update a translation task with translations.

Takes a task ID and translations JSON, updates the task in the database,
and marks it as completed.

Usage:
    python update.py TASK_ID TRANSLATIONS_JSON [OPTIONS]
    python update.py TASK_ID --file translations.json [OPTIONS]

Examples:
    python update.py 42 '{"submit": "Sendi", "cancel": "Nuligi"}'
    python update.py 42 --file translations.json
    python update.py 42 --skip --note "Not applicable"
    python update.py 42 --status pending  # Reset to pending
"""

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Optional

# Add parent scripts directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent.parent  # tasks/ -> scripts/ -> locales/
DB_DIR = LOCALES_DIR / "db"
DB_FILE = DB_DIR / "tasks.db"

VALID_STATUSES = ("pending", "in_progress", "completed", "skipped")


def update_task(
    task_id: int,
    translations_json: Optional[str] = None,
    status: Optional[str] = None,
    notes: Optional[str] = None,
) -> dict:
    """Update a task with translations and/or status.

    Args:
        task_id: The task ID to update.
        translations_json: JSON string of translations (key: translation pairs).
        status: New status (pending, in_progress, completed, skipped).
        notes: Optional notes to add.

    Returns:
        Updated task dict.

    Raises:
        FileNotFoundError: If database doesn't exist.
        ValueError: If task not found or invalid status.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python store.py migrate' to create it first."
        )

    if status and status not in VALID_STATUSES:
        raise ValueError(f"Invalid status: {status}. Must be one of: {VALID_STATUSES}")

    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row

    try:
        cursor = conn.cursor()

        # Verify task exists
        cursor.execute("SELECT * FROM translation_tasks WHERE id = ?", (task_id,))
        row = cursor.fetchone()
        if not row:
            raise ValueError(f"Task {task_id} not found")

        # Build update query dynamically
        updates = ["updated_at = datetime('now')"]
        params = []

        if translations_json is not None:
            # Validate JSON
            try:
                json.loads(translations_json)
            except json.JSONDecodeError as e:
                raise ValueError(f"Invalid translations JSON: {e}") from e

            updates.append("translations_json = ?")
            params.append(translations_json)

            # Auto-mark as completed if providing translations and no explicit status
            if status is None:
                status = "completed"

        if status is not None:
            updates.append("status = ?")
            params.append(status)

        if notes is not None:
            updates.append("notes = ?")
            params.append(notes)

        params.append(task_id)

        query = f"UPDATE translation_tasks SET {', '.join(updates)} WHERE id = ?"
        cursor.execute(query, params)
        conn.commit()

        # Fetch and return updated task
        cursor.execute(
            """
            SELECT id, file, level_path, locale, status, keys_json,
                   translations_json, notes, created_at, updated_at
            FROM translation_tasks
            WHERE id = ?
            """,
            (task_id,),
        )
        row = cursor.fetchone()
        task = dict(row)

        # Parse JSON fields
        if task.get("keys_json"):
            task["keys"] = json.loads(task["keys_json"])
        if task.get("translations_json"):
            task["translations"] = json.loads(task["translations_json"])

        return task

    finally:
        conn.close()


def validate_translations(keys_json: str, translations_json: str) -> list[str]:
    """Validate that translations match expected keys.

    Args:
        keys_json: JSON string of expected keys.
        translations_json: JSON string of provided translations.

    Returns:
        List of warning messages (empty if all good).
    """
    warnings = []

    try:
        keys = json.loads(keys_json)
        translations = json.loads(translations_json)
    except json.JSONDecodeError:
        return ["Invalid JSON"]

    expected_keys = set(keys.keys())
    provided_keys = set(translations.keys())

    missing = expected_keys - provided_keys
    extra = provided_keys - expected_keys

    if missing:
        warnings.append(f"Missing translations for: {', '.join(sorted(missing))}")
    if extra:
        warnings.append(f"Extra keys not in source: {', '.join(sorted(extra))}")

    return warnings


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Update a translation task with translations.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python update.py 42 '{"submit": "Sendi", "cancel": "Nuligi"}'
    python update.py 42 --file translations.json
    python update.py 42 --skip --note "Not applicable"
    python update.py 42 --status pending  # Reset to pending
    python update.py 42 --status in_progress  # Mark as in progress
        """,
    )

    parser.add_argument(
        "task_id",
        type=int,
        help="Task ID to update",
    )
    parser.add_argument(
        "translations",
        nargs="?",
        help="JSON string of translations (key: translation pairs)",
    )
    parser.add_argument(
        "--file", "-f",
        dest="translations_file",
        help="Read translations from JSON file instead of argument",
    )
    parser.add_argument(
        "--status", "-s",
        choices=VALID_STATUSES,
        help="Set task status (default: completed when providing translations)",
    )
    parser.add_argument(
        "--skip",
        action="store_true",
        help="Mark task as skipped (shortcut for --status skipped)",
    )
    parser.add_argument(
        "--note", "-n",
        help="Add a note to the task",
    )
    parser.add_argument(
        "--json", "-j",
        action="store_true",
        help="Output result as JSON",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate translations against expected keys before saving",
    )

    args = parser.parse_args()

    # Handle --skip shortcut
    status = args.status
    if args.skip:
        status = "skipped"

    # Get translations from argument or file
    translations_json = args.translations
    if args.translations_file:
        try:
            translations_path = Path(args.translations_file)
            if not translations_path.exists():
                print(f"Error: File not found: {args.translations_file}", file=sys.stderr)
                return 1
            translations_json = translations_path.read_text(encoding="utf-8")
        except Exception as e:
            print(f"Error reading file: {e}", file=sys.stderr)
            return 1

    # Require translations or status change
    if not translations_json and not status and not args.note:
        print(
            "Error: Must provide translations, --status, --skip, or --note",
            file=sys.stderr,
        )
        return 1

    try:
        # Validation if requested
        if args.validate and translations_json:
            # Need to fetch the task first to get keys_json
            from next import get_task_by_id

            task = get_task_by_id(args.task_id)
            if not task:
                print(f"Error: Task {args.task_id} not found", file=sys.stderr)
                return 1

            warnings = validate_translations(task["keys_json"], translations_json)
            if warnings:
                for warning in warnings:
                    print(f"Warning: {warning}", file=sys.stderr)
                # Continue anyway, but note the warnings

        # Update the task
        task = update_task(
            task_id=args.task_id,
            translations_json=translations_json,
            status=status,
            notes=args.note,
        )

        if args.json:
            print(json.dumps(task, indent=2, default=str))
        else:
            print(f"Updated task {args.task_id}:")
            print(f"  Status: {task['status']}")
            print(f"  File: {task['file']}")
            print(f"  Level: {task['level_path']}")
            if task.get("translations"):
                print(f"  Translations: {len(task['translations'])} keys")
            if task.get("notes"):
                print(f"  Notes: {task['notes']}")

        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except sqlite3.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
