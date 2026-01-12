#!/usr/bin/env python3
"""
Sync translations from historical JSON to app-consumable JSON files.

Reads from locales/translations/{locale}/*.json (historical format, flat keys)
and writes to src/locales/{locale}/*.json (app format, nested JSON).

Three-tier architecture:
- locales/translations/{locale}/*.json - Historical source of truth (flat keys)
- src/locales/{locale}/*.json - Lean app-consumable files (nested JSON)
- locales/db/tasks.db - Ephemeral, hydrated on-demand for queries

Only keys with a 'translation' field are synced. Keys marked 'skip' or
pending (no translation) are excluded from app files.

Usage:
    python sync_to_src.py LOCALE [OPTIONS]

Examples:
    python sync_to_src.py eo --dry-run
    python sync_to_src.py eo --file auth.json
    python sync_to_src.py eo
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
TRANSLATIONS_DIR = LOCALES_DIR / "translations"
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"


def get_translations_from_historical(historical: dict[str, Any]) -> dict[str, str]:
    """Extract translations from historical format.

    Only returns keys that have a 'translation' field.
    Skips pending keys (only 'en') and skipped keys ('skip': true).

    Args:
        historical: Historical format dict with flat keys.

    Returns:
        Dict mapping flat key paths to translation strings.
    """
    translations = {}

    for key, entry in historical.items():
        if not isinstance(entry, dict):
            continue

        # Only include keys with actual translations
        if "translation" in entry:
            translations[key] = entry["translation"]

    return translations


def sync_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
) -> dict[str, int]:
    """Sync translations from historical JSON to src/locales.

    Args:
        locale: Target locale code.
        file_filter: Optional file name to filter by.
        dry_run: If True, only report what would be done.
        verbose: If True, show detailed output.

    Returns:
        Stats dict with counts per file.
    """
    translations_dir = TRANSLATIONS_DIR / locale
    target_dir = SRC_LOCALES_DIR / locale

    if not translations_dir.exists():
        print(f"No translations found for '{locale}'")
        print(f"  Expected: {translations_dir}")
        return {}

    # Get historical JSON files
    historical_files = sorted(translations_dir.glob("*.json"))
    if file_filter:
        historical_files = [f for f in historical_files if f.name == file_filter]

    if not historical_files:
        print(f"No translation files found in {translations_dir}")
        return {}

    stats: dict[str, int] = {}

    for historical_file in historical_files:
        file_name = historical_file.name
        target_file = target_dir / file_name

        # Load historical data
        historical = load_json_file(historical_file)
        if not historical:
            continue

        # Extract translations only
        translations = get_translations_from_historical(historical)
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

        # Load existing target file to preserve structure/metadata
        target_data = load_json_file(target_file)

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
        description="Sync translations from historical JSON to src/locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python sync_to_src.py eo --dry-run
    python sync_to_src.py eo --file auth.json
    python sync_to_src.py eo
        """,
    )

    parser.add_argument(
        "locale",
        help="Target locale code (e.g., 'eo', 'de')",
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
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    print(f"Syncing translations for '{args.locale}'")
    print(f"  From: {TRANSLATIONS_DIR / args.locale}")
    print(f"  To:   {SRC_LOCALES_DIR / args.locale}")
    print()

    stats = sync_locale(
        locale=args.locale,
        file_filter=args.file_filter,
        dry_run=args.dry_run,
        verbose=args.verbose,
    )

    if stats and not args.dry_run:
        total = sum(stats.values())
        print(f"\nSynced {total} translations across {len(stats)} files")

    return 0


if __name__ == "__main__":
    sys.exit(main())
