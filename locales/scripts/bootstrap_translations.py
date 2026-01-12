#!/usr/bin/env python3
"""
Bootstrap existing translations into the new historical JSON format.

Reads English source files and existing locale translations, then creates
historical JSON files that serve as the source of truth for translations.

The historical format includes the English text at translation time (for
staleness detection) and metadata about skipped keys.

Usage:
    python bootstrap_translations.py LOCALE [--dry-run]
    python bootstrap_translations.py eo --dry-run
    python bootstrap_translations.py --all

Output format (locales/translations/{locale}/{file}.json):
    {
      "web.COMMON.tagline": {
        "en": "Secure links that only work once",
        "translation": "Sekuraj ligiloj..."
      },
      "web.COMMON.broadcast": {
        "en": "",
        "skip": true,
        "note": "empty source"
      }
    }
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterator

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"
EN_DIR = SRC_LOCALES_DIR / "en"
TRANSLATIONS_DIR = LOCALES_DIR / "translations"


def walk_keys(obj: dict[str, Any], prefix: str = "") -> Iterator[tuple[str, str]]:
    """Recursively walk a nested dict, yielding (key_path, value) tuples.

    Skips metadata keys (prefixed with '_').
    Only yields leaf string values.

    Args:
        obj: Dictionary to walk.
        prefix: Current key path prefix.

    Yields:
        Tuples of (full_key_path, string_value).
    """
    for key, value in obj.items():
        # Skip metadata keys
        if key.startswith("_"):
            continue

        full_key = f"{prefix}.{key}" if prefix else key

        if isinstance(value, dict):
            yield from walk_keys(value, full_key)
        elif isinstance(value, str):
            yield (full_key, value)
        # Skip non-string, non-dict values (arrays, numbers, etc.)


def get_keys_from_file(file_path: Path) -> dict[str, str]:
    """Load a JSON file and return a dict of key_path -> value.

    Args:
        file_path: Path to JSON file.

    Returns:
        Dictionary mapping dot-notation key paths to string values.
    """
    try:
        with open(file_path, encoding="utf-8") as f:
            data = json.load(f)
        return dict(walk_keys(data))
    except json.JSONDecodeError as e:
        print(f"Warning: Invalid JSON in {file_path}: {e}", file=sys.stderr)
        return {}
    except FileNotFoundError:
        return {}


def save_json_file(file_path: Path, data: dict) -> None:
    """Save a dictionary to a JSON file with consistent formatting."""
    file_path.parent.mkdir(parents=True, exist_ok=True)

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def get_available_locales() -> list[str]:
    """Get list of available locale codes (excluding 'en')."""
    if not SRC_LOCALES_DIR.exists():
        return []

    locales = []
    for path in sorted(SRC_LOCALES_DIR.iterdir()):
        if path.is_dir() and path.name != "en" and not path.name.startswith("."):
            locales.append(path.name)
    return locales


def build_historical_entry(
    en_text: str,
    locale_text: str | None,
) -> dict[str, Any]:
    """Build a historical entry for a single key.

    Args:
        en_text: English source text.
        locale_text: Translated text (None if missing).

    Returns:
        Historical entry dict with appropriate fields.
    """
    entry: dict[str, Any] = {"en": en_text}

    if en_text == "":
        # Empty English source - mark as skip
        entry["skip"] = True
        entry["note"] = "empty source"
    elif locale_text is not None:
        # Translation exists
        entry["translation"] = locale_text
    # else: only "en" field (pending translation)

    return entry


def bootstrap_locale(
    locale: str,
    dry_run: bool = False,
) -> dict[str, dict[str, int]] | None:
    """Bootstrap historical translations for a single locale.

    Args:
        locale: Target locale code (e.g., 'eo').
        dry_run: If True, only report what would be created.

    Returns:
        Stats dict with counts per file.
    """
    locale_dir = SRC_LOCALES_DIR / locale
    output_dir = TRANSLATIONS_DIR / locale

    if not locale_dir.exists():
        print(f"Error: Locale directory not found: {locale_dir}", file=sys.stderr)
        return None

    if not EN_DIR.exists():
        print(f"Error: English directory not found: {EN_DIR}", file=sys.stderr)
        sys.exit(1)

    stats: dict[str, dict[str, int]] = {}
    en_files = sorted(EN_DIR.glob("*.json"))

    for en_file in en_files:
        file_name = en_file.name
        locale_file = locale_dir / file_name
        output_file = output_dir / file_name

        # Get English keys
        en_keys = get_keys_from_file(en_file)
        if not en_keys:
            continue

        # Get locale keys (may be empty if file doesn't exist)
        locale_keys = get_keys_from_file(locale_file)

        # Build historical data
        historical: dict[str, dict[str, Any]] = {}
        file_stats = {
            "total": 0,
            "translated": 0,
            "pending": 0,
            "skipped": 0,
        }

        for key, en_text in en_keys.items():
            locale_text = locale_keys.get(key)
            entry = build_historical_entry(en_text, locale_text)
            historical[key] = entry

            file_stats["total"] += 1
            if entry.get("skip"):
                file_stats["skipped"] += 1
            elif "translation" in entry:
                file_stats["translated"] += 1
            else:
                file_stats["pending"] += 1

        stats[file_name] = file_stats

        if dry_run:
            print(f"  [DRY-RUN] {file_name}: "
                  f"{file_stats['translated']} translated, "
                  f"{file_stats['pending']} pending, "
                  f"{file_stats['skipped']} skipped")
        else:
            save_json_file(output_file, historical)
            print(f"  {file_name}: "
                  f"{file_stats['translated']} translated, "
                  f"{file_stats['pending']} pending, "
                  f"{file_stats['skipped']} skipped")

    return stats


def print_summary(all_stats: dict[str, dict[str, dict[str, int]]]) -> None:
    """Print summary of all processed locales."""
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)

    grand_total = {"total": 0, "translated": 0, "pending": 0, "skipped": 0}

    for locale, file_stats in sorted(all_stats.items()):
        locale_total = {"total": 0, "translated": 0, "pending": 0, "skipped": 0}
        for stats in file_stats.values():
            for key in locale_total:
                locale_total[key] += stats[key]
                grand_total[key] += stats[key]

        pct = (locale_total["translated"] / locale_total["total"] * 100
               if locale_total["total"] > 0 else 0)
        print(f"  {locale}: {locale_total['translated']}/{locale_total['total']} "
              f"({pct:.1f}% translated)")

    if len(all_stats) > 1:
        print("-" * 60)
        print(f"  Total: {grand_total['total']} keys across {len(all_stats)} locales")


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Bootstrap existing translations into historical JSON format.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python bootstrap_translations.py eo           # Bootstrap Esperanto
    python bootstrap_translations.py eo --dry-run # Preview without writing
    python bootstrap_translations.py --all        # Bootstrap all locales
        """,
    )

    parser.add_argument(
        "locale",
        nargs="?",
        help="Target locale code (e.g., 'eo', 'fr_FR')",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Process all available locales",
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
        locales = get_available_locales()
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
            print(f"\nOutput directory: {TRANSLATIONS_DIR}")

    # Return error code if any locales failed
    if errors > 0:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
