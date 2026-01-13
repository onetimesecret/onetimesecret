#!/usr/bin/env python3
"""
Execute translation tasks for a locale using Claude.

Identifies pending tasks by comparing English source with historical JSON,
invokes Claude (or mock), and writes results to historical JSON files.

Three-tier architecture:
- locales/content/{locale}/*.json - Version-controlled source of truth (flat keys)
- src/locales/{locale}/*.json - Lean app-consumable files (nested JSON)
- locales/db/tasks.db - Ephemeral, hydrated on-demand for queries

Usage:
    python run_translation.py LOCALE [OPTIONS]

Examples:
    python run_translation.py eo --limit 10 --dry-run
    python run_translation.py eo --limit 20 --mock
    python run_translation.py eo --file auth.json --mock
"""

import argparse
import asyncio
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from utils import load_json_file, save_json_file, walk_keys

# SDK imports - optional, allows --mock fallback
try:
    from claude_agent_sdk import (
        AssistantMessage,
        ClaudeAgentOptions,
        ClaudeSDKError,
        query,
        ResultMessage,
        TextBlock,
    )
    HAS_SDK = True
except ImportError:
    HAS_SDK = False

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"
EN_DIR = SRC_LOCALES_DIR / "en"
CONTENT_DIR = LOCALES_DIR / "content"
GUIDES_DIR = LOCALES_DIR / "guides"
ANALYSIS_DIR = LOCALES_DIR / "analysis"


@dataclass
class TranslationTask:
    """A pending translation task."""

    file: str
    key: str
    english_text: str


def get_pending_tasks(
    locale: str,
    limit: Optional[int] = None,
    file_filter: Optional[str] = None,
) -> list[TranslationTask]:
    """Identify pending tasks by comparing English source with locale content.

    A key is pending if:
    - It exists in content/en/ source
    - AND either doesn't exist in locale content OR has empty/no 'text' field
    - AND is not marked as 'skip'

    Args:
        locale: Target locale code.
        limit: Maximum number of tasks to return.
        file_filter: Optional file name to filter by.

    Returns:
        List of TranslationTask objects.
    """
    en_content_dir = CONTENT_DIR / "en"
    if not en_content_dir.exists():
        raise FileNotFoundError(f"English content not found: {en_content_dir}")

    tasks: list[TranslationTask] = []
    locale_content_dir = CONTENT_DIR / locale

    # Get English content JSON files
    en_files = sorted(en_content_dir.glob("*.json"))
    if file_filter:
        en_files = [f for f in en_files if f.name == file_filter]

    for en_file in en_files:
        file_name = en_file.name
        locale_file = locale_content_dir / file_name

        # Get English keys from content
        en_content = load_json_file(en_file)

        # Get existing locale content (may be empty)
        locale_content = load_json_file(locale_file)

        for key, en_entry in en_content.items():
            if not isinstance(en_entry, dict):
                continue

            english_text = en_entry.get("text", "")
            locale_entry = locale_content.get(key, {})

            # Skip if already has text or marked skip
            if locale_entry.get("text") and not locale_entry.get("skip"):
                continue
            if locale_entry.get("skip"):
                continue

            tasks.append(TranslationTask(
                file=file_name,
                key=key,
                english_text=english_text,
            ))

            if limit and len(tasks) >= limit:
                return tasks

    return tasks


def load_guide(locale: str) -> Optional[str]:
    """Load the export guide for a locale."""
    guide_path = GUIDES_DIR / "exports" / f"{locale}.md"
    if guide_path.exists():
        return guide_path.read_text(encoding="utf-8")
    return None


def load_analysis(file_name: str) -> Optional[str]:
    """Load analysis for a domain file."""
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
        {"key": t.key, "english": t.english_text}
        for t in tasks
    ]

    prompt = f"""Translate these UI strings from English to {locale} for OneTime Secret.

## Rules
1. PRESERVE variables exactly: {{time}}, {{count}}, {{0}}, {{1}}, etc.
2. Keep HTML tags: <a>, <strong>, <br>
3. "secret" = culturally appropriate term for the locale
4. password (login credential) vs passphrase (protects secrets)

## Output Format
Return a JSON array with translations added:
[
  {{"key": "example_key", "english": "Hello", "translated": "Saluton"}},
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
                "key": task.key,
                "english": task.english_text,
                "translated": "",
                "skipped": True,
                "reason": "empty_source",
            })
            continue

        # Generate placeholder translation
        translated = f"[{locale.upper()}] {task.english_text}"

        results.append({
            "key": task.key,
            "english": task.english_text,
            "translated": translated,
        })

    return results


def extract_json_from_response(text: str) -> list[dict]:
    """Extract JSON array from Claude's response.

    Handles responses that may include markdown code blocks or extra text.

    Args:
        text: Raw response text from Claude.

    Returns:
        Parsed list of translation dicts.

    Raises:
        ValueError: If no valid JSON array can be extracted.
    """
    # Try direct parse first
    try:
        result = json.loads(text.strip())
        if isinstance(result, list):
            return result
    except json.JSONDecodeError:
        pass

    # Try extracting from markdown code block
    code_block = re.search(r"```(?:json)?\s*\n?(.*?)\n?```", text, re.DOTALL)
    if code_block:
        try:
            result = json.loads(code_block.group(1).strip())
            if isinstance(result, list):
                return result
        except json.JSONDecodeError:
            pass

    # Try finding JSON array pattern
    array_match = re.search(r"\[\s*\{.*\}\s*\]", text, re.DOTALL)
    if array_match:
        try:
            result = json.loads(array_match.group(0))
            if isinstance(result, list):
                return result
        except json.JSONDecodeError:
            pass

    raise ValueError(f"Could not extract JSON array from response: {text[:200]}...")


async def _invoke_claude_async(prompt: str, verbose: bool = False) -> list[dict]:
    """Async implementation of Claude invocation.

    Args:
        prompt: The translation prompt.
        verbose: Whether to show progress output.

    Returns:
        List of translation result dicts.

    Raises:
        RuntimeError: If SDK not available or Claude returns an error.
    """
    if not HAS_SDK:
        raise RuntimeError(
            "claude_agent_sdk not installed. Use --mock for testing, "
            "or install with: pip install claude-agent-sdk"
        )

    options = ClaudeAgentOptions(
        cwd=str(LOCALES_DIR),
        allowed_tools=["Read"],  # May read guide files
        max_turns=1,  # Single-turn translation task
    )

    content_parts: list[str] = []
    result_text = ""

    try:
        async for message in query(prompt=prompt, options=options):
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        content_parts.append(block.text)

            elif isinstance(message, ResultMessage):
                if verbose:
                    cost = getattr(message, "cost_usd", 0) or 0
                    duration = getattr(message, "duration_ms", 0) or 0
                    print(f"  Cost: ${cost:.4f}, duration: {duration}ms")

                if getattr(message, "is_error", False):
                    error_msg = getattr(message, "result", "Unknown error")
                    raise RuntimeError(f"Claude error: {error_msg}")

                result_text = getattr(message, "result", "") or ""

        # Use accumulated content if no result from ResultMessage
        if not result_text and content_parts:
            result_text = "".join(content_parts)

        if not result_text:
            raise RuntimeError("No response received from Claude")

        return extract_json_from_response(result_text)

    except ClaudeSDKError as e:
        raise RuntimeError(f"Claude SDK error: {e}") from e


def invoke_claude(prompt: str, locale: str, verbose: bool = False) -> list[dict]:
    """Invoke Claude to translate strings.

    Args:
        prompt: The translation prompt.
        locale: Target locale code (for error messages).
        verbose: Whether to show progress output.

    Returns:
        List of translation result dicts with keys: key, english, translated.

    Raises:
        RuntimeError: If Claude invocation fails.
    """
    try:
        return asyncio.run(_invoke_claude_async(prompt, verbose))
    except Exception as e:
        raise RuntimeError(f"Translation failed for {locale}: {e}") from e


def process_translations(
    locale: str,
    tasks: list[TranslationTask],
    translations: list[dict],
) -> dict[str, int]:
    """Process translation results and write to content JSON files.

    Args:
        locale: Target locale code.
        tasks: Original task list (for file mapping).
        translations: List of translation results from Claude/mock.

    Returns:
        Stats dict with counts.
    """
    stats = {"completed": 0, "skipped": 0, "errors": 0}

    # Build key-to-file mapping from tasks
    key_to_file: dict[str, str] = {t.key: t.file for t in tasks}

    # Group translations by file
    by_file: dict[str, list[dict]] = {}
    for t in translations:
        key = t["key"]
        file_name = key_to_file.get(key)
        if file_name:
            by_file.setdefault(file_name, []).append(t)

    content_dir = CONTENT_DIR / locale

    for file_name, file_translations in by_file.items():
        content_file = content_dir / file_name

        # Load existing content data
        content = load_json_file(content_file)

        for t in file_translations:
            key = t["key"]

            if t.get("skipped"):
                # Mark as skipped
                content[key] = {
                    "text": "",
                    "skip": True,
                    "note": t.get("reason", "skipped"),
                }
                stats["skipped"] += 1
            elif t.get("error"):
                # Record error but don't mark as translated
                content[key] = {
                    "text": "",
                    "note": f"error: {t.get('error')}",
                }
                stats["errors"] += 1
            elif t.get("translated"):
                # Successful translation
                content[key] = {"text": t["translated"]}
                stats["completed"] += 1
            else:
                # No translation returned
                content[key] = {
                    "text": "",
                    "note": "no_translation_returned",
                }
                stats["errors"] += 1

        # Save updated content file
        save_json_file(content_file, content)

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
            print(f"  {task.key}: {task.english_text[:50]}...")
        if len(tasks) > 5:
            print(f"  ... and {len(tasks) - 5} more")
        return 0

    # Load context
    guide = load_guide(args.locale)
    if guide:
        print(f"Loaded export guide for {args.locale}")

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
            translations = invoke_claude(prompt, args.locale, verbose=args.verbose)
        except RuntimeError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1

    # Process results
    print(f"Processing {len(translations)} translations...")
    stats = process_translations(args.locale, tasks, translations)

    print("\nResults:")
    print(f"  Completed: {stats['completed']}")
    print(f"  Skipped: {stats['skipped']}")
    print(f"  Errors: {stats['errors']}")

    if args.verbose and translations:
        print("\nSample translations:")
        for t in translations[:3]:
            if t.get("translated"):
                print(f"  {t['key']}: {t['translated'][:60]}...")

    output_dir = CONTENT_DIR / args.locale
    print(f"\nOutput: {output_dir}/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
