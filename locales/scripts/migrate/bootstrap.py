#!/usr/bin/env python3
"""
Bootstrap locale content into versioned JSON format.

Reads source locale files from src/locales/{locale}/ and creates
content files in locales/content/{locale}/ for version control.

All locales use the same format, including English:
    {
      "web.COMMON.tagline": {
        "text": "Secure links that only work once"
      },
      "web.COMMON.broadcast": {
        "text": "",
        "skip": true,
        "note": "empty source"
      }
    }

For non-English locales, English text is NOT duplicated here.
It's looked up from content/en/ when generating tasks.

Usage:
    python bootstrap_translations.py LOCALE [--dry-run]
    python bootstrap_translations.py en --dry-run
    python bootstrap_translations.py --all

Examples:
    python bootstrap_translations.py en              # Bootstrap English
    python bootstrap_translations.py eo --dry-run   # Preview Esperanto
    python bootstrap_translations.py --all          # Bootstrap all locales
"""

import argparse
import sys
from pathlib import Path
from typing import Any

# Add parent scripts directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from keys import load_json_file, save_json_file, walk_keys

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent.parent  # migrate/ -> scripts/ -> locales/
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"
CONTENT_DIR = LOCALES_DIR / "content"


def get_keys_from_file(file_path: Path) -> dict[str, str]:
    """Load a JSON file and return a dict of key_path -> value.

    Args:
        file_path: Path to JSON file.

    Returns:
        Dictionary mapping dot-notation key paths to string values.
    """
    data = load_json_file(file_path)
    return dict(walk_keys(data))


def get_available_locales(include_english: bool = True) -> list[str]:
    """Get list of available locale codes.

    Args:
        include_english: If True, include 'en' in the list.

    Returns:
        Sorted list of locale codes.
    """
    if not SRC_LOCALES_DIR.exists():
        return []

    locales = []
    for path in sorted(SRC_LOCALES_DIR.iterdir()):
        if path.is_dir() and not path.name.startswith("."):
            if include_english or path.name != "en":
                locales.append(path.name)
    return locales


def build_content_entry(
    text: str,
    is_english: bool = False,
) -> dict[str, Any]:
    """Build a content entry for a single key.

    Args:
        text: The text value for this key.
        is_english: If True, this is an English source entry.

    Returns:
        Content entry dict with appropriate fields.
    """
    entry: dict[str, Any] = {"text": text}

    # Mark empty values as skip (applies to all locales)
    if text == "":
        entry["skip"] = True
        entry["note"] = "empty source" if is_english else "empty"

    return entry


def bootstrap_locale(
    locale: str,
    dry_run: bool = False,
) -> dict[str, dict[str, int]] | None:
    """Bootstrap content for a single locale.

    Args:
        locale: Target locale code (e.g., 'en', 'eo').
        dry_run: If True, only report what would be created.

    Returns:
        Stats dict with counts per file, or None on error.
    """
    locale_dir = SRC_LOCALES_DIR / locale
    output_dir = CONTENT_DIR / locale
    is_english = locale == "en"

    if not locale_dir.exists():
        print(
            f"Error: Locale directory not found: {locale_dir}", file=sys.stderr
        )
        return None

    stats: dict[str, dict[str, int]] = {}
    locale_files = sorted(locale_dir.glob("*.json"))

    for locale_file in locale_files:
        file_name = locale_file.name
        output_file = output_dir / file_name

        # Get keys from this locale's file
        keys = get_keys_from_file(locale_file)
        if not keys:
            continue

        # Build content data
        content: dict[str, dict[str, Any]] = {}
        file_stats = {
            "total": 0,
            "with_text": 0,
            "skipped": 0,
        }

        for key, text in keys.items():
            entry = build_content_entry(text, is_english=is_english)
            content[key] = entry

            file_stats["total"] += 1
            if entry.get("skip"):
                file_stats["skipped"] += 1
            else:
                file_stats["with_text"] += 1

        stats[file_name] = file_stats

        if dry_run:
            print(
                f"  [DRY-RUN] {file_name}: "
                f"{file_stats['with_text']} with text, "
                f"{file_stats['skipped']} skipped"
            )
        else:
            save_json_file(output_file, content)
            print(
                f"  {file_name}: "
                f"{file_stats['with_text']} with text, "
                f"{file_stats['skipped']} skipped"
            )

    return stats


def print_summary(all_stats: dict[str, dict[str, dict[str, int]]]) -> None:
    """Print summary of all processed locales."""
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)

    grand_total = {"total": 0, "with_text": 0, "skipped": 0}

    for locale, file_stats in sorted(all_stats.items()):
        locale_total = {"total": 0, "with_text": 0, "skipped": 0}
        for stats in file_stats.values():
            for key in locale_total:
                locale_total[key] += stats[key]
                grand_total[key] += stats[key]

        pct = (
            locale_total["with_text"] / locale_total["total"] * 100
            if locale_total["total"] > 0
            else 0
        )
        print(
            f"  {locale}: {locale_total['with_text']}/{locale_total['total']} "
            f"({pct:.1f}% with text)"
        )

    if len(all_stats) > 1:
        print("-" * 60)
        print(
            f"  Total: {grand_total['total']} keys across {len(all_stats)} locales"
        )


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Bootstrap locale content into versioned JSON format.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python bootstrap_translations.py en              # Bootstrap English
    python bootstrap_translations.py eo --dry-run   # Preview Esperanto
    python bootstrap_translations.py --all          # Bootstrap all locales
        """,
    )

    parser.add_argument(
        "locale",
        nargs="?",
        help="Target locale code (e.g., 'en', 'eo', 'fr_FR')",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Process all available locales (including English)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without writing files",
    )

    args = parser.parse_args()

    # Validate arguments
    if not args.locale and not args.all:
        parser.error("Must specify LOCALE or --all")

    if args.locale and args.all:
        parser.error("Cannot specify both LOCALE and --all")

    # Determine locales to process
    if args.all:
        locales = get_available_locales(include_english=True)
        if not locales:
            print("Error: No locales found in src/locales/", file=sys.stderr)
            return 1
        print(f"Processing {len(locales)} locales: {', '.join(locales)}")
    else:
        locales = [args.locale]

    if args.dry_run:
        print("[DRY-RUN MODE]")
    print()

    # Process each locale
    all_stats: dict[str, dict[str, dict[str, int]]] = {}
    errors = 0

    for locale in locales:
        print(f"Bootstrapping {locale}/")
        stats = bootstrap_locale(locale, dry_run=args.dry_run)
        if stats is None:
            errors += 1
        elif stats:
            all_stats[locale] = stats
        print()

    # Print summary
    if all_stats:
        print_summary(all_stats)

        if not args.dry_run:
            print(f"\nOutput directory: {CONTENT_DIR}")

    # Return error code if any locales failed
    if errors > 0:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
