#!/usr/bin/env python3
"""
Detect variable discrepancies between English (en) baseline and other locales.

Variable patterns detected:
  - Vue i18n: {variable} or {0}, {1}, etc.
  - Ruby ERB: %{variable}
  - Legacy printf: %s, %d, %i, %f, %u, %x, %X, %o, %e, %E, %g, %G, %c, %p

Format validation:
  - email.json must use Ruby ERB %{var} only (not Vue {var})

Usage:
  audit-variables.py [options]

Options:
  --summary          Count discrepancies by locale (default)
  --detailed         Show all issues with key paths and strings
  --json             Minimal JSON output for CI
  --locale XX        Check only specific locale (e.g., es, fr_FR)
  --file FILE        Check only specific file (e.g., email.json)
  --filter PREFIX    Only include keys starting with PREFIX
  --exclude PREFIX   Exclude keys starting with PREFIX

Exit codes:
  0                  No issues found
  1-100              Number of issues (capped at 100)

Examples:
  audit-variables.py                           # Summary of all locales
  audit-variables.py --detailed --locale es    # Detailed report for Spanish
  audit-variables.py --json | jq .summary      # JSON summary for human
  audit-variables.py --json                    # JSON summary for automation
  audit-variables.py --filter email.welcome    # Only email.welcome.* keys
  audit-variables.py --exclude web.COMMON      # Skip web.COMMON.* keys
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

# Date stamp for error IDs (MMDD format)
DATE_STAMP = datetime.now().strftime("%m%d")


# Variable patterns
# Vue i18n: {variable} - use negative lookbehind to exclude ERB %{variable}
VUE_VAR_PATTERN = re.compile(r"(?<!%)(?<!\{)\{([a-zA-Z0-9_]+)\}")
ERB_VAR_PATTERN = re.compile(r"%\{([a-zA-Z0-9_]+)\}")
PRINTF_PATTERN = re.compile(r"%[sdifuxXoeEgGcp]")

# Files that should ONLY use Ruby ERB format (%{var}), not Vue format ({var})
# Email templates are rendered server-side by Ruby, not by Vue
RUBY_ONLY_FILES = {"email.json"}


def extract_variables(text: str) -> dict[str, set[str]]:
    """Extract all variable patterns from a string."""
    if not isinstance(text, str):
        return {"vue": set(), "erb": set(), "printf": set()}

    return {
        "vue": set(VUE_VAR_PATTERN.findall(text)),
        "erb": set(ERB_VAR_PATTERN.findall(text)),
        "printf": set(PRINTF_PATTERN.findall(text)),
    }


def flatten_json(obj: dict[str, Any], prefix: str = "") -> dict[str, str]:
    """Flatten nested JSON into dot-notation key paths."""
    result = {}
    for key, value in obj.items():
        full_key = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            result.update(flatten_json(value, full_key))
        elif isinstance(value, str):
            result[full_key] = value
    return result


def should_skip_key(
    key: str,
    filter_prefix: str | None = None,
    exclude_prefix: str | None = None,
) -> bool:
    """Check if a key should be skipped (metadata keys or filtered out)."""
    parts = key.split(".")
    # Skip metadata keys (prefixed with _)
    if any(part.startswith("_") for part in parts):
        return True
    # Apply filter (only include keys starting with prefix)
    if filter_prefix and not key.startswith(filter_prefix):
        return True
    # Apply exclude (skip keys starting with prefix)
    if exclude_prefix and key.startswith(exclude_prefix):
        return True
    return False


def compare_variables(
    source_text: str, locale_text: str
) -> dict[str, dict[str, set[str]]]:
    """Compare variables between English and translated text."""
    en_vars = extract_variables(source_text)
    locale_vars = extract_variables(locale_text)

    discrepancies = {}

    for var_type in ["vue", "erb", "printf"]:
        missing = en_vars[var_type] - locale_vars[var_type]
        extra = locale_vars[var_type] - en_vars[var_type]

        if missing or extra:
            discrepancies[var_type] = {"missing": missing, "extra": extra}

    return discrepancies


def check_empty_with_vars(source_text: str, locale_text: str) -> bool:
    """Check if translation is empty but English had variables."""
    if locale_text.strip() == "" and source_text.strip() != "":
        en_vars = extract_variables(source_text)
        return any(vars for vars in en_vars.values())
    return False


def check_wrong_format(text: str, filename: str) -> list[str]:
    """Check if text uses wrong variable format for the file type.

    Email templates (Ruby-rendered) should use %{var}, not {var}.
    Returns list of variables using wrong format.
    """
    if filename not in RUBY_ONLY_FILES:
        return []

    # In Ruby-only files, Vue-style {var} is wrong
    vue_vars = VUE_VAR_PATTERN.findall(text)
    return [f"{{{v}}}" for v in vue_vars]


def audit_locale(
    en_dir: Path,
    locale_dir: Path,
    target_file: str | None = None,
    warned_missing_file: set | None = None,
    filter_prefix: str | None = None,
    exclude_prefix: str | None = None,
) -> dict[str, list[dict]]:
    """Audit a single locale against English baseline."""
    issues = defaultdict(list)
    if warned_missing_file is None:
        warned_missing_file = set()

    json_files = list(en_dir.glob("*.json"))
    if target_file:
        json_files = [f for f in json_files if f.name == target_file]
        if not json_files and target_file not in warned_missing_file:
            print(
                f'Warning: No file named "{target_file}" in English locale',
                file=sys.stderr,
            )
            warned_missing_file.add(target_file)

    for en_file in json_files:
        locale_file = locale_dir / en_file.name

        if not locale_file.exists():
            continue

        try:
            with open(en_file, "r", encoding="utf-8") as f:
                en_data = flatten_json(json.load(f))
            with open(locale_file, "r", encoding="utf-8") as f:
                locale_data = flatten_json(json.load(f))
        except (json.JSONDecodeError, IOError) as e:
            issues[en_file.name].append(
                {
                    "key": "_file_error",
                    "error": str(e),
                }
            )
            continue

        for key, source_text in en_data.items():
            if should_skip_key(key, filter_prefix, exclude_prefix):
                continue

            locale_text = locale_data.get(key, "")

            # Check for wrong variable format in Ruby-only files (e.g., email.json)
            # English source should use %{var}, not {var}
            wrong_format_en = check_wrong_format(source_text, en_file.name)
            if wrong_format_en:
                issues[en_file.name].append(
                    {
                        "key": key,
                        "source_text": source_text,
                        "locale_text": locale_text,
                        "wrong_format": wrong_format_en,
                        "wrong_format_source": "en",
                        "hint": "Use %{var} instead of {var} for Ruby i18n",
                    }
                )
                # Continue to also check for other issues

            # Check wrong format in translation too
            if locale_text and key in locale_data:
                wrong_format_locale = check_wrong_format(locale_text, en_file.name)
                if wrong_format_locale:
                    issues[en_file.name].append(
                        {
                            "key": key,
                            "source_text": source_text,
                            "locale_text": locale_text,
                            "wrong_format": wrong_format_locale,
                            "wrong_format_source": "locale",
                            "hint": "Use %{var} instead of {var} for Ruby i18n",
                        }
                    )

            # Check for empty translation with variables in English
            if check_empty_with_vars(source_text, locale_text):
                en_vars = extract_variables(source_text)
                all_vars = []
                for var_type, vars in en_vars.items():
                    for v in vars:
                        if var_type == "printf":
                            all_vars.append(v)
                        elif var_type == "erb":
                            all_vars.append(f"%{{{v}}}")
                        else:
                            all_vars.append(f"{{{v}}}")

                issues[en_file.name].append(
                    {
                        "key": key,
                        "source_text": source_text,
                        "locale_text": "[EMPTY]",
                        "missing": all_vars,
                        "extra": [],
                        "empty_with_vars": True,
                    }
                )
                continue

            # Skip if translation doesn't exist
            if key not in locale_data:
                continue

            # Compare variables
            discrepancies = compare_variables(source_text, locale_text)

            if discrepancies:
                all_missing = []
                all_extra = []

                for var_type, diffs in discrepancies.items():
                    for v in diffs["missing"]:
                        if var_type == "printf":
                            all_missing.append(v)
                        elif var_type == "erb":
                            all_missing.append(f"%{{{v}}}")
                        else:
                            all_missing.append(f"{{{v}}}")

                    for v in diffs["extra"]:
                        if var_type == "printf":
                            all_extra.append(v)
                        elif var_type == "erb":
                            all_extra.append(f"%{{{v}}}")
                        else:
                            all_extra.append(f"{{{v}}}")

                issues[en_file.name].append(
                    {
                        "key": key,
                        "source_text": source_text,
                        "locale_text": locale_text,
                        "missing": all_missing,
                        "extra": all_extra,
                    }
                )

    return dict(issues)


def print_summary(results: dict[str, dict[str, list[dict]]]) -> None:
    """Print summary of discrepancies by locale."""
    totals = []
    for locale, files in sorted(results.items()):
        count = sum(len(issues) for issues in files.values())
        if count > 0:
            totals.append((locale, count))

    if not totals:
        print(f"{'total':<10} {0:>4}")
        return

    totals.sort(key=lambda x: -x[1])

    for locale, count in totals:
        print(f"{locale:<10} {count:>4}")

    grand_total = sum(c for _, c in totals)
    print(f"{'total':<10} {grand_total:>4}")


def print_detailed(results: dict[str, dict[str, list[dict]]]) -> None:
    """Print detailed discrepancy report."""
    for locale, files in sorted(results.items()):
        if not any(files.values()):
            continue

        print()
        print("=" * 60)
        print(f"=== Locale: {locale} ===")
        print("=" * 60)

        # Count errors for this locale to generate error IDs
        error_index = 0

        for filename, issues in sorted(files.items()):
            if not issues:
                continue

            print(f"\nfile: {filename}")

            for issue in issues:
                if "error" in issue:
                    print(f"  ERROR: {issue['error']}")
                    continue

                error_index += 1
                error_id = f"{locale}-{DATE_STAMP}-error-{error_index}"

                print(f"  key:      {issue['key']}")
                print(f'  en:       "{issue["source_text"]}"')
                print(f"  {locale}:".ljust(12) + f'"{issue["locale_text"]}"')
                if issue.get("wrong_format"):
                    source = issue.get("wrong_format_source", "unknown")
                    print(f"  wrong_fmt: {', '.join(issue['wrong_format'])} (in {source})")
                    print(f"  hint:     {issue.get('hint', '')}")
                if issue.get("missing"):
                    print(f"  missing:  {', '.join(issue['missing'])}")
                if issue.get("extra"):
                    print(f"  comment:  {', '.join(issue['extra'])}")
                print(f"  errorid:  {error_id}")
                print()


def print_json(results: dict[str, dict[str, list[dict]]]) -> None:
    """Print machine-readable JSON output."""
    output = {
        "date": DATE_STAMP,
        "summary": {},
        "details": {},
    }

    for locale, files in results.items():
        count = sum(len(issues) for issues in files.values())
        if count > 0:
            output["summary"][locale] = count

        if files:
            output["details"][locale] = {}
            error_index = 0
            for filename, issues in sorted(files.items()):
                if issues:
                    enriched_issues = []
                    for issue in issues:
                        if "error" not in issue:
                            error_index += 1
                            issue_copy = issue.copy()
                            issue_copy["errorid"] = (
                                f"{locale}-{DATE_STAMP}-error-{error_index}"
                            )
                            # Rename 'extra' to 'comment' for consistency
                            if "extra" in issue_copy:
                                issue_copy["comment"] = issue_copy.pop("extra")
                            enriched_issues.append(issue_copy)
                        else:
                            enriched_issues.append(issue)
                    output["details"][locale][filename] = enriched_issues

    print(json.dumps(output, separators=(",", ":"), ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detect variable discrepancies in i18n locale files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Variable patterns detected:
  - Vue i18n: {variable} or {0}, {1}, etc.
  - Ruby ERB: %%{variable}
  - Legacy printf: %%s, %%d, %%i, %%f, etc.

Examples:
  %(prog)s --summary
  %(prog)s --detailed --locale es
  %(prog)s --json --file email.json
  %(prog)s --detailed --filter email.welcome
  %(prog)s --summary --exclude web.COMMON
""",
    )

    output_group = parser.add_mutually_exclusive_group()
    output_group.add_argument(
        "--summary",
        action="store_true",
        default=True,
        help="Count discrepancies by locale (default)",
    )
    output_group.add_argument(
        "--detailed",
        action="store_true",
        help="Show all issues with key paths and strings",
    )
    output_group.add_argument(
        "--json",
        action="store_true",
        help="Machine-readable JSON output for CI",
    )

    parser.add_argument(
        "--locale",
        metavar="XX",
        help="Check only specific locale (e.g., es, fr_FR)",
    )
    parser.add_argument(
        "--file",
        metavar="FILE",
        help="Check only specific file (e.g., email.json)",
    )
    parser.add_argument(
        "--filter",
        metavar="PREFIX",
        help="Only include keys starting with PREFIX (e.g., email.welcome)",
    )
    parser.add_argument(
        "--exclude",
        metavar="PREFIX",
        help="Exclude keys starting with PREFIX (e.g., web.COMMON)",
    )

    args = parser.parse_args()

    # Determine locales directory
    script_dir = Path(__file__).resolve().parent
    # Navigate from locales/scripts/validate to locales/content
    content_dir = script_dir.parent.parent / "content"

    if not content_dir.exists():
        print(
            f"Error: Content directory not found: {content_dir}",
            file=sys.stderr,
        )
        return 1

    en_dir = content_dir / "en"
    if not en_dir.exists():
        print(f"Error: English locale not found: {en_dir}", file=sys.stderr)
        return 1

    # Get list of locales to check
    if args.locale:
        locale_dirs = [content_dir / args.locale]
        if not locale_dirs[0].exists():
            print(f"Error: Locale not found: {args.locale}", file=sys.stderr)
            return 1
    else:
        locale_dirs = [
            d
            for d in content_dir.iterdir()
            if d.is_dir() and d.name != "en" and not d.name.startswith(".")
        ]

    # Audit each locale
    results = {}
    warned_missing_file: set[str] = set()
    for locale_dir in sorted(locale_dirs):
        locale_name = locale_dir.name
        issues = audit_locale(
            en_dir,
            locale_dir,
            args.file,
            warned_missing_file,
            args.filter,
            args.exclude,
        )
        if any(issues.values()):
            results[locale_name] = issues

    # Output results
    if args.json:
        print_json(results)
    elif args.detailed:
        print_detailed(results)
    else:
        print_summary(results)

    # Return issue count as exit code (max 100) for CI
    total_issues = sum(
        sum(len(issues) for issues in files.values())
        for files in results.values()
    )
    return min(total_issues, 100)


if __name__ == "__main__":
    sys.exit(main())
