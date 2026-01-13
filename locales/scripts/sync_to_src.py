#!/usr/bin/env python3
"""
Sync translations from content JSON to app-consumable JSON files.

Reads from locales/content/{locale}/*.json (flat keys with text field)
and writes to src/locales/{locale}/*.json (app format, nested JSON).

Three-tier architecture:
- locales/content/{locale}/*.json - Version-controlled source of truth (flat keys)
- src/locales/{locale}/*.json - Lean app-consumable files (nested JSON)
- locales/db/tasks.db - Ephemeral, hydrated on-demand for queries

Only keys with a 'text' field are synced. Keys marked 'skip' or
with empty text are excluded from app files.

Usage:
    python sync_to_src.py LOCALE [OPTIONS]
    python sync_to_src.py --all [OPTIONS]

Examples:
    python sync_to_src.py eo --dry-run
    python sync_to_src.py eo --file auth.json
    python sync_to_src.py eo
    python sync_to_src.py --all
    python sync_to_src.py eo --clobber  # Replace files instead of merging
"""

import argparse
import sys
from pathlib import Path
from typing import Any

from utils import (
    KeyPathConflictError,
    load_json_file,
    save_json_file,
    set_nested_value,
)

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
CONTENT_DIR = LOCALES_DIR / "content"
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"


def get_translations_from_content(content: dict[str, Any]) -> dict[str, str]:
    """Extract translations from content format.

    Only returns keys that have a non-empty 'text' field and no 'skip' flag.

    Args:
        content: Content format dict with flat keys.

    Returns:
        Dict mapping flat key paths to translation strings.
    """
    translations = {}

    for key, entry in content.items():
        if not isinstance(entry, dict):
            continue

        # Skip entries marked as skip
        if entry.get("skip"):
            continue

        # Only include keys with non-empty text
        text = entry.get("text", "")
        if text:
            translations[key] = text

    return translations


def sync_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
    clobber: bool = False,
) -> dict[str, int]:
    """Sync translations from content JSON to src/locales.

    Args:
        locale: Target locale code.
        file_filter: Optional file name to filter by.
        dry_run: If True, only report what would be done.
        verbose: If True, show detailed output.
        clobber: If True, replace target files entirely instead of merging.

    Returns:
        Stats dict with counts per file.
    """
    content_dir = CONTENT_DIR / locale
    target_dir = SRC_LOCALES_DIR / locale

    if not content_dir.exists():
        print(f"No content found for '{locale}'")
        print(f"  Expected: {content_dir}")
        return {}

    # Get content JSON files
    content_files = sorted(content_dir.glob("*.json"))
    if file_filter:
        content_files = [f for f in content_files if f.name == file_filter]

    if not content_files:
        print(f"No content files found in {content_dir}")
        return {}

    stats: dict[str, int] = {}

    for content_file in content_files:
        file_name = content_file.name
        target_file = target_dir / file_name

        # Load content data
        content = load_json_file(content_file)
        if not content:
            continue

        # Extract translations only
        translations = get_translations_from_content(content)
        if not translations:
            if verbose:
                print(f"  {file_name}: no translations yet")
            continue

        stats[file_name] = len(translations)

        if dry_run:
            print(f"\n[DRY-RUN] Would update {file_name} ({len(translations)} keys)")
            if verbose:
                sample = list(translations.items())[:5]
                for key, value in sample:
                    print(f"  {key}: {value[:50]}...")
                if len(translations) > 5:
                    print(f"  ... and {len(translations) - 5} more")
            continue

        # Load existing target file to preserve structure/metadata (unless clobber)
        target_data = {} if clobber else load_json_file(target_file)

        # Apply translations (converts flat keys to nested structure)
        for key, translation in translations.items():
            try:
                set_nested_value(target_data, key, translation, strict=True)
            except KeyPathConflictError as e:
                print(f"Error in {file_name}: {e}", file=sys.stderr)
                print("  This indicates conflicting key structures.", file=sys.stderr)
                print("  Fix the source data before syncing.", file=sys.stderr)
                return {}

        # Save
        save_json_file(target_file, target_data)
        print(f"Updated {target_file}: {len(translations)} keys")

        if verbose:
            sample = list(translations.items())[:3]
            for key, value in sample:
                print(f"  {key}: {value[:40]}...")

    return stats


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Sync translations from content JSON to src/locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python sync_to_src.py eo --dry-run
    python sync_to_src.py eo --file auth.json
    python sync_to_src.py eo
    python sync_to_src.py --all
    python sync_to_src.py --all --dry-run
    python sync_to_src.py eo --clobber       # Replace files instead of merging
        """,
    )

    parser.add_argument(
        "locale",
        nargs="?",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Sync all locales in content directory",
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
        "--clobber",
        action="store_true",
        help="Replace target files entirely instead of merging with existing",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    # Validate arguments
    if not args.locale and not args.all:
        parser.error("Either LOCALE or --all must be specified")
    if args.locale and args.all:
        parser.error("Cannot specify both LOCALE and --all")

    # Determine which locales to sync
    if args.all:
        locale_dirs = sorted([d.name for d in CONTENT_DIR.iterdir() if d.is_dir()])
        if not locale_dirs:
            print(f"No locale directories found in {CONTENT_DIR}")
            return 1
        print(f"Syncing {len(locale_dirs)} locales: {', '.join(locale_dirs[:5])}{'...' if len(locale_dirs) > 5 else ''}")
        print()
    else:
        locale_dirs = [args.locale]

    all_stats: dict[str, dict[str, int]] = {}

    for locale in locale_dirs:
        if args.all:
            print(f"\n{'='*60}")
            print(f"Locale: {locale}")
            print(f"{'='*60}")

        print(f"Syncing translations for '{locale}'")
        print(f"  From: {CONTENT_DIR / locale}")
        print(f"  To:   {SRC_LOCALES_DIR / locale}")
        print()

        stats = sync_locale(
            locale=locale,
            file_filter=args.file_filter,
            dry_run=args.dry_run,
            verbose=args.verbose,
            clobber=args.clobber,
        )

        if stats:
            all_stats[locale] = stats
            if not args.dry_run and not args.all:
                total = sum(stats.values())
                print(f"\nSynced {total} translations across {len(stats)} files")

    # Summary for --all mode
    if args.all and all_stats and not args.dry_run:
        print(f"\n{'='*60}")
        print("Summary")
        print(f"{'='*60}")
        grand_total = 0
        for locale, stats in sorted(all_stats.items()):
            locale_total = sum(stats.values())
            grand_total += locale_total
            print(f"  {locale}: {locale_total} keys across {len(stats)} files")
        print(f"{'='*60}")
        print(f"Total: {grand_total} keys across {len(all_stats)} locales")

    return 0


if __name__ == "__main__":
    sys.exit(main())
