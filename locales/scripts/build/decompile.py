#!/usr/bin/env python3
"""
Sync translations from app-consumable JSON back to content JSON files.

Reads from src/locales/{locale}/*.json (app format, nested JSON)
and writes to locales/content/{locale}/*.json (flat keys with text field).

Three-tier architecture:
- src/locales/{locale}/*.json - Lean app-consumable files (nested JSON)
- locales/content/{locale}/*.json - Version-controlled source of truth (flat keys)
- locales/db/tasks.db - Ephemeral, hydrated on-demand for queries

This is the reverse of sync_to_src.py. Use this when you've edited
src/locales directly and need to propagate changes back to content files.

Existing metadata (context, skip, note) is preserved when updating keys.

IMPORTANT: Keys are NEVER removed from content files unless --remove is specified.
This protects the source of truth from accidental data loss.

Usage:
    python sync_from_src.py LOCALE [OPTIONS]
    python sync_from_src.py --all [OPTIONS]

Examples:
    python sync_from_src.py en --dry-run
    python sync_from_src.py en --file feature-organizations.json
    python sync_from_src.py en
    python sync_from_src.py --all
    python sync_from_src.py en --report-orphans
    python sync_from_src.py en --remove          # Also remove orphaned keys
"""

import argparse
import sys
from pathlib import Path

# Add parent scripts directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from keys import (
    load_json_file,
    save_json_file,
    walk_keys,
)

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent.parent  # build/ -> scripts/ -> locales/
CONTENT_DIR = LOCALES_DIR / "content"
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"


def sync_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
    report_orphans: bool = False,
    remove_orphans: bool = False,
) -> dict[str, dict[str, int]]:
    """Sync translations from src/locales to content JSON.

    Args:
        locale: Target locale code.
        file_filter: Optional file name to filter by.
        dry_run: If True, only report what would be done.
        verbose: If True, show detailed output.
        report_orphans: If True, report keys in content that don't exist in src.
        remove_orphans: If True, remove keys from content that don't exist in src.

    Returns:
        Stats dict with counts per file: {filename: {added: N, updated: N, removed: N, orphans: N}}
    """
    src_dir = SRC_LOCALES_DIR / locale
    content_dir = CONTENT_DIR / locale

    if not src_dir.exists():
        print(f"No source found for '{locale}'")
        print(f"  Expected: {src_dir}")
        return {}

    # Get source JSON files
    src_files = sorted(src_dir.glob("*.json"))
    if file_filter:
        src_files = [f for f in src_files if f.name == file_filter]

    if not src_files:
        print(f"No source files found in {src_dir}")
        return {}

    stats: dict[str, dict[str, int]] = {}

    for src_file in src_files:
        file_name = src_file.name
        content_file = content_dir / file_name

        # Load source data and flatten keys
        src_data = load_json_file(src_file)
        if not src_data:
            continue

        src_keys = dict(walk_keys(src_data))
        if not src_keys:
            if verbose:
                print(f"  {file_name}: no keys found")
            continue

        # Load existing content data
        content_data = load_json_file(content_file)

        # Track changes
        added = 0
        updated = 0
        unchanged = 0
        removed = 0
        orphans = []

        # Process each key from source
        for key_path, value in src_keys.items():
            if key_path in content_data:
                # Key exists - check if text changed
                existing = content_data[key_path]
                if isinstance(existing, dict):
                    if existing.get("text") != value:
                        if dry_run:
                            if verbose:
                                print(f"  [UPDATE] {key_path}")
                                print(
                                    f"    old: {existing.get('text', '')[:50]}..."
                                )
                                print(f"    new: {value[:50]}...")
                        # Preserve metadata, update text
                        existing["text"] = value
                        updated += 1
                    else:
                        unchanged += 1
                else:
                    # Malformed entry, replace it
                    content_data[key_path] = {"text": value}
                    updated += 1
            else:
                # New key
                content_data[key_path] = {"text": value}
                added += 1
                if dry_run and verbose:
                    print(f"  [ADD] {key_path}: {value[:50]}...")

        # Check for orphans (keys in content but not in src)
        if report_orphans or remove_orphans:
            for key_path in list(content_data.keys()):
                if key_path not in src_keys:
                    orphans.append(key_path)
                    if remove_orphans:
                        if dry_run and verbose:
                            print(f"  [REMOVE] {key_path}")
                        del content_data[key_path]
                        removed += 1

        stats[file_name] = {
            "added": added,
            "updated": updated,
            "unchanged": unchanged,
            "removed": removed,
            "orphans": len(orphans),
        }

        if dry_run:
            msg = f"\n[DRY-RUN] {file_name}: {added} new, {updated} updated, {unchanged} unchanged"
            if remove_orphans:
                msg += f", {removed} to remove"
            print(msg)
            if (report_orphans or remove_orphans) and orphans:
                print(f"  Orphaned keys ({len(orphans)}):")
                for key in orphans[:10]:
                    print(f"    - {key}")
                if len(orphans) > 10:
                    print(f"    ... and {len(orphans) - 10} more")
            continue

        # Only write if there are changes
        if added > 0 or updated > 0 or removed > 0:
            # Preserve original key order, don't re-sort
            # This minimizes diff noise when only adding/updating keys
            save_json_file(content_file, content_data)
            msg = f"Updated {content_file}: {added} added, {updated} updated"
            if removed > 0:
                msg += f", {removed} removed"
            print(msg)
        elif verbose:
            print(f"  {file_name}: no changes")

        if report_orphans and orphans:
            print(f"  Orphaned keys in {file_name} ({len(orphans)}):")
            for key in orphans[:10]:
                print(f"    - {key}")
            if len(orphans) > 10:
                print(f"    ... and {len(orphans) - 10} more")

    return stats


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Sync translations from src/locales to content JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python sync_from_src.py en --dry-run
    python sync_from_src.py en --file feature-organizations.json
    python sync_from_src.py en
    python sync_from_src.py --all
    python sync_from_src.py en --report-orphans
        """,
    )

    parser.add_argument(
        "locale",
        nargs="?",
        help="Target locale code (e.g., 'en', 'de')",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Sync all locales in src/locales directory",
    )
    parser.add_argument(
        "--file",
        dest="file_filter",
        help="Only sync this file (e.g., 'feature-organizations.json')",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be synced without making changes",
    )
    parser.add_argument(
        "--report-orphans",
        action="store_true",
        help="Report keys in content that don't exist in src",
    )
    parser.add_argument(
        "--remove",
        action="store_true",
        help="Remove keys from content that don't exist in src (dangerous)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
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
        locale_dirs = sorted(
            [d.name for d in SRC_LOCALES_DIR.iterdir() if d.is_dir()]
        )
        if not locale_dirs:
            print(f"No locale directories found in {SRC_LOCALES_DIR}")
            return 1
        print(
            f"Syncing {len(locale_dirs)} locales: {', '.join(locale_dirs[:5])}{'...' if len(locale_dirs) > 5 else ''}"
        )
        print()
    else:
        locale_dirs = [args.locale]

    all_stats: dict[str, dict[str, dict[str, int]]] = {}

    for locale in locale_dirs:
        if args.all:
            print(f"\n{'=' * 60}")
            print(f"Locale: {locale}")
            print(f"{'=' * 60}")

        print(f"Syncing translations for '{locale}'")
        print(f"  From: {SRC_LOCALES_DIR / locale}")
        print(f"  To:   {CONTENT_DIR / locale}")
        print()

        stats = sync_locale(
            locale=locale,
            file_filter=args.file_filter,
            dry_run=args.dry_run,
            verbose=args.verbose,
            report_orphans=args.report_orphans,
            remove_orphans=args.remove,
        )

        if stats:
            all_stats[locale] = stats
            if not args.dry_run and not args.all:
                total_added = sum(s["added"] for s in stats.values())
                total_updated = sum(s["updated"] for s in stats.values())
                print(
                    f"\nSynced {total_added} new, {total_updated} updated across {len(stats)} files"
                )

    # Summary for --all mode
    if args.all and all_stats and not args.dry_run:
        print(f"\n{'=' * 60}")
        print("Summary")
        print(f"{'=' * 60}")
        grand_added = 0
        grand_updated = 0
        for locale, file_stats in sorted(all_stats.items()):
            locale_added = sum(s["added"] for s in file_stats.values())
            locale_updated = sum(s["updated"] for s in file_stats.values())
            grand_added += locale_added
            grand_updated += locale_updated
            print(
                f"  {locale}: {locale_added} added, {locale_updated} updated across {len(file_stats)} files"
            )
        print(f"{'=' * 60}")
        print(
            f"Total: {grand_added} added, {grand_updated} updated across {len(all_stats)} locales"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
