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
    python3 locales/scripts/i18n tasks create fr_CA            # Generate tasks for Canadian French
    python3 locales/scripts/i18n tasks create eo --dry-run     # Preview without writing
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
            "Enqueue keys untranslated in content/<locale> (absent, or empty "
            "text without skip) plus stale ones (translated, but the en source "
            "changed since), skipping levels with no work. Catches a "
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
    python3 locales/scripts/i18n tasks next eo                    # Show next pending task
    python3 locales/scripts/i18n tasks next eo --claim            # Claim task (mark in_progress)
    python3 locales/scripts/i18n tasks next eo --json             # Output as JSON
    python3 locales/scripts/i18n tasks next eo --file auth.json   # Filter by file
    python3 locales/scripts/i18n tasks next eo --filter web.COMMON  # Filter by key path prefix
    python3 locales/scripts/i18n tasks next eo --stats            # Show task statistics
    python3 locales/scripts/i18n tasks next eo --id 42            # Get specific task by ID
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
    python3 locales/scripts/i18n tasks update 42 '{"submit": "Sendi", "cancel": "Nuligi"}'
    python3 locales/scripts/i18n tasks update 42 --file translations.json --validate
    python3 locales/scripts/i18n tasks update 42 --skip --note "Not applicable"
    python3 locales/scripts/i18n tasks update 42 --status pending  # Reset to pending
    python3 locales/scripts/i18n tasks update 42 --status in_progress  # Mark as in progress
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
    python3 locales/scripts/i18n tasks export eo --dry-run
    python3 locales/scripts/i18n tasks export eo
    python3 locales/scripts/i18n tasks export eo --file 00-common.json
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
    # JSON string: {"key_name": "en content_hash", ...} — the en watermark each
    # leaf is being translated against, snapshotted now. export stamps these onto
    # the target's source_hash. None when no leaf in the level has a content_hash.
    source_hashes_json: str | None = None


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


def level_source_hashes(
    level_path: str, leaf_keys: dict[str, str], en_hashes: dict[str, str]
) -> dict[str, str]:
    """Map each leaf in a level to its en ``content_hash`` (the snapshot).

    Leaves whose en key has no ``content_hash`` (unhashed source) are omitted,
    so the result — and thus ``source_hashes_json`` — is empty rather than
    carrying null placeholders.
    """
    out: dict[str, str] = {}
    for leaf in leaf_keys:
        full_key = f"{level_path}.{leaf}" if level_path else leaf
        if full_key in en_hashes:
            out[leaf] = en_hashes[full_key]
    return out


def get_keys_from_file(file_path: Path) -> dict[str, str]:
    """Load a JSON file and return a dict of key_path -> value."""
    data = load_json_file(file_path)
    return dict(walk_keys(data))


def get_source_hashes_from_file(file_path: Path) -> dict[str, str]:
    """Full key path -> ``content_hash`` for translatable en keys in a file.

    Mirrors :func:`get_keys_from_file`'s skip/metadata filtering but reads the
    ``content_hash`` written by ``content hashes`` instead of the text. Keys
    without a ``content_hash`` (bare, not-yet-hashed source strings) are omitted
    — they carry no watermark to snapshot or compare against.
    """
    out: dict[str, str] = {}
    for full_key, entry in load_json_file(file_path).items():
        if full_key.startswith("_") or not isinstance(entry, dict):
            continue
        if entry.get("skip"):
            continue
        content_hash = entry.get("content_hash")
        if isinstance(content_hash, str) and content_hash:
            out[full_key] = content_hash
    return out


def get_target_entries(locale: str, file_name: str) -> dict[str, dict]:
    """Full key path -> entry dict for ``locale``'s copy of ``file_name``.

    Empty when the target file does not exist yet. Non-dict values are dropped
    so callers can read ``text``/``skip``/``source_hash`` without re-checking.
    """
    target = CONTENT_DIR / locale / file_name
    if not target.exists():
        return {}
    return {
        k: v
        for k, v in load_json_file(target).items()
        if isinstance(v, dict)
    }


def classify_key(entry: Optional[dict], en_hash: Optional[str]) -> str:
    """Classify one en key's state in a target locale.

    ``entry`` is the target's entry for the key (None if absent); ``en_hash`` is
    the key's current en ``content_hash`` (None if the source is unhashed).

    Returns one of:
      - ``"skipped"``  — target marked it skip (an intentional non-translation).
      - ``"missing"``  — absent, or empty text without a skip flag.
      - ``"stale"``    — translated, but its ``source_hash`` watermark no longer
                         matches en (English moved after translation). Requires a
                         present watermark AND a present en hash: an absent
                         watermark can't prove drift, so it reads as ``current``.
      - ``"current"``  — translated and the watermark still matches en.
    """
    if entry is not None and entry.get("skip"):
        return "skipped"
    if not (isinstance(entry, dict) and entry.get("text", "") != ""):
        return "missing"
    prev = entry.get("source_hash")
    if en_hash and isinstance(prev, str) and prev and prev != en_hash:
        return "stale"
    return "current"


def generate_tasks(
    locale: str,
    dry_run: bool = False,
    missing_only: bool = False,
) -> tuple[list[TranslationTask], dict[str, int]]:
    """Generate translation tasks from English source files.

    Default behaviour is target-blind: every English key becomes a task,
    regardless of the locale's existing translations. With ``missing_only``,
    each English file is filtered against ``content/<locale>`` so only keys that
    still need work are enqueued — **missing** (absent, or empty ``text`` without
    ``skip``) *and* **stale** (translated, but the target's ``source_hash``
    watermark no longer matches en's ``content_hash`` — English moved after the
    translation was made). Levels left with no work produce no row. This is the
    catch-up path for bringing a locale up to a grown *or edited* English source
    without re-touching still-current reviewed translations.

    Every generated task also snapshots the current en ``content_hash`` per leaf
    into ``source_hashes_json`` (both modes), so ``export`` can stamp the target
    ``source_hash`` with exactly what was translated against — the watermark that
    later marks the key stale if en changes again.
    """
    if not EN_DIR.exists():
        print(f"Error: English directory not found: {EN_DIR}", file=sys.stderr)
        sys.exit(1)

    tasks: list[TranslationTask] = []
    stats = {
        "total_files": 0,
        "total_levels": 0,
        "total_keys": 0,
        "missing_keys": 0,
        "stale_keys": 0,
    }

    # Get all English JSON files
    en_files = sorted(EN_DIR.glob("*.json"))

    for en_file in en_files:
        file_name = en_file.name

        # English keys, already excluding skip + underscore-meta entries.
        en_keys = get_keys_from_file(en_file)
        # Per-leaf en content_hash (skip/meta excluded); drives both the stale
        # filter and the snapshot stamped into each task row.
        en_hashes = get_source_hashes_from_file(en_file)

        if missing_only:
            target = get_target_entries(locale, file_name)
            kept: dict[str, str] = {}
            for full_key, text in en_keys.items():
                state = classify_key(target.get(full_key), en_hashes.get(full_key))
                if state == "missing":
                    kept[full_key] = text
                    stats["missing_keys"] += 1
                elif state == "stale":
                    kept[full_key] = text
                    stats["stale_keys"] += 1
                # "current"/"skipped" → leave the reviewed translation alone.
            en_keys = kept

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

            # Snapshot the en content_hash for each leaf in this level. Keys with
            # no en content_hash (unhashed source) are omitted; None when empty.
            level_hashes = level_source_hashes(level_path, keys_dict, en_hashes)
            source_hashes_json = (
                json.dumps(level_hashes, ensure_ascii=False)
                if level_hashes
                else None
            )

            tasks.append(
                TranslationTask(
                    file=file_name,
                    level_path=level_path,
                    locale=locale,
                    keys_json=json.dumps(keys_dict, ensure_ascii=False),
                    source_hashes_json=source_hashes_json,
                )
            )

    return tasks, stats


def insert_tasks(tasks: list[TranslationTask]) -> int:
    """Insert translation tasks into the database.

    Upserts on (file, level_path, locale): inserts new levels, and for levels
    that already exist refreshes keys_json + updated_at. It never touches status
    or translations_json, so in-flight / completed work is preserved.

    ``source_hashes_json`` is refreshed on conflict ONLY for non-completed rows.
    A completed row's snapshot is the en hash its translation was actually made
    against — the watermark export must stamp. Refreshing it to the current en
    hash on a re-run (after en drifted post-translation, pre-export) would make
    export stamp a hash newer than the translation, falsely marking a stale key
    current and hiding it forever. Freezing it on completed rows keeps the
    watermark truthful; the drifted key stays stale and a fresh-DB catch-up
    re-enqueues it.

    Returns:
        Count of inserted/updated rows.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python3 locales/scripts/i18n db init' to create it first."
        )

    count = 0
    with get_connection() as conn:
        cursor = conn.cursor()

        # Fail loud on a pre-schema-008 DB: the INSERT below names
        # source_hashes_json, and the per-row `except` further down would
        # otherwise swallow "no such column" on EVERY row and still exit 0 with
        # an empty queue. A fresh `db init` has the column; an old local tasks.db
        # needs `db migrate`.
        columns = {
            row[1]
            for row in cursor.execute("PRAGMA table_info(translation_tasks)")
        }
        if "source_hashes_json" not in columns:
            raise RuntimeError(
                "translation_tasks is missing the 'source_hashes_json' column "
                "(task DB predates schema 008). Run "
                "'python3 locales/scripts/i18n db migrate' first."
            )

        for task in tasks:
            try:
                cursor.execute(
                    """
                    INSERT INTO translation_tasks
                        (file, level_path, locale, keys_json, source_hashes_json)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(file, level_path, locale) DO UPDATE SET
                        keys_json = excluded.keys_json,
                        source_hashes_json = CASE
                            WHEN translation_tasks.status = 'completed'
                                THEN translation_tasks.source_hashes_json
                            ELSE excluded.source_hashes_json
                        END,
                        updated_at = datetime('now')
                    """,
                    (
                        task.file,
                        task.level_path,
                        task.locale,
                        task.keys_json,
                        task.source_hashes_json,
                    ),
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
    if args.missing_only:
        # In catch-up mode, break the enqueued keys into new vs re-translate.
        print(f"    missing (new/untranslated): {stats['missing_keys']}")
        print(f"    stale (en changed since):   {stats['stale_keys']}")

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
    except (FileNotFoundError, RuntimeError) as e:
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
            "Run 'python3 locales/scripts/i18n db init' to create it first."
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
        # Always report pending/completed, even at 0: every documented loop and
        # monitor condition is "stop when pending: 0", and GROUP BY alone drops
        # zero-count statuses so that line would otherwise never print.
        stats = {"pending": 0, "completed": 0}
        stats.update({row[0]: row[1] for row in rows})
        return stats


def compute_coverage(locale: str) -> dict[str, int]:
    """Content-truth coverage of ``locale`` against en, independent of the queue.

    For every translatable en key, classify the locale's current content entry
    (see :func:`classify_key`) into ``current`` / ``stale`` / ``missing`` /
    ``skipped``. This answers "how current is this locale" — which the task
    queue's ``0 pending`` cannot: a fully drained queue can still hide keys whose
    English moved after they were translated (``stale``) until the next
    ``tasks create --missing-only`` re-enqueues them.
    """
    counts = {"current": 0, "stale": 0, "missing": 0, "skipped": 0}
    if not EN_DIR.exists():
        return counts
    for en_file in sorted(EN_DIR.glob("*.json")):
        en_keys = get_keys_from_file(en_file)
        en_hashes = get_source_hashes_from_file(en_file)
        target = get_target_entries(locale, en_file.name)
        for full_key in en_keys:
            state = classify_key(target.get(full_key), en_hashes.get(full_key))
            counts[state] += 1
    return counts


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
                # Flat {status: count} — kept stable for machine consumers that
                # sum(values()) (e.g. export-and-commit.sh). Coverage is a nested
                # shape, so it stays out of --json to avoid breaking that sum.
                print(json.dumps(stats, indent=2))
            else:
                print(f"Task statistics for '{args.locale}':")
                total = sum(stats.values())
                for status, count in sorted(stats.items()):
                    print(f"  {status}: {count}")
                print(f"  total: {total}")

                # Content-truth coverage: the "am I current?" signal the queue
                # can't give. A drained queue (0 pending) can still show stale > 0.
                coverage = compute_coverage(args.locale)
                covered = coverage["current"] + coverage["stale"]
                denom = covered + coverage["missing"]
                print(f"\nCoverage (content/{args.locale} vs en):")
                print(f"  current: {coverage['current']}")
                print(f"  stale (en changed since translation): {coverage['stale']}")
                print(f"  missing (untranslated): {coverage['missing']}")
                print(f"  skipped: {coverage['skipped']}")
                if denom:
                    pct = covered / denom * 100
                    print(f"  translated: {covered}/{denom} ({pct:.1f}%)")
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
            "Run 'python3 locales/scripts/i18n db init' to create it first."
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
            SELECT file, level_path, keys_json, translations_json,
                   source_hashes_json
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
            # Per-leaf en content_hash snapshotted at create (empty for rows cut
            # before the column, or leaves whose en key had no content_hash).
            src_hashes = (
                json.loads(task["source_hashes_json"])
                if task["source_hashes_json"]
                else {}
            )

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

                # Stamp the watermark: the en content_hash this text was
                # translated against. Advances a stale key's source_hash to the
                # current en hash (clearing staleness) and gives freshly created
                # keys a truthful watermark immediately, instead of waiting for
                # `content hashes` to seed the CURRENT en hash — which would
                # mislabel a key as fresh if en drifted in the interim. Only when
                # we actually wrote text (past the blank guard) and have a hash.
                src_hash = src_hashes.get(key)
                if src_hash:
                    content[full_key]["source_hash"] = src_hash

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
