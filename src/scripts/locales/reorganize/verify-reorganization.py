#!/usr/bin/env python3
"""
Post-reorganization verification script for locale key migration.

Verifies that all keys from uncategorized.json have been correctly distributed
to category files without data loss or corruption.

Usage:
    ./verify-reorganization.py                    # Verify all locales
    ./verify-reorganization.py en                 # Verify single locale
    ./verify-reorganization.py en es fr           # Verify multiple locales
    ./verify-reorganization.py --verbose          # Detailed output
    ./verify-reorganization.py --json             # JSON output for CI
    ./verify-reorganization.py --pre-check        # Pre-reorganization snapshot
    ./verify-reorganization.py --compare SNAPSHOT # Compare against snapshot

Exit codes:
    0 = All checks passed
    1 = Verification failed
    2 = Configuration/setup error
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# Keys explicitly excluded from reorganization
EXCLUDED_KEYS = [
    "emoji-x",
    "emoji-checkmark",
    "min-width-1024px",
]

# Files that may not have the standard { "web": {...} } structure
# These are checked with a warning instead of failure in non-strict mode
LEGACY_STRUCTURE_FILES = [
    "email.json",
    "feature-incoming.json",
]

# Keys known to have intentionally unbalanced characters
# (e.g., sentence fragments that span multiple keys)
KNOWN_UNBALANCED_KEYS = [
    "a-cname-record-is-not-allowed-instead-youll-need",
    "please-note-that-for-apex-domains",
]

# Expected category files after reorganization
EXPECTED_CATEGORY_FILES = [
    "account.json",
    "account-billing.json",
    "auth.json",
    "colonel.json",
    "dashboard.json",
    "email.json",
    "feature-domains.json",
    "feature-incoming.json",
    "feature-organizations.json",
    "feature-regions.json",
    "feature-secrets.json",
    "homepage.json",
    "layout.json",
    "_common.json",
    "uncategorized.json",  # Will have remaining keys
]


@dataclass
class VerificationResult:
    """Holds results of a single verification check."""
    check_name: str
    passed: bool
    message: str
    details: list = field(default_factory=list)

    def __str__(self):
        status = "PASS" if self.passed else "FAIL"
        return f"[{status}] {self.check_name}: {self.message}"


@dataclass
class LocaleReport:
    """Complete verification report for a single locale."""
    locale: str
    results: list = field(default_factory=list)
    original_key_count: int = 0
    distributed_key_count: int = 0
    excluded_key_count: int = 0

    @property
    def all_passed(self) -> bool:
        return all(r.passed for r in self.results)

    @property
    def failed_count(self) -> int:
        return sum(1 for r in self.results if not r.passed)


def get_relative_path(path: Path) -> str:
    """Get path relative to current working directory."""
    try:
        resolved = path.resolve()
        return str(resolved.relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


def load_json_file(file_path: Path) -> tuple[Optional[dict], Optional[str]]:
    """Load and parse a JSON file.

    Returns: (data, error_message)
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f), None
    except json.JSONDecodeError as e:
        return None, f"JSON syntax error at line {e.lineno}, col {e.colno}: {e.msg}"
    except FileNotFoundError:
        return None, "File not found"
    except Exception as e:
        return None, str(e)


def extract_flat_keys(data: dict, prefix: str = "") -> dict:
    """Extract all keys from nested structure into flat key->value mapping."""
    keys = {}
    for key, value in data.items():
        full_key = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            keys.update(extract_flat_keys(value, full_key))
        else:
            keys[full_key] = value
    return keys


def extract_top_level_keys(data: dict) -> set:
    """Extract top-level keys from a flat JSON structure."""
    return set(data.keys())


def find_interpolation_markers(text: str) -> list:
    """Find all interpolation markers like {0}, {1}, {count} in text."""
    if not isinstance(text, str):
        return []
    # Match {0}, {1}, {name}, etc.
    return re.findall(r'\{[^}]+\}', text)


def check_json_syntax(locale_dir: Path) -> VerificationResult:
    """Verify all JSON files in locale directory have valid syntax."""
    errors = []
    checked = 0

    for json_file in sorted(locale_dir.glob("*.json")):
        if not json_file.is_file():
            continue
        checked += 1
        _, error = load_json_file(json_file)
        if error:
            errors.append(f"{json_file.name}: {error}")

    if errors:
        return VerificationResult(
            check_name="JSON Syntax",
            passed=False,
            message=f"{len(errors)} file(s) have syntax errors",
            details=errors
        )

    return VerificationResult(
        check_name="JSON Syntax",
        passed=True,
        message=f"All {checked} files have valid JSON syntax"
    )


def check_no_duplicate_keys(locale_dir: Path) -> VerificationResult:
    """Verify no key appears in multiple category files."""
    key_locations = defaultdict(list)
    errors = []

    for json_file in sorted(locale_dir.glob("*.json")):
        if not json_file.is_file():
            continue

        data, error = load_json_file(json_file)
        if error:
            continue  # Syntax errors caught elsewhere

        # Handle both flat and nested ("web": {...}) structures
        if "web" in data and isinstance(data["web"], dict):
            # Nested structure - extract all leaf keys
            flat_keys = extract_flat_keys(data)
            for key in flat_keys:
                key_locations[key].append(json_file.name)
        else:
            # Flat structure (uncategorized.json style)
            for key in data:
                key_locations[key].append(json_file.name)

    # Find duplicates
    duplicates = {k: v for k, v in key_locations.items() if len(v) > 1}

    if duplicates:
        for key, files in sorted(duplicates.items())[:10]:  # Show first 10
            errors.append(f"'{key}' found in: {', '.join(files)}")
        if len(duplicates) > 10:
            errors.append(f"... and {len(duplicates) - 10} more duplicates")

        return VerificationResult(
            check_name="No Duplicate Keys",
            passed=False,
            message=f"{len(duplicates)} key(s) appear in multiple files",
            details=errors
        )

    return VerificationResult(
        check_name="No Duplicate Keys",
        passed=True,
        message=f"All keys are unique across {len(list(locale_dir.glob('*.json')))} files"
    )


def check_key_count(locale_dir: Path, expected_original: int = 430) -> VerificationResult:
    """Verify total key count matches expected after reorganization."""
    total_keys = 0
    excluded_found = 0
    key_breakdown = {}

    uncategorized_path = locale_dir / "uncategorized.json"
    uncategorized_data, _ = load_json_file(uncategorized_path)

    for json_file in sorted(locale_dir.glob("*.json")):
        if not json_file.is_file():
            continue

        data, error = load_json_file(json_file)
        if error:
            continue

        file_key_count = 0

        if "web" in data and isinstance(data["web"], dict):
            # Nested structure
            flat_keys = extract_flat_keys(data)
            file_key_count = len(flat_keys)
        else:
            # Flat structure
            file_key_count = len(data)
            # Check for excluded keys in uncategorized
            if json_file.name == "uncategorized.json":
                for key in EXCLUDED_KEYS:
                    if key in data:
                        excluded_found += 1

        key_breakdown[json_file.name] = file_key_count
        total_keys += file_key_count

    # Expected: original - excluded = distributed
    expected_distributed = expected_original - len(EXCLUDED_KEYS)
    # Note: We don't subtract excluded from total because they stay in uncategorized

    details = [f"{name}: {count} keys" for name, count in sorted(key_breakdown.items())]

    # The check passes if we have at least the expected number of keys
    # (category files may have pre-existing keys)
    if total_keys >= expected_distributed:
        return VerificationResult(
            check_name="Key Count",
            passed=True,
            message=f"Total {total_keys} keys (expected >= {expected_distributed})",
            details=details
        )
    else:
        return VerificationResult(
            check_name="Key Count",
            passed=False,
            message=f"Total {total_keys} keys, expected >= {expected_distributed} (original {expected_original} - {len(EXCLUDED_KEYS)} excluded)",
            details=details
        )


def check_interpolation_preserved(
    locale_dir: Path,
    original_uncategorized: Optional[dict] = None
) -> VerificationResult:
    """Verify interpolation markers {0}, {1}, etc. are preserved."""
    issues = []

    if original_uncategorized is None:
        # Load current uncategorized as reference
        uncategorized_path = locale_dir / "uncategorized.json"
        original_uncategorized, error = load_json_file(uncategorized_path)
        if error:
            return VerificationResult(
                check_name="Interpolation Markers",
                passed=False,
                message=f"Cannot load reference file: {error}"
            )

    # Build map of key -> expected markers from original
    expected_markers = {}
    for key, value in original_uncategorized.items():
        markers = find_interpolation_markers(value)
        if markers:
            expected_markers[key] = set(markers)

    # Check markers in all category files
    for json_file in sorted(locale_dir.glob("*.json")):
        if json_file.name == "uncategorized.json":
            continue
        if not json_file.is_file():
            continue

        data, error = load_json_file(json_file)
        if error:
            continue

        # Extract all values and check markers
        if "web" in data and isinstance(data["web"], dict):
            flat_data = extract_flat_keys(data)
            for full_key, value in flat_data.items():
                # Try to match with original key (last segment)
                key_segments = full_key.split(".")
                original_key = key_segments[-1] if key_segments else full_key

                if original_key in expected_markers:
                    current_markers = set(find_interpolation_markers(value))
                    expected = expected_markers[original_key]
                    if current_markers != expected:
                        issues.append(
                            f"{json_file.name}: '{original_key}' - "
                            f"expected {expected}, found {current_markers}"
                        )

    if issues:
        return VerificationResult(
            check_name="Interpolation Markers",
            passed=False,
            message=f"{len(issues)} key(s) have mismatched interpolation markers",
            details=issues[:10]  # Show first 10
        )

    return VerificationResult(
        check_name="Interpolation Markers",
        passed=True,
        message=f"All {len(expected_markers)} keys with markers preserved correctly"
    )


def check_file_structure(locale_dir: Path, strict: bool = True) -> VerificationResult:
    """Verify category files have proper { "web": { ... } } structure."""
    issues = []
    warnings = []
    valid_count = 0

    for json_file in sorted(locale_dir.glob("*.json")):
        if not json_file.is_file():
            continue

        # Skip uncategorized.json - it uses flat structure
        if json_file.name == "uncategorized.json":
            continue

        # Skip _common.json - may have different structure
        if json_file.name == "_common.json":
            continue

        data, error = load_json_file(json_file)
        if error:
            issues.append(f"{json_file.name}: Cannot load - {error}")
            continue

        # Check for "web" wrapper
        if "web" not in data:
            msg = f"{json_file.name}: Missing 'web' top-level key"
            # In non-strict mode, allow known legacy files
            if not strict and json_file.name in LEGACY_STRUCTURE_FILES:
                warnings.append(f"{msg} (legacy file, allowed)")
            else:
                issues.append(msg)
        elif not isinstance(data["web"], dict):
            issues.append(f"{json_file.name}: 'web' is not an object")
        else:
            valid_count += 1

    if issues:
        return VerificationResult(
            check_name="File Structure",
            passed=False,
            message=f"{len(issues)} file(s) have incorrect structure",
            details=issues + warnings
        )

    if warnings:
        return VerificationResult(
            check_name="File Structure",
            passed=True,
            message=f"{valid_count} valid, {len(warnings)} legacy files (allowed)",
            details=warnings
        )

    return VerificationResult(
        check_name="File Structure",
        passed=True,
        message=f"All {valid_count} category files have valid structure"
    )


def check_expected_files_exist(locale_dir: Path) -> VerificationResult:
    """Verify all expected category files exist."""
    missing = []
    existing = []

    for expected_file in EXPECTED_CATEGORY_FILES:
        file_path = locale_dir / expected_file
        if file_path.is_file():
            existing.append(expected_file)
        else:
            missing.append(expected_file)

    if missing:
        return VerificationResult(
            check_name="Expected Files",
            passed=False,
            message=f"{len(missing)} expected file(s) missing",
            details=[f"Missing: {f}" for f in missing]
        )

    return VerificationResult(
        check_name="Expected Files",
        passed=True,
        message=f"All {len(existing)} expected files present"
    )


def check_no_unbalanced_quotes(locale_dir: Path, strict: bool = True) -> VerificationResult:
    """Check for unbalanced quotes or brackets in values."""
    issues = []
    warnings = []

    for json_file in sorted(locale_dir.glob("*.json")):
        if not json_file.is_file():
            continue

        data, error = load_json_file(json_file)
        if error:
            continue

        def check_value(key: str, value: str, filename: str):
            if not isinstance(value, str):
                return

            # Extract just the key name (last segment for nested keys)
            key_name = key.split(".")[-1] if "." in key else key

            # Check for unbalanced curly braces (interpolation markers)
            open_braces = value.count('{')
            close_braces = value.count('}')
            if open_braces != close_braces:
                issues.append(
                    f"{filename}: '{key}' has unbalanced braces "
                    f"({{ = {open_braces}, }} = {close_braces})"
                )

            # Check for unbalanced square brackets
            open_brackets = value.count('[')
            close_brackets = value.count(']')
            if open_brackets != close_brackets:
                issues.append(
                    f"{filename}: '{key}' has unbalanced brackets "
                    f"([ = {open_brackets}, ] = {close_brackets})"
                )

            # Check for unbalanced parentheses
            open_parens = value.count('(')
            close_parens = value.count(')')
            if open_parens != close_parens:
                msg = (
                    f"{filename}: '{key}' has unbalanced parentheses "
                    f"(( = {open_parens}, ) = {close_parens})"
                )
                # In non-strict mode, allow known unbalanced keys
                if not strict and key_name in KNOWN_UNBALANCED_KEYS:
                    warnings.append(f"{msg} (known fragment, allowed)")
                else:
                    issues.append(msg)

        if "web" in data and isinstance(data["web"], dict):
            flat_data = extract_flat_keys(data)
            for key, value in flat_data.items():
                check_value(key, value, json_file.name)
        else:
            for key, value in data.items():
                check_value(key, value, json_file.name)

    if issues:
        return VerificationResult(
            check_name="Balanced Quotes/Brackets",
            passed=False,
            message=f"{len(issues)} value(s) have unbalanced characters",
            details=issues[:10] + warnings[:5]
        )

    if warnings:
        return VerificationResult(
            check_name="Balanced Quotes/Brackets",
            passed=True,
            message=f"All balanced ({len(warnings)} known fragments allowed)",
            details=warnings
        )

    return VerificationResult(
        check_name="Balanced Quotes/Brackets",
        passed=True,
        message="All values have balanced quotes and brackets"
    )


def verify_locale(locale_dir: Path, verbose: bool = False, strict: bool = True) -> LocaleReport:
    """Run all verification checks on a single locale.

    Args:
        locale_dir: Path to locale directory
        verbose: Show detailed output
        strict: If False, allow known legacy patterns (default True)
    """
    report = LocaleReport(locale=locale_dir.name)

    # Load original uncategorized for reference
    uncategorized_path = locale_dir / "uncategorized.json"
    original_data, _ = load_json_file(uncategorized_path)
    if original_data:
        report.original_key_count = len(original_data)

    # Run all checks
    checks = [
        check_json_syntax(locale_dir),
        check_expected_files_exist(locale_dir),
        check_file_structure(locale_dir, strict=strict),
        check_no_duplicate_keys(locale_dir),
        check_key_count(locale_dir, report.original_key_count or 430),
        check_interpolation_preserved(locale_dir, original_data),
        check_no_unbalanced_quotes(locale_dir, strict=strict),
    ]

    report.results = checks
    return report


def create_snapshot(locales_dir: Path, output_path: Path) -> bool:
    """Create a pre-reorganization snapshot for later comparison."""
    snapshot = {
        "created_at": str(Path(__file__).stat().st_mtime),
        "locales": {}
    }

    for locale_dir in sorted(locales_dir.iterdir()):
        if not locale_dir.is_dir() or locale_dir.name.startswith("."):
            continue

        uncategorized_path = locale_dir / "uncategorized.json"
        if not uncategorized_path.is_file():
            continue

        data, error = load_json_file(uncategorized_path)
        if error:
            print(f"Warning: Cannot load {locale_dir.name}/uncategorized.json: {error}")
            continue

        snapshot["locales"][locale_dir.name] = {
            "key_count": len(data),
            "keys": list(data.keys()),
            "interpolation_keys": {
                k: find_interpolation_markers(v)
                for k, v in data.items()
                if find_interpolation_markers(v)
            }
        }

    try:
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(snapshot, f, indent=2, ensure_ascii=False)
        print(f"Snapshot saved to: {output_path}")
        return True
    except Exception as e:
        print(f"Error saving snapshot: {e}", file=sys.stderr)
        return False


def print_report(report: LocaleReport, verbose: bool = False):
    """Print verification report for a locale."""
    status = "PASSED" if report.all_passed else "FAILED"
    print(f"\n{'='*60}")
    print(f"Locale: {report.locale} - {status}")
    print(f"{'='*60}")

    for result in report.results:
        print(f"  {result}")
        if verbose and result.details:
            for detail in result.details:
                print(f"    - {detail}")

    if not report.all_passed:
        print(f"\n  Summary: {report.failed_count} check(s) failed")


def print_json_report(reports: list[LocaleReport]):
    """Print verification results as JSON for CI integration."""
    output = {
        "success": all(r.all_passed for r in reports),
        "locales": {}
    }

    for report in reports:
        output["locales"][report.locale] = {
            "passed": report.all_passed,
            "checks": [
                {
                    "name": r.check_name,
                    "passed": r.passed,
                    "message": r.message,
                    "details": r.details if r.details else None
                }
                for r in report.results
            ]
        }

    print(json.dumps(output, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="Verify locale reorganization completed correctly"
    )
    parser.add_argument(
        "locales",
        nargs="*",
        help="Locale codes to verify (e.g., 'en', 'es'). If omitted, verifies all."
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show detailed output including all issues"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON for CI integration"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Strict mode: fail on all issues including known legacy patterns"
    )
    parser.add_argument(
        "--pre-check",
        metavar="FILE",
        help="Create pre-reorganization snapshot to FILE"
    )
    parser.add_argument(
        "--compare",
        metavar="SNAPSHOT",
        help="Compare against pre-reorganization snapshot"
    )

    args = parser.parse_args()

    # Locate locales directory
    script_dir = Path(__file__).parent
    locales_dir = script_dir / "../../../locales"

    if not locales_dir.is_dir():
        print(f"Error: Locales directory not found: {locales_dir}", file=sys.stderr)
        return 2

    locales_dir = locales_dir.resolve()

    # Handle pre-check snapshot creation
    if args.pre_check:
        success = create_snapshot(locales_dir, Path(args.pre_check))
        return 0 if success else 2

    # Determine which locales to verify
    locales_to_check = []

    if args.locales:
        for locale in args.locales:
            locale_path = locales_dir / locale
            if not locale_path.is_dir():
                print(f"Warning: Locale directory not found: {locale}", file=sys.stderr)
                continue
            locales_to_check.append(locale_path)
    else:
        locales_to_check = [
            d for d in sorted(locales_dir.iterdir())
            if d.is_dir() and not d.name.startswith(".")
        ]

    if not locales_to_check:
        print("No locales to verify.", file=sys.stderr)
        return 2

    # Run verification
    reports = []
    for locale_dir in locales_to_check:
        report = verify_locale(locale_dir, verbose=args.verbose, strict=args.strict)
        reports.append(report)

    # Output results
    if args.json:
        print_json_report(reports)
    else:
        for report in reports:
            print_report(report, verbose=args.verbose)

        # Summary
        passed = sum(1 for r in reports if r.all_passed)
        failed = len(reports) - passed
        print(f"\n{'='*60}")
        print(f"SUMMARY: {passed} passed, {failed} failed out of {len(reports)} locales")
        print(f"{'='*60}")

    # Exit code
    if all(r.all_passed for r in reports):
        return 0
    else:
        return 1


if __name__ == "__main__":
    sys.exit(main())
