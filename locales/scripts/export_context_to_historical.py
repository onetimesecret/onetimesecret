#!/usr/bin/env python3
"""
One-time migration: export _context fields from src/locales/en to content JSON.

The bootstrap_translations.py script intentionally skipped _context keys (metadata).
This script adds them as a 'context' field on the related key's entry in content JSON.

Two patterns are handled:
  1. _context inside a group: applies to all sibling keys
     {"verify": {"_context": "...", "title": "..."}}
     -> adds context to "web.auth.verify.title" entry

  2. _context_<keyname>: applies to specific key
     {"_context_mfa_required": "...", "mfa_required": "..."}
     -> adds context to "web.auth.mfa_required" entry

Usage:
    python export_context_to_historical.py --dry-run
    python export_context_to_historical.py
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
SRC_LOCALES_DIR = LOCALES_DIR.parent / "src" / "locales"
EN_DIR = SRC_LOCALES_DIR / "en"
CONTENT_DIR = LOCALES_DIR / "content"


def collect_context_mappings(obj: dict[str, Any], prefix: str = "") -> dict[str, str]:
    """Recursively collect context mappings from nested dict.

    Returns a dict mapping target key paths to their context strings.

    Args:
        obj: Dictionary to walk.
        prefix: Current key path prefix.

    Returns:
        Dict mapping key_path -> context_string
    """
    mappings: dict[str, str] = {}

    # First pass: find _context (group context) and _context_<key> (specific context)
    group_context = obj.get("_context")
    specific_contexts: dict[str, str] = {}

    for key, value in obj.items():
        if key.startswith("_context_") and isinstance(value, str):
            # _context_foo -> applies to "foo"
            target_key = key[9:]  # strip "_context_"
            specific_contexts[target_key] = value

    # Second pass: process all keys
    for key, value in obj.items():
        if key.startswith("_"):
            continue

        full_key = f"{prefix}.{key}" if prefix else key

        if isinstance(value, dict):
            # Recurse into nested dict
            mappings.update(collect_context_mappings(value, full_key))
        elif isinstance(value, str):
            # Leaf key - check for applicable context
            if key in specific_contexts:
                mappings[full_key] = specific_contexts[key]
            elif group_context:
                mappings[full_key] = group_context

    return mappings


def load_json_file(file_path: Path) -> dict:
    """Load a JSON file, returning empty dict if not found."""
    if file_path.exists():
        try:
            with open(file_path, encoding="utf-8") as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"Warning: Invalid JSON in {file_path}: {e}", file=sys.stderr)
            return {}
    return {}


def save_json_file(file_path: Path, data: dict) -> None:
    """Save a dictionary to a JSON file with consistent formatting."""
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def get_locale_dirs() -> list[str]:
    """Get list of locale directories in content/."""
    if not CONTENT_DIR.exists():
        return []
    return sorted([
        d.name for d in CONTENT_DIR.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    ])


def export_context_fields(dry_run: bool = False) -> dict[str, int]:
    """Export _context fields from English to all content locale files.

    Adds context as a 'context' field on the target key's entry.

    Args:
        dry_run: If True, only report what would be done.

    Returns:
        Stats dict with counts per file.
    """
    if not EN_DIR.exists():
        print(f"Error: English directory not found: {EN_DIR}", file=sys.stderr)
        sys.exit(1)

    locale_dirs = get_locale_dirs()
    if not locale_dirs:
        print(f"Error: No locale directories in {CONTENT_DIR}", file=sys.stderr)
        sys.exit(1)

    stats: dict[str, int] = {}

    # Process each English JSON file
    for en_file in sorted(EN_DIR.glob("*.json")):
        file_name = en_file.name
        en_data = load_json_file(en_file)
        if not en_data:
            continue

        # Collect context mappings (key_path -> context_string)
        context_mappings = collect_context_mappings(en_data)
        if not context_mappings:
            continue

        stats[file_name] = len(context_mappings)

        if dry_run:
            print(f"\n{file_name}: {len(context_mappings)} keys with context")
            for key, ctx in context_mappings.items():
                print(f"  {key}")
                print(f"    context: {ctx[:60]}{'...' if len(ctx) > 60 else ''}")
            continue

        # Add context to each locale's content file
        added_count = 0
        for locale in locale_dirs:
            content_file = CONTENT_DIR / locale / file_name
            content = load_json_file(content_file)

            # Add context field to matching entries
            locale_added = 0
            for key_path, context in context_mappings.items():
                if key_path in content and "context" not in content[key_path]:
                    content[key_path]["context"] = context
                    locale_added += 1

            if locale_added > 0:
                save_json_file(content_file, content)
                added_count += locale_added

        print(f"{file_name}: added context to {len(context_mappings)} keys across {len(locale_dirs)} locales")

    return stats


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Export _context fields from src/locales/en to content JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be exported without making changes",
    )

    args = parser.parse_args()

    print("Exporting _context fields from English source to content JSON")
    print(f"  Source: {EN_DIR}")
    print(f"  Target: {CONTENT_DIR}")
    print()

    stats = export_context_fields(dry_run=args.dry_run)

    if stats:
        total = sum(stats.values())
        print(f"\n{'Would add' if args.dry_run else 'Added'} context to {total} keys from {len(stats)} files")

    return 0


if __name__ == "__main__":
    sys.exit(main())
