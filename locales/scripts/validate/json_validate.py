#!/usr/bin/env python3
"""
Validates JSON syntax in i18n locale files.

Usage:
    ./validate-locale-json.py           # Check all locales (show only errors)
    ./validate-locale-json.py -v zh     # Check specific locale (verbose)
    ./validate-locale-json.py -q        # Quiet mode (exit code only)
    ./validate-locale-json.py en es fr  # Check multiple locales
"""

import argparse
import json
import sys
from pathlib import Path


def get_relative_path(path: Path) -> str:
    """Get path relative to current working directory."""
    try:
        # Resolve to absolute path first to clean up any ../.. patterns
        resolved = path.resolve()
        return str(resolved.relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


def validate_json_file(file_path: Path) -> tuple[bool, str]:
    """Validate a single JSON file.

    Returns: (is_valid, error_message)
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            json.load(f)
        return True, ""
    except json.JSONDecodeError as e:
        return False, f"Line {e.lineno}, Col {e.colno}: {e.msg}"
    except Exception as e:
        return False, str(e)


def validate_locale(
    locale_dir: Path, verbose: bool = False, quiet: bool = False
) -> int:
    """Validate all JSON files in a locale directory.

    Args:
        locale_dir: Path to locale directory
        verbose: Show all files (OK and NOT OK)
        quiet: No output, just return error count

    Returns: Number of files with errors
    """
    if not locale_dir.is_dir():
        if not quiet:
            print(f"Locale directory not found: {locale_dir}", file=sys.stderr)
        return 0

    json_files = sorted(locale_dir.glob("*.json"))
    if not json_files:
        return 0

    error_count = 0

    for json_file in json_files:
        if not json_file.is_file():
            continue

        rel_path = get_relative_path(json_file)
        is_valid, error_msg = validate_json_file(json_file)

        if is_valid:
            if verbose:
                print(f"{rel_path}: OK")
        else:
            if not quiet:
                print(f"{rel_path}: NOT OK")
                if error_msg:
                    print(f"  Error: {error_msg}")
            error_count += 1

    return error_count


def main():
    parser = argparse.ArgumentParser(
        description="Validates JSON syntax in i18n locale files"
    )
    parser.add_argument(
        "locales",
        nargs="*",
        help="Locale codes to check (2-5 chars, e.g., 'en', 'zh'). If omitted, checks all locales.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Show all files (OK and NOT OK)",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Quiet mode (no output, exit code only)",
    )

    args = parser.parse_args()

    # Determine locale directories to check
    script_dir = Path(__file__).parent
    locales_dir = script_dir / "../../../locales"

    if not locales_dir.is_dir():
        if not args.quiet:
            print(
                f"Locales directory not found: {locales_dir}", file=sys.stderr
            )
        return 1

    # Determine which locales to check
    locales_to_check = []

    if args.locales:
        # Check specific locales provided as arguments
        for locale in args.locales:
            if len(locale) < 2 or len(locale) > 5:
                if not args.quiet:
                    print(
                        f"Invalid locale code: {locale} (must be 2-5 characters)",
                        file=sys.stderr,
                    )
                return 1
            locales_to_check.append(locale)
    else:
        # Check all locale directories
        locales_to_check = [
            d.name
            for d in locales_dir.iterdir()
            if d.is_dir() and not d.name.startswith(".")
        ]

    # Validate each locale
    total_errors = 0

    for locale in sorted(locales_to_check):
        locale_dir = locales_dir / locale
        errors = validate_locale(
            locale_dir, verbose=args.verbose, quiet=args.quiet
        )
        total_errors += errors

    # Exit with error code if any validation failed
    return 1 if total_errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
