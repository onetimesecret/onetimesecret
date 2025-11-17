#!/usr/bin/env python3
"""
Repairs i18n locale files to match base en/ key structure.
Preserves existing translations while moving/adding keys.

Usage: ./harmonize-locale-file.py [-q] [-f] [-v] [-c] LOCALE
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Optional


def find_value(key: str, obj: Any) -> Optional[Any]:
    """Deep search for key anywhere in nested structure."""
    if obj is None or not isinstance(obj, dict):
        return None

    if key in obj:
        return obj[key]

    for value in obj.values():
        result = find_value(key, value)
        if result is not None:
            return result

    return None


def find_compatible_value(
    key: str, expected_value: Any, obj: Any
) -> Optional[Any]:
    """Find key in obj, but only if types match expected_value."""
    found = find_value(key, obj)
    if found is not None and type(found) == type(expected_value):
        return found
    return None


def empty_structure(value: Any) -> Any:
    """Create empty skeleton matching structure."""
    if isinstance(value, dict):
        return {k: empty_structure(v) for k, v in value.items()}
    return ""


def walk(
    target: Any, base: Any, target_root: Any, copy_values: bool = False
) -> Any:
    """Restructure target to match base, with type-safe key recovery."""
    if not isinstance(base, dict):
        # Base is primitive
        return base if (target is None and copy_values) else (target or "")

    # Base is object - iterate through its structure
    result = {}
    for key, base_value in base.items():
        if (
            isinstance(target, dict)
            and key in target
            and target[key] is not None
        ):
            # Key exists in expected location
            result[key] = walk(
                target[key], base_value, target_root, copy_values
            )
        else:
            # Key missing - search entire target tree
            existing = find_compatible_value(key, base_value, target_root)
            if existing is not None:
                result[key] = existing
            elif copy_values:
                result[key] = base_value
            else:
                result[key] = empty_structure(base_value)

    return result


def harmonize_file(
    base_file: Path, locale_file: Path, copy_values: bool = False
) -> dict:
    """Harmonize a single locale file to match base structure."""
    with open(base_file, "r", encoding="utf-8") as f:
        base = json.load(f)

    with open(locale_file, "r", encoding="utf-8") as f:
        target = json.load(f)

    return walk(target, base, target, copy_values)


def main():
    parser = argparse.ArgumentParser(
        description="Repairs i18n locale files to match base en/ key structure"
    )
    parser.add_argument("locale", help='Locale code (e.g., "es", "fr")')
    parser.add_argument("-q", "--quiet", action="store_true", help="Quiet mode")
    parser.add_argument(
        "-f",
        "--filename-only",
        action="store_true",
        help="Filename only output",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Verbose output"
    )
    parser.add_argument(
        "-c",
        "--copy-values",
        action="store_true",
        help="Copy values from base file",
    )
    parser.add_argument(
        "--base-locale", default="en", help="Base locale (default: en)"
    )
    parser.add_argument("--base-dir", help="Base locale directory")

    args = parser.parse_args()

    # Determine directories
    script_dir = Path(__file__).parent
    base_dir = (
        Path(args.base_dir)
        if args.base_dir
        else script_dir / "../../../locales" / args.base_locale
    )
    locale_dir = script_dir / "../../../locales" / args.locale

    # Validate directories
    if not locale_dir.is_dir():
        print(f"Locale directory not found: {locale_dir}", file=sys.stderr)
        return 1

    if not base_dir.is_dir():
        print(f"Base locale directory not found: {base_dir}", file=sys.stderr)
        return 1

    # Process files
    error_count = 0
    success_count = 0

    for locale_file in sorted(locale_dir.glob("*.json")):
        if not locale_file.is_file():
            continue

        base_file = base_dir / locale_file.name

        # Skip if corresponding base file doesn't exist
        if not base_file.is_file():
            if args.verbose:
                print(
                    f"Skipping {locale_file.name} (no corresponding base file)"
                )
            continue

        try:
            # Harmonize the file
            result = harmonize_file(base_file, locale_file, args.copy_values)

            # Write back to the same file
            with open(locale_file, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
                f.write("\n")

            if args.verbose:
                print(f"Repaired {locale_file}")

            success_count += 1

        except Exception as e:
            if args.filename_only:
                print(locale_file)
            if args.verbose:
                print(f"Failed repairing {locale_file}: {e}")
            error_count += 1

    # Summary output
    if not args.quiet and not args.verbose:
        print(f"Harmonized {success_count} file(s) for locale '{args.locale}'")

    if error_count > 0:
        if not args.quiet:
            print(f"Failed to harmonize {error_count} file(s)", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
