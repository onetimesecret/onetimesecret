# locales/scripts/i18n/commands/tasks.py

"""``tasks`` command group: the translation-task workflow.

Ported from the legacy ``locales/scripts/tasks/create.py``,
``locales/scripts/tasks/next.py``, ``locales/scripts/tasks/update.py`` and
``locales/scripts/migrate/export.py``. Behavior-preserving: flags, defaults,
exit codes and stdout/stderr formatting mirror the originals.

All path constants come from :mod:`i18n.config`; JSON helpers from
:mod:`i18n.io`; DB access through :func:`i18n.db.get_connection` (so the
``I18N_DB_FILE`` env override applies uniformly). The human task table is
rendered through :func:`i18n.console.render_table`, the one sanctioned
deviation point (see :mod:`i18n.console`); JSON output paths never route
through it and remain byte-identical to the legacy scripts.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from ..config import CONTENT_DIR, DB_FILE, EN_DIR
from ..console import render_table
from ..db import get_connection
from ..io import load_json_file, save_json_file, walk_keys

VALID_STATUSES = ("pending", "in_progress", "completed", "skipped")


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------
def register(subparsers) -> None:
    g = subparsers.add_parser("tasks", help="Translation task workflow")
    gsub = g.add_subparsers(dest="cmd", required=True)

    _register_create(gsub)
    _register_next(gsub)
    _register_update(gsub)
    _register_export(gsub)


def _register_create(gsub) -> None:
    c = gsub.add_parser(
        "create",
        help="Generate translation tasks for a target locale",
        description="Generate translation tasks by comparing locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python create.py fr_CA           # Generate tasks for Canadian French
    python create.py eo --dry-run    # Preview without writing
        """,
    )
    c.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'fr_CA', 'de')",
    )
    c.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without writing",
    )
    c.add_argument(
        "--missing-only",
        action="store_true",
        help=(
            "Enqueue only keys untranslated in content/<locale> (absent, or "
            "empty text without skip), skipping levels with no work. Catches a "
            "locale up to a grown English source without re-touching reviewed "
            "translations. Run once per locale (re-running rewrites keys_json)."
        ),
    )
    c.set_defaults(func=_create_handler)


def _register_next(gsub) -> None:
    c = gsub.add_parser(
        "next",
        help="Get the next pending translation task for a locale",
        description="Get the next pending translation task for a locale.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python next.py eo                    # Show next pending task
    python next.py eo --claim            # Claim task (mark in_progress)
    python next.py eo --json             # Output as JSON
    python next.py eo --file auth.json   # Filter by file
    python next.py eo --filter web.COMMON  # Filter by key path prefix
    python next.py eo --stats            # Show task statistics
    python next.py eo --id 42            # Get specific task by ID
        """,
    )
    c.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    c.add_argument(
        "--claim",
        action="store_true",
        help="Mark the task as in_progress (claim it)",
    )
    c.add_argument(
        "--file",
        dest="file_filter",
        help="Filter tasks by file name (e.g., 'auth.json')",
    )
    c.add_argument(
        "--filter",
        dest="path_filter",
        help="Filter tasks by key path prefix (e.g., 'web.COMMON')",
    )
    c.add_argument(
        "--json",
        "-j",
        action="store_true",
        help="Output as JSON",
    )
    c.add_argument(
        "--stats",
        action="store_true",
        help="Show task statistics instead of next task",
    )
    c.add_argument(
        "--id",
        type=int,
        dest="task_id",
        help="Get a specific task by ID",
    )
    c.set_defaults(func=_next_handler)


def _register_update(gsub) -> None:
    c = gsub.add_parser(
        "update",
        help="Update a translation task with translations",
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
    c.add_argument(
        "task_id",
        type=int,
        help="Task ID to update",
    )
    c.add_argument(
        "translations",
        nargs="?",
        help="JSON string of translations (key: translation pairs)",
    )
    c.add_argument(
        "--file",
        "-f",
        dest="translations_file",
        help="Read translations from JSON file instead of argument",
    )
    c.add_argument(
        "--status",
        "-s",
        choices=VALID_STATUSES,
        help="Set task status (default: completed when providing translations)",
    )
    c.add_argument(
        "--skip",
        action="store_true",
        help="Mark task as skipped (shortcut for --status skipped)",
    )
    c.add_argument(
        "--note",
        "-n",
        help="Add a note to the task",
    )
    c.add_argument(
        "--json",
        "-j",
        action="store_true",
        help="Output result as JSON",
    )
    c.add_argument(
        "--validate",
        action="store_true",
        help=(
            "Warn on key mismatches (missing/extra keys vs the source) before "
            "saving. ADVISORY ONLY: it prints warnings to stderr but still saves "
            "and still exits 0 — it does NOT block a bad write. Read the warnings "
            "and re-run with the corrected key set if any appear."
        ),
    )
    c.set_defaults(func=_update_handler)


def _register_export(gsub) -> None:
    c = gsub.add_parser(
        "export",
        help="Export completed translations from SQLite to content JSON",
        description="Export completed translations from SQLite to content JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python export.py eo --dry-run
    python export.py eo
    python export.py eo --file 00-common.json
        """,
    )
    c.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    c.add_argument(
        "--file",
        dest="file_filter",
        help="Only export this file (e.g., '_common.json')",
    )
    c.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be exported without making changes",
    )
    c.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose output",
    )
    c.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Quiet output (only errors)",
    )
    c.set_defaults(func=_export_handler)


# ---------------------------------------------------------------------------
# create (from tasks/create.py)
# ---------------------------------------------------------------------------
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
    """Extract the parent level from a full key path."""
    parts = key_path.rsplit(".", 1)
    return parts[0] if len(parts) > 1 else ""


def get_leaf_key(key_path: str) -> str:
    """Extract the leaf key name from a full key path."""
    parts = key_path.rsplit(".", 1)
    return parts[-1]


def group_keys_by_level(keys: dict[str, str]) -> dict[str, dict[str, str]]:
    """Group keys by their parent level."""
    levels: dict[str, dict[str, str]] = defaultdict(dict)
    for key_path, source in keys.items():
        level_path = get_parent_level(key_path)
        leaf_key = get_leaf_key(key_path)
        levels[level_path][leaf_key] = source
    return dict(levels)


def get_keys_from_file(file_path: Path) -> dict[str, str]:
    """Load a JSON file and return a dict of key_path -> value."""
    data = load_json_file(file_path)
    return dict(walk_keys(data))


def get_translated_keys(locale: str, file_name: str) -> set[str]:
    """Full key paths already handled for ``locale`` in ``file_name``.

    A target entry counts as handled when it carries a truthy ``skip`` flag or
    a non-empty ``text`` value. Used by ``create --missing-only`` to enqueue
    only the untranslated delta instead of the full English tree. Returns an
    empty set when the target file does not exist yet (everything is missing).
    """
    target = CONTENT_DIR / locale / file_name
    if not target.exists():
        return set()
    done: set[str] = set()
    for full_key, entry in load_json_file(target).items():
        if not isinstance(entry, dict):
            continue
        if entry.get("skip") or entry.get("text", "") != "":
            done.add(full_key)
    return done


def generate_tasks(
    locale: str,
    dry_run: bool = False,
    missing_only: bool = False,
) -> tuple[list[TranslationTask], dict[str, int]]:
    """Generate translation tasks from English source files.

    Default behaviour is target-blind: every English key becomes a task,
    regardless of the locale's existing translations. With ``missing_only``,
    each English file is filtered against ``content/<locale>`` so only
    untranslated keys (absent, or empty ``text`` without ``skip``) are
    enqueued; levels left with no work produce no row. This is the
    "translate the new strings only" path for catching a locale up to a grown
    English source without re-touching reviewed translations.
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

        # English keys, already excluding skip + underscore-meta entries.
        en_keys = get_keys_from_file(en_file)

        if missing_only:
            done = get_translated_keys(locale, file_name)
            en_keys = {k: v for k, v in en_keys.items() if k not in done}

        # A fully-translated (or empty) file contributes no tasks.
        if not en_keys:
            continue

        stats["total_files"] += 1
        stats["total_keys"] += len(en_keys)

        # Group keys by level
        levels = group_keys_by_level(en_keys)

        for level_path, keys_dict in sorted(levels.items()):
            stats["total_levels"] += 1

            if dry_run:
                print(
                    f"LEVEL: {file_name}:{level_path} ({len(keys_dict)} keys)"
                )

            tasks.append(
                TranslationTask(
                    file=file_name,
                    level_path=level_path,
                    locale=locale,
                    keys_json=json.dumps(keys_dict, ensure_ascii=False),
                )
            )

    return tasks, stats


def insert_tasks(tasks: list[TranslationTask]) -> int:
    """Insert translation tasks into the database.

    Upserts on (file, level_path, locale): inserts new levels, and for levels
    that already exist refreshes only keys_json + updated_at. It never touches
    status or translations_json, so in-flight / completed work is preserved.

    Returns:
        Count of inserted/updated rows.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python locales/scripts/store.py init' to create it first."
        )

    count = 0
    with get_connection() as conn:
        cursor = conn.cursor()
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
    return count


def _create_handler(args) -> int:
    mode = " (missing-only)" if args.missing_only else ""
    print(f"Generating translation tasks for '{args.locale}'{mode}")
    print()

    tasks, stats = generate_tasks(
        locale=args.locale,
        dry_run=args.dry_run,
        missing_only=args.missing_only,
    )

    print()
    print("Summary:")
    print(f"  Files: {stats['total_files']}")
    print(f"  Levels: {stats['total_levels']}")
    print(f"  Keys: {stats['total_keys']}")

    if args.dry_run:
        print()
        print("Dry run - no changes made.")
        return 0

    if not tasks:
        print()
        print("No tasks to generate.")
        return 0

    # Insert into database
    try:
        count = insert_tasks(tasks)
    except FileNotFoundError as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"\nInserted/updated {count} tasks into {DB_FILE}")
    return 0


# ---------------------------------------------------------------------------
# next (from tasks/next.py)
# ---------------------------------------------------------------------------
def get_next_task(
    locale: str,
    file_filter: Optional[str] = None,
    path_filter: Optional[str] = None,
    claim: bool = False,
) -> Optional[dict]:
    """Get the next pending task for a locale."""
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python locales/scripts/store.py init' to create it first."
        )

    with get_connection() as conn:
        cursor = conn.cursor()

        # Build query with optional filters
        query = """
            SELECT id, file, level_path, locale, status, keys_json,
                   translations_json, notes, created_at, updated_at
            FROM translation_tasks
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
                UPDATE translation_tasks
                SET status = 'in_progress', updated_at = datetime('now')
                WHERE id = ?
                """,
                (task["id"],),
            )
            conn.commit()
            task["status"] = "in_progress"

        return task


def get_task_by_id(task_id: int) -> Optional[dict]:
    """Get a specific task by ID."""
    if not DB_FILE.exists():
        raise FileNotFoundError(f"Database not found: {DB_FILE}")

    with get_connection() as conn:
        cursor = conn.cursor()
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

        if not row:
            return None

        task = dict(row)

        if task.get("keys_json"):
            task["keys"] = json.loads(task["keys_json"])
        if task.get("translations_json"):
            task["translations"] = json.loads(task["translations_json"])

        return task


def get_task_stats(locale: str) -> dict:
    """Get task statistics for a locale."""
    if not DB_FILE.exists():
        raise FileNotFoundError(f"Database not found: {DB_FILE}")

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT status, COUNT(*) as count
            FROM translation_tasks
            WHERE locale = ?
            GROUP BY status
            """,
            (locale,),
        )
        rows = cursor.fetchall()
        return {row[0]: row[1] for row in rows}


def format_task_human(task: dict) -> str:
    """Format a task for human-readable output.

    Returns:
        Formatted string with title line and key/english/translation table.
    """
    keys = task.get("keys", {})
    num_keys = len(keys)

    # Title line: Task # · file · path · key count
    title = f"**Task {task['id']}** · `{task['file']}` · `{task['level_path']}` · {num_keys} keys"

    # Sort by length of source text for visual grouping
    sorted_keys = sorted(keys.items(), key=lambda x: len(x[1]))

    translations = task.get("translations", {})
    rows = [
        [key, source_text, translations.get(key, "")]
        for key, source_text in sorted_keys
    ]

    table_str = render_table(
        ["Key", "English", task.get("locale") or "Translation"],
        rows,
        col_styles=["cyan", None, None],
        widths=[28, 60, 60],
    )

    lines = [title, "", table_str.rstrip()]

    if task.get("notes"):
        lines.append(f"\nNotes: {task['notes']}")

    return "\n".join(lines)


def _next_handler(args) -> int:
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


# ---------------------------------------------------------------------------
# update (from tasks/update.py)
# ---------------------------------------------------------------------------
def update_task(
    task_id: int,
    translations_json: Optional[str] = None,
    status: Optional[str] = None,
    notes: Optional[str] = None,
) -> dict:
    """Update a task with translations and/or status."""
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python locales/scripts/store.py init' to create it first."
        )

    if status and status not in VALID_STATUSES:
        raise ValueError(
            f"Invalid status: {status}. Must be one of: {VALID_STATUSES}"
        )

    with get_connection() as conn:
        cursor = conn.cursor()

        # Verify task exists
        cursor.execute(
            "SELECT * FROM translation_tasks WHERE id = ?", (task_id,)
        )
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

        query = (
            f"UPDATE translation_tasks SET {', '.join(updates)} WHERE id = ?"
        )
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


def validate_translations(keys_json: str, translations_json: str) -> list[str]:
    """Validate that translations match expected keys."""
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
        warnings.append(
            f"Missing translations for: {', '.join(sorted(missing))}"
        )
    if extra:
        warnings.append(f"Extra keys not in source: {', '.join(sorted(extra))}")

    return warnings


def _update_handler(args) -> int:
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
                print(
                    f"Error: File not found: {args.translations_file}",
                    file=sys.stderr,
                )
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
            task = get_task_by_id(args.task_id)
            if not task:
                print(f"Error: Task {args.task_id} not found", file=sys.stderr)
                return 1

            warnings = validate_translations(
                task["keys_json"], translations_json
            )
            if warnings:
                for warning in warnings:
                    print(f"Warning: {warning}", file=sys.stderr)
                # Advisory only: we warn but still save (exit 0). Callers must
                # read these warnings and re-submit with the correct keys.

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


# ---------------------------------------------------------------------------
# export (from migrate/export.py)
# ---------------------------------------------------------------------------
def get_completed_tasks(
    locale: str,
    file_filter: str | None = None,
) -> list[dict]:
    """Get all completed translation_tasks for a locale."""
    if not DB_FILE.exists():
        raise FileNotFoundError(f"Database not found: {DB_FILE}")

    with get_connection() as conn:
        cursor = conn.cursor()

        query = """
            SELECT file, level_path, keys_json, translations_json
            FROM translation_tasks
            WHERE locale = ? AND status = 'completed' AND translations_json IS NOT NULL
        """
        params: list = [locale]

        if file_filter:
            query += " AND file = ?"
            params.append(file_filter)

        query += " ORDER BY file, level_path"

        cursor.execute(query, params)
        return [dict(row) for row in cursor.fetchall()]


def export_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
    quiet: bool = False,
) -> dict[str, int]:
    """Export completed translations to content JSON files."""
    tasks = get_completed_tasks(locale, file_filter)

    if not tasks:
        if not quiet:
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
    content_dir = CONTENT_DIR / locale

    for file_name, file_tasks in sorted(by_file.items()):
        content_file = content_dir / file_name

        # Load existing content, or start a fresh file when the target locale
        # doesn't have this source file yet. export is the SQLite -> content
        # writer, so creating the missing file here (instead of skipping it) is
        # the correct way to mirror a newly added English file into a target
        # locale. source_hash watermarks are stamped afterward by add_hashes.py
        # (pnpm run locales:hashes), which only seeds files that already exist.
        is_new_file = not content_file.exists()
        content = {} if is_new_file else load_json_file(content_file)

        # Count keys to update
        key_count = 0

        for task in file_tasks:
            keys = json.loads(task["keys_json"])
            translations = json.loads(task["translations_json"])

            for key in keys:
                if key not in translations:
                    continue

                # Build full key path: level_path + key
                level_path = task["level_path"]
                full_key = f"{level_path}.{key}"

                translation = translations[key]

                # An empty/whitespace "translation" must never overwrite an
                # existing value or strip an intentional skip flag. This closes
                # the default (target-blind) create hazard where a locale's
                # already-skipped/translated key could be enqueued, "completed"
                # blank, and clobbered here. --missing-only never enqueues such
                # keys; this guards the default path too.
                if not (isinstance(translation, str) and translation.strip()):
                    continue

                if full_key in content:
                    # Update existing entry
                    content[full_key]["text"] = translation
                    # Remove skip flag if present (now has translation)
                    if "skip" in content[full_key]:
                        del content[full_key]["skip"]
                    if (
                        "note" in content[full_key]
                        and content[full_key]["note"] == "empty"
                    ):
                        del content[full_key]["note"]
                else:
                    # Create new entry
                    content[full_key] = {"text": translation}

                key_count += 1

        stats[file_name] = key_count

        verb = "create" if is_new_file else "update"

        if dry_run:
            if not quiet:
                print(
                    f"[DRY-RUN] Would {verb} {file_name}: {key_count} keys"
                )
                if verbose:
                    for task in file_tasks[:2]:
                        translations = json.loads(task["translations_json"])
                        sample = list(translations.items())[:2]
                        for k, v in sample:
                            print(f"  {task['level_path']}.{k}: {v[:40]}...")
        else:
            save_json_file(content_file, content)
            if not quiet:
                print(f"{verb.capitalize()}d {file_name}: {key_count} keys")

                if verbose:
                    for task in file_tasks[:2]:
                        translations = json.loads(task["translations_json"])
                        sample = list(translations.items())[:2]
                        for k, v in sample:
                            print(f"  {task['level_path']}.{k}: {v[:40]}...")

    return stats


def _export_handler(args) -> int:
    try:
        if not args.quiet:
            print(f"Exporting completed translations for '{args.locale}'")
            print(f"  From: {DB_FILE}")
            print(f"  To:   {CONTENT_DIR / args.locale}")
            print()

        stats = export_locale(
            locale=args.locale,
            file_filter=args.file_filter,
            dry_run=args.dry_run,
            verbose=args.verbose,
            quiet=args.quiet,
        )

        if stats:
            total = sum(stats.values())
            if not args.dry_run and not args.quiet:
                print(
                    f"\nExported {total} translations across {len(stats)} files"
                )
            return 0
        else:
            # No tasks exported - return non-zero for scripting
            return 2

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
