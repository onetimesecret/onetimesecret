#!/usr/bin/env python3
"""
Execute translation tasks for a locale using Claude.

Queries pending tasks from DB, builds prompts with context,
invokes Claude (or mock), and updates task status.

Usage:
    python run_translation.py LOCALE [OPTIONS]

Examples:
    python run_translation.py eo --limit 10 --dry-run
    python run_translation.py eo --limit 20 --mock
    python run_translation.py eo --file auth.json --mock
"""

import argparse
import json
import sqlite3
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
DB_DIR = LOCALES_DIR / "db"
DB_FILE = DB_DIR / "tasks.db"
GUIDES_DIR = LOCALES_DIR / "guides"
ANALYSIS_DIR = LOCALES_DIR / "analysis"


@dataclass
class TranslationTask:
    """A pending translation task from the database."""

    id: int
    batch: str
    locale: str
    file: str
    key: str
    english_text: str


def get_pending_tasks(
    locale: str,
    limit: Optional[int] = None,
    file_filter: Optional[str] = None,
) -> list[TranslationTask]:
    """Query pending tasks from the database.

    Args:
        locale: Target locale code.
        limit: Maximum number of tasks to return.
        file_filter: Optional file name to filter by.

    Returns:
        List of TranslationTask objects.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python db.py hydrate' first."
        )

    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row

    query = """
        SELECT id, batch, locale, file, key, english_text
        FROM translation_tasks
        WHERE locale = ? AND status = 'pending'
    """
    params: list = [locale]

    if file_filter:
        query += " AND file = ?"
        params.append(file_filter)

    query += " ORDER BY file, id"

    if limit:
        query += " LIMIT ?"
        params.append(limit)

    cursor = conn.cursor()
    cursor.execute(query, params)
    rows = cursor.fetchall()
    conn.close()

    return [
        TranslationTask(
            id=row["id"],
            batch=row["batch"],
            locale=row["locale"],
            file=row["file"],
            key=row["key"],
            english_text=row["english_text"],
        )
        for row in rows
    ]


def load_guide(locale: str) -> Optional[str]:
    """Load the export guide for a locale."""
    guide_path = GUIDES_DIR / "exports" / f"{locale}.md"
    if guide_path.exists():
        return guide_path.read_text(encoding="utf-8")
    return None


def load_analysis(file_name: str) -> Optional[str]:
    """Load analysis for a domain file."""
    # Map file name to analysis file
    # e.g., auth.json -> auth.analysis.md
    base_name = file_name.replace(".json", "")
    analysis_path = ANALYSIS_DIR / f"{base_name}.analysis.md"
    if analysis_path.exists():
        return analysis_path.read_text(encoding="utf-8")
    return None


def build_prompt(
    locale: str,
    tasks: list[TranslationTask],
    guide: Optional[str],
    analysis: Optional[str],
) -> str:
    """Build a translation prompt for Claude.

    Args:
        locale: Target locale code.
        tasks: List of tasks to translate.
        guide: Optional export guide content.
        analysis: Optional domain analysis content.

    Returns:
        Formatted prompt string.
    """
    items = [
        {"id": t.id, "key": t.key, "english": t.english_text}
        for t in tasks
    ]

    prompt = f"""Translate these UI strings from English to {locale} for OneTime Secret.

## Rules
1. PRESERVE variables exactly: {{time}}, {{count}}, {{0}}, {{1}}, etc.
2. Keep HTML tags: <a>, <strong>, <br>
3. "secret" = culturally appropriate term for the locale
4. password (login credential) vs passphrase (protects secrets)

## Output Format
Return a JSON array with translations added. Include the id for each:
[
  {{"id": 1, "key": "example_key", "english": "Hello", "translated": "Saluton"}},
  ...
]

Return ONLY the JSON array, no markdown, no explanation.
"""

    if guide:
        prompt += f"\n## Translation Guide\n{guide[:2000]}...\n"

    if analysis:
        prompt += f"\n## Domain Context\n{analysis[:1000]}...\n"

    prompt += f"\n## Strings to Translate ({len(items)} items)\n"
    prompt += json.dumps(items, indent=2, ensure_ascii=False)

    return prompt


def mock_translate(tasks: list[TranslationTask], locale: str) -> list[dict]:
    """Generate mock translations for testing the workflow.

    Returns translations in the same format Claude would return.
    """
    results = []
    for task in tasks:
        # Skip empty English text
        if not task.english_text.strip():
            results.append({
                "id": task.id,
                "key": task.key,
                "english": task.english_text,
                "translated": "",
                "skipped": True,
                "reason": "empty_source",
            })
            continue

        # Generate placeholder translation
        # Format: [LOCALE] Original text
        translated = f"[{locale.upper()}] {task.english_text}"

        results.append({
            "id": task.id,
            "key": task.key,
            "english": task.english_text,
            "translated": translated,
        })

    return results


def invoke_claude(prompt: str, locale: str) -> list[dict]:
    """Invoke Claude to translate strings.

    TODO: Implement actual Claude invocation.
    For now, raises NotImplementedError.
    """
    raise NotImplementedError(
        "Claude invocation not yet implemented. Use --mock for testing."
    )


def update_task_status(
    task_id: int,
    status: str,
    translation: Optional[str] = None,
    notes: Optional[str] = None,
) -> None:
    """Update a task's status in the database.

    Args:
        task_id: Task ID to update.
        status: New status (completed, skipped, error).
        translation: Optional translation text.
        notes: Optional notes about the translation.
    """
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    if status == "completed":
        cursor.execute(
            """
            UPDATE translation_tasks
            SET status = ?, translation = ?, notes = ?,
                completed_at = datetime('now')
            WHERE id = ?
            """,
            (status, translation, notes, task_id),
        )
    else:
        cursor.execute(
            """
            UPDATE translation_tasks
            SET status = ?, notes = ?
            WHERE id = ?
            """,
            (status, notes, task_id),
        )

    conn.commit()
    conn.close()


def process_translations(translations: list[dict]) -> dict:
    """Process translation results and update database.

    Args:
        translations: List of translation results from Claude/mock.

    Returns:
        Stats dict with counts.
    """
    stats = {"completed": 0, "skipped": 0, "errors": 0}

    for t in translations:
        task_id = t["id"]

        if t.get("skipped"):
            update_task_status(
                task_id,
                status="skipped",
                notes=t.get("reason", "skipped"),
            )
            stats["skipped"] += 1
        elif t.get("error"):
            update_task_status(
                task_id,
                status="error",
                notes=t.get("error"),
            )
            stats["errors"] += 1
        elif t.get("translated"):
            update_task_status(
                task_id,
                status="completed",
                translation=t["translated"],
            )
            stats["completed"] += 1
        else:
            update_task_status(
                task_id,
                status="error",
                notes="no_translation_returned",
            )
            stats["errors"] += 1

    return stats


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Execute translation tasks for a locale.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python run_translation.py eo --limit 10 --dry-run
    python run_translation.py eo --limit 20 --mock
    python run_translation.py eo --file auth.json --mock
        """,
    )

    parser.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Maximum tasks to process (default: 10)",
    )
    parser.add_argument(
        "--file",
        dest="file_filter",
        help="Only process tasks for this file (e.g., 'auth.json')",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use mock translator instead of Claude",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be translated without making changes",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    # Get pending tasks
    try:
        tasks = get_pending_tasks(
            locale=args.locale,
            limit=args.limit,
            file_filter=args.file_filter,
        )
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    if not tasks:
        print(f"No pending tasks for locale '{args.locale}'")
        return 0

    print(f"Found {len(tasks)} pending tasks for '{args.locale}'")

    # Group by file for display
    by_file: dict[str, list[TranslationTask]] = {}
    for task in tasks:
        by_file.setdefault(task.file, []).append(task)

    for file_name, file_tasks in by_file.items():
        print(f"  {file_name}: {len(file_tasks)} tasks")

    if args.dry_run:
        print("\n[DRY-RUN] Would translate:")
        for task in tasks[:5]:
            print(f"  [{task.id}] {task.key}: {task.english_text[:50]}...")
        if len(tasks) > 5:
            print(f"  ... and {len(tasks) - 5} more")
        return 0

    # Load context
    guide = load_guide(args.locale)
    if guide:
        print(f"Loaded export guide for {args.locale}")

    # Get unique files for analysis loading
    files = set(t.file for t in tasks)

    # Build prompt (for logging/debugging)
    prompt = build_prompt(args.locale, tasks, guide, None)
    if args.verbose:
        print("\n--- Prompt Preview (first 500 chars) ---")
        print(prompt[:500])
        print("---\n")

    # Translate
    if args.mock:
        print("Using mock translator...")
        translations = mock_translate(tasks, args.locale)
    else:
        print("Invoking Claude...")
        try:
            translations = invoke_claude(prompt, args.locale)
        except NotImplementedError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1

    # Process results
    print(f"Processing {len(translations)} translations...")
    stats = process_translations(translations)

    print("\nResults:")
    print(f"  Completed: {stats['completed']}")
    print(f"  Skipped: {stats['skipped']}")
    print(f"  Errors: {stats['errors']}")

    if args.verbose and translations:
        print("\nSample translations:")
        for t in translations[:3]:
            if t.get("translated"):
                print(f"  {t['key']}: {t['translated'][:60]}...")

    return 0


if __name__ == "__main__":
    sys.exit(main())
