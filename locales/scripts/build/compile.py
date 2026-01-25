#!/usr/bin/env python3
"""
Sync translations from content JSON to app-consumable JSON files.

Reads from locales/content/{locale}/*.json (flat keys with text field)
and writes to generated/locales/{locale}.json (app format, nested JSON).

Two-tier architecture:
- locales/content/{locale}/*.json - Version-controlled source of truth (flat keys)
- generated/locales/{locale}.json - App-consumable merged JSON (nested, auto-generated)

Only keys with a 'text' field are synced. Keys marked 'skip' or
with empty text are excluded from app files.

Usage:
    python compile.py LOCALE [OPTIONS]
    python compile.py --all [OPTIONS]
    python compile.py --all --merged [OPTIONS]

Examples:
    python compile.py eo --dry-run
    python compile.py eo --file auth.json
    python compile.py eo
    python compile.py --all
    python compile.py eo --clobber  # Replace files instead of merging
    python compile.py --all --merged  # Output single merged JSON per locale
    python compile.py --all --merged --output-dir generated/locales
"""

import argparse
import sys
from pathlib import Path
from typing import Any

# Add parent scripts directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from keys import (
    KeyPathConflictError,
    load_json_file,
    save_json_file,
    set_nested_value,
)

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent.parent  # build/ -> scripts/ -> locales/
PROJECT_ROOT = LOCALES_DIR.parent
CONTENT_DIR = LOCALES_DIR / "content"
SRC_LOCALES_DIR = PROJECT_ROOT / "src" / "locales"
GENERATED_LOCALES_DIR = PROJECT_ROOT / "generated" / "locales"


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


def _is_metadata_key(key: str) -> bool:
    """Check if a key is metadata (has underscore-prefixed segment).

    Keys like '_meta', 'web.auth._guidance', or 'web.auth._guidance.context'
    are all metadata keys that should be excluded from translation counts.
    """
    return any(part.startswith("_") for part in key.split("."))


def _get_source_keys(locale_dir: Path) -> set[str]:
    """Get the set of valid translation keys for a locale.

    Returns keys that have non-empty 'text', no 'skip' flag, and are not
    metadata keys (no underscore-prefixed segments in the key path).

    Args:
        locale_dir: Path to locale content directory.

    Returns:
        Set of valid translation keys.
    """
    keys: set[str] = set()

    if not locale_dir.exists():
        return keys

    for content_file in locale_dir.glob("*.json"):
        content = load_json_file(content_file)
        if not content:
            continue

        for key, entry in content.items():
            if _is_metadata_key(key):
                continue
            if not isinstance(entry, dict):
                continue
            if entry.get("skip"):
                continue
            if entry.get("text", ""):
                keys.add(key)

    return keys


def sync_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
    clobber: bool = False,
) -> dict[str, int]:
    """Sync translations from content JSON to generated/locales.

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


def sync_locale_merged(
    locale: str,
    output_dir: Path,
    dry_run: bool = False,
    verbose: bool = False,
) -> int:
    """Sync all translations for a locale into a single merged JSON file.

    Reads all content files for the locale, extracts translations,
    converts flat keys to nested structure, and outputs a single
    {locale}.json file to the output directory.

    Args:
        locale: Target locale code.
        output_dir: Directory to write merged output file.
        dry_run: If True, only report what would be done.
        verbose: If True, show detailed output.

    Returns:
        Number of keys synced.
    """
    content_dir = CONTENT_DIR / locale

    if not content_dir.exists():
        if verbose:
            print(f"No content found for '{locale}'")
            print(f"  Expected: {content_dir}")
        return 0

    # Get all content JSON files
    content_files = sorted(content_dir.glob("*.json"))

    if not content_files:
        if verbose:
            print(f"No content files found in {content_dir}")
        return 0

    # Collect all translations from all files
    all_translations: dict[str, str] = {}

    for content_file in content_files:
        content = load_json_file(content_file)
        if not content:
            continue

        translations = get_translations_from_content(content)
        all_translations.update(translations)

        if verbose:
            print(f"  {content_file.name}: {len(translations)} keys")

    if not all_translations:
        if verbose:
            print(f"No translations found for '{locale}'")
        return 0

    if dry_run:
        print(f"\n[DRY-RUN] Would write {output_dir / f'{locale}.json'} ({len(all_translations)} keys)")
        if verbose:
            sample = list(all_translations.items())[:5]
            for key, value in sample:
                print(f"  {key}: {value[:50]}...")
            if len(all_translations) > 5:
                print(f"  ... and {len(all_translations) - 5} more")
        return len(all_translations)

    # Build nested structure from flat keys
    merged_data: dict[str, Any] = {}

    for key, translation in all_translations.items():
        try:
            set_nested_value(merged_data, key, translation, strict=True)
        except KeyPathConflictError as e:
            print(f"Error in {locale}: {e}", file=sys.stderr)
            print("  This indicates conflicting key structures.", file=sys.stderr)
            print("  Fix the source data before syncing.", file=sys.stderr)
            sys.exit(1)

    # Write merged output file
    output_file = output_dir / f"{locale}.json"
    save_json_file(output_file, merged_data)

    if verbose:
        print(f"Updated {output_file}: {len(all_translations)} keys")

    return len(all_translations)


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Sync translations from content JSON to generated/locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python compile.py eo --dry-run
    python compile.py eo --file auth.json
    python compile.py eo
    python compile.py --all
    python compile.py --all --dry-run
    python compile.py eo --clobber       # Replace files instead of merging
    python compile.py --all --merged     # Output single merged file per locale
    python compile.py --all --merged --output-dir generated/locales
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
    parser.add_argument(
        "--merged",
        action="store_true",
        help="Output single merged JSON file per locale (for backend consumption)",
    )
    parser.add_argument(
        "--output-dir",
        dest="output_dir",
        type=Path,
        default=GENERATED_LOCALES_DIR,
        help=f"Output directory for merged files (default: {GENERATED_LOCALES_DIR})",
    )

    args = parser.parse_args()

    # Validate arguments
    if not args.locale and not args.all:
        parser.error("Either LOCALE or --all must be specified")
    if args.locale and args.all:
        parser.error("Cannot specify both LOCALE and --all")
    if args.merged and args.file_filter:
        parser.error("Cannot use --file with --merged mode")
    if args.merged and args.clobber:
        parser.error("--clobber is not applicable in --merged mode")

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

    # Handle merged mode separately
    if args.merged:
        output_dir = args.output_dir
        if args.verbose:
            print(f"Output directory: {output_dir}")

        all_key_counts: dict[str, int] = {}
        default_locale = "en"  # Will be used for percentage calculation

        for locale in locale_dirs:
            if args.verbose:
                if args.all:
                    print(f"\n{'='*60}")
                    print(f"Locale: {locale}")
                    print(f"{'='*60}")

                print(f"Syncing translations for '{locale}' (merged mode)")
                print(f"  From: {CONTENT_DIR / locale}")
                print(f"  To:   {output_dir / f'{locale}.json'}")
                print()

            key_count = sync_locale_merged(
                locale=locale,
                output_dir=output_dir,
                dry_run=args.dry_run,
                verbose=args.verbose,
            )

            if key_count > 0:
                all_key_counts[locale] = key_count

        # Summary for merged mode
        if args.all and all_key_counts and not args.dry_run:
            # Build set of English source keys (excluding skip/empty)
            source_keys = _get_source_keys(CONTENT_DIR / default_locale)
            source_key_count = len(source_keys)

            # Calculate completion stats for each locale
            locale_stats: dict[str, tuple[int, int, bool]] = {}  # locale -> (translated, total, has_orphans)
            for locale in all_key_counts:
                locale_keys = _get_source_keys(CONTENT_DIR / locale)
                translated = len(source_keys & locale_keys)  # Keys in both source and locale
                has_orphans = bool(locale_keys - source_keys)  # Keys in locale but not in source
                locale_stats[locale] = (translated, all_key_counts[locale], has_orphans)

            # Sort by percentage descending (excluding source locale)
            other_locales = [(loc, stats) for loc, stats in locale_stats.items() if loc != default_locale]
            other_locales.sort(key=lambda x: x[1][0], reverse=True)

            print(f"\n{'='*60}")
            print(f"Locale sync complete ({len(all_key_counts)} locales)")
            print(f"{'='*60}")

            # Show source locale first
            if default_locale in locale_stats:
                translated, total, _ = locale_stats[default_locale]
                print(f"  {default_locale:8} {source_key_count:5} keys (100.0%)")
                print()

            # Show other locales sorted by completion percentage
            grand_total = sum(all_key_counts.values())
            for locale, (translated, total, has_orphans) in other_locales:
                if source_key_count > 0:
                    pct = (translated / source_key_count) * 100
                    pct_str = f"{pct:5.1f}%"
                else:
                    pct_str = "  N/A"
                marker = " *" if has_orphans else ""
                print(f"  {locale:8} {translated:5} keys ({pct_str}){marker}")

            print(f"{'='*60}")
            print(f"Total: {grand_total} keys  (* = has orphaned keys not in source)")

        return 0

    # Standard (non-merged) mode
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
