#!/usr/bin/env python3
"""
PR locale validation script - validates changed locale files in pull requests.

Purpose:
  Validation-focused: ensures existing translations don't break. This script
  catches errors in translations that are present, NOT missing translations.
  Missing key detection is handled separately by harmonization workflows.

Validates:
1. JSON syntax (prerequisite - fail fast)
2. Template variables ({var}, {0}, %{var}) match English exactly
3. ERB format (email.json must use %{var} only, not Vue {var})
4. Security namespace (web.auth.security.*) forbidden patterns
5. Key structure (no extra/orphaned keys that don't exist in English)

Out of scope (handled by harmonization):
- Keys present in English but missing from translations
- Translation completeness/coverage metrics

Usage:
  validate-locale-pr.py                    # Validate changed files (git diff vs origin/develop)
  validate-locale-pr.py --base main        # Custom base branch
  validate-locale-pr.py --files FILE...    # Specific files (testing)
  validate-locale-pr.py --format json      # JSON output for PR comments
  validate-locale-pr.py --verbose          # Detailed progress

Exit codes:
  0 = pass, 1 = failures
"""

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Version check: GitHub Actions workflow uses Python 3.12, but script is compatible with 3.10+
# (dict[str, Any] syntax requires 3.9+, dataclass features used require 3.10+)
MIN_PYTHON = (3, 10)
if sys.version_info < MIN_PYTHON:
    sys.exit(f"Error: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required (found {sys.version_info.major}.{sys.version_info.minor})")


# Variable patterns (reused from audit-variables.py)
VUE_VAR_PATTERN = re.compile(r"(?<!%)(?<!\{)\{([a-zA-Z0-9_]+)\}")
ERB_VAR_PATTERN = re.compile(r"%\{([a-zA-Z0-9_]+)\}")
PRINTF_PATTERN = re.compile(r"%[sdifuxXoeEgGcp]")

# Files that must use Ruby ERB format only
RUBY_ONLY_FILES = {"email.json"}

# Security namespace forbidden patterns
SECURITY_FORBIDDEN_PATTERNS = [
    # Credential-specific reveals
    (r"\b(wrong|incorrect|invalid)\s+(password|otp|code|recovery)", "credential-specific failure"),
    (r"\bpassword\s+(wrong|incorrect|invalid|failed)", "credential-specific failure"),
    (r"\botp\s+(wrong|incorrect|invalid|failed)", "credential-specific failure"),
    (r"\b(recovery\s+)?code\s+(wrong|incorrect|invalid|does\s+not\s+exist)", "credential-specific failure"),
    # Precise timing reveals
    (r"\bwait\s+\d+\s+(minute|second|hour)", "precise timing"),
    (r"\btry\s+again\s+in\s+\d+", "precise timing"),
    (r"\blocked\s+for\s+\d+", "precise timing"),
    # Attack progress reveals
    (r"\b\d+\s+attempt[s]?\s+(remaining|left)", "attempt counter"),
    (r"\battempt[s]?\s+\d+", "attempt counter"),
    # Account enumeration
    (r"\baccount\s+(does\s+not\s+exist|not\s+found)", "account enumeration"),
    (r"\bemail\s+(does\s+not\s+exist|not\s+found)", "account enumeration"),
]


@dataclass
class ValidationIssue:
    """Single validation issue."""
    file: str
    locale: str
    key: str
    severity: str  # error, warning
    category: str  # json, variables, format, security, structure
    message: str
    details: dict[str, Any] = field(default_factory=dict)


@dataclass
class ValidationResult:
    """Validation results for all files."""
    issues: list[ValidationIssue] = field(default_factory=list)
    files_checked: int = 0
    locales_checked: set[str] = field(default_factory=set)

    @property
    def error_count(self) -> int:
        return sum(1 for i in self.issues if i.severity == "error")

    @property
    def warning_count(self) -> int:
        return sum(1 for i in self.issues if i.severity == "warning")

    @property
    def passed(self) -> bool:
        return self.error_count == 0


def extract_variables(text: Any) -> dict[str, set[str]]:
    """Extract all variable patterns from a string.

    Accepts Any type for defensive validation of JSON values.

    Examples:
        >>> extract_variables("Hello {name}, you have {count} messages")
        {'vue': {'name', 'count'}, 'erb': set(), 'printf': set()}

        >>> extract_variables("Dear %{recipient}, your code is %{code}")
        {'vue': set(), 'erb': {'recipient', 'code'}, 'printf': set()}

        >>> extract_variables(None)  # Non-string returns empty sets
        {'vue': set(), 'erb': set(), 'printf': set()}
    """
    if not isinstance(text, str):
        return {"vue": set(), "erb": set(), "printf": set()}

    return {
        "vue": set(VUE_VAR_PATTERN.findall(text)),
        "erb": set(ERB_VAR_PATTERN.findall(text)),
        "printf": set(PRINTF_PATTERN.findall(text)),
    }


def flatten_json(obj: dict[str, Any], prefix: str = "") -> dict[str, str]:
    """Flatten nested JSON into dot-notation key paths.

    Examples:
        >>> flatten_json({"web": {"auth": {"login": "Sign in"}}})
        {'web.auth.login': 'Sign in'}

        >>> flatten_json({"greeting": "Hello", "farewell": "Goodbye"})
        {'greeting': 'Hello', 'farewell': 'Goodbye'}
    """
    result = {}
    for key, value in obj.items():
        full_key = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            result.update(flatten_json(value, full_key))
        elif isinstance(value, str):
            result[full_key] = value
    return result


def should_skip_key(key: str) -> bool:
    """Check if a key should be skipped (metadata keys with _ prefix).

    Examples:
        >>> should_skip_key("_metadata.version")
        True

        >>> should_skip_key("web.auth._comment")
        True

        >>> should_skip_key("web.auth.login")
        False
    """
    parts = key.split(".")
    return any(part.startswith("_") for part in parts)


def get_changed_locale_files(base_branch: str) -> list[tuple[str, str]]:
    """
    Get list of changed locale files from git diff.
    Returns list of (locale, filename) tuples.
    """
    try:
        # Get changed files relative to base branch
        result = subprocess.run(
            ["git", "diff", "--name-only", f"origin/{base_branch}...HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )

        changed_files = []
        for line in result.stdout.strip().split("\n"):
            if not line:
                continue

            # Match src/locales/{locale}/{file.json}
            match = re.match(r"^src/locales/([^/]+)/([^/]+\.json)$", line)
            if match:
                locale, filename = match.groups()
                if locale != "en":  # Skip English baseline
                    changed_files.append((locale, filename))

        return changed_files

    except subprocess.CalledProcessError as e:
        print(f"Error running git diff: {e}", file=sys.stderr)
        return []


def validate_json_syntax(file_path: Path) -> tuple[bool, str]:
    """Validate JSON syntax and UTF-8 encoding.

    Returns:
        Tuple of (is_valid, error_message). Error message is empty on success.

    Examples:
        >>> validate_json_syntax(Path("valid.json"))
        (True, '')

        >>> validate_json_syntax(Path("broken.json"))  # Missing comma
        (False, 'Line 3, Col 5: Expecting property name...')
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            json.load(f)
        return True, ""
    except json.JSONDecodeError as e:
        return False, f"Line {e.lineno}, Col {e.colno}: {e.msg}"
    except Exception as e:
        return False, str(e)


def validate_variables(
    key: str,
    source_text: str,
    locale_text: str,
    locale: str,
    filename: str,
    issues: list[ValidationIssue],
) -> None:
    """Validate that variables match between English and translation."""
    en_vars = extract_variables(source_text)
    locale_vars = extract_variables(locale_text)

    # Check each variable type
    for var_type in ["vue", "erb", "printf"]:
        missing = en_vars[var_type] - locale_vars[var_type]
        extra = locale_vars[var_type] - en_vars[var_type]

        if missing:
            # Format variable names based on type
            if var_type == "erb":
                var_list = [f"%{{{v}}}" for v in missing]
            elif var_type == "printf":
                var_list = list(missing)
            else:
                var_list = [f"{{{v}}}" for v in missing]

            issues.append(
                ValidationIssue(
                    file=filename,
                    locale=locale,
                    key=key,
                    severity="error",
                    category="variables",
                    message=f"Missing {var_type} variables: {', '.join(var_list)}",
                    details={
                        "source_text": source_text,
                        "locale_text": locale_text,
                        "missing_vars": var_list,
                    },
                )
            )

        if extra:
            # Format variable names based on type
            if var_type == "erb":
                var_list = [f"%{{{v}}}" for v in extra]
            elif var_type == "printf":
                var_list = list(extra)
            else:
                var_list = [f"{{{v}}}" for v in extra]

            issues.append(
                ValidationIssue(
                    file=filename,
                    locale=locale,
                    key=key,
                    severity="error",
                    category="variables",
                    message=f"Extra {var_type} variables: {', '.join(var_list)}",
                    details={
                        "source_text": source_text,
                        "locale_text": locale_text,
                        "extra_vars": var_list,
                    },
                )
            )


def validate_erb_format(
    key: str,
    locale_text: str,
    locale: str,
    filename: str,
    issues: list[ValidationIssue],
) -> None:
    """Validate that email.json uses ERB format, not Vue format."""
    if filename not in RUBY_ONLY_FILES:
        return

    # Check for Vue-style variables in Ruby-only files
    vue_vars = VUE_VAR_PATTERN.findall(locale_text)
    if vue_vars:
        issues.append(
            ValidationIssue(
                file=filename,
                locale=locale,
                key=key,
                severity="error",
                category="format",
                message=f"Use %{{var}} instead of {{var}} in email templates",
                details={
                    "locale_text": locale_text,
                    "wrong_vars": [f"{{{v}}}" for v in vue_vars],
                    "hint": "Email templates are rendered by Ruby, not Vue",
                },
            )
        )


def validate_security_namespace(
    key: str,
    locale_text: str,
    locale: str,
    filename: str,
    issues: list[ValidationIssue],
) -> None:
    """Validate security-critical messages don't reveal sensitive information."""
    # Only check keys in web.auth.security namespace
    if not key.startswith("web.auth.security."):
        return

    # Check for forbidden patterns
    for pattern, risk_type in SECURITY_FORBIDDEN_PATTERNS:
        if re.search(pattern, locale_text, re.IGNORECASE):
            issues.append(
                ValidationIssue(
                    file=filename,
                    locale=locale,
                    key=key,
                    severity="error",
                    category="security",
                    message=f"Security violation: {risk_type}",
                    details={
                        "locale_text": locale_text,
                        "forbidden_pattern": pattern,
                        "risk": risk_type,
                        "guide": "See src/locales/SECURITY-TRANSLATION-GUIDE.md",
                    },
                )
            )


def validate_key_structure(
    en_keys: set[str],
    locale_keys: set[str],
    locale: str,
    filename: str,
    issues: list[ValidationIssue],
) -> None:
    """Validate that locale has same key structure as English."""
    # Filter out metadata keys
    en_real_keys = {k for k in en_keys if not should_skip_key(k)}
    locale_real_keys = {k for k in locale_keys if not should_skip_key(k)}

    # Check for extra keys in locale (not in English)
    extra_keys = locale_real_keys - en_real_keys
    if extra_keys:
        issues.append(
            ValidationIssue(
                file=filename,
                locale=locale,
                key="",
                severity="warning",
                category="structure",
                message=f"Extra keys not in English: {', '.join(sorted(extra_keys)[:5])}{'...' if len(extra_keys) > 5 else ''}",
                details={"extra_keys": sorted(extra_keys)},
            )
        )


def validate_file(
    locale: str,
    filename: str,
    locales_dir: Path,
    verbose: bool = False,
) -> list[ValidationIssue]:
    """Validate a single locale file against its English baseline.

    Performs all validation checks in order:
    1. JSON syntax (fail-fast)
    2. Template variables match English
    3. ERB format for email templates
    4. Security namespace compliance
    5. Key structure consistency

    Args:
        locale: Locale code (e.g., 'es', 'fr', 'de')
        filename: JSON filename (e.g., 'auth.json', 'email.json')
        locales_dir: Path to src/locales directory
        verbose: Print progress messages

    Returns:
        List of ValidationIssue objects found during validation.

    Examples:
        >>> issues = validate_file('es', 'auth.json', Path('src/locales'))
        >>> [i.category for i in issues]
        ['variables', 'security']
    """
    issues = []

    locale_file = locales_dir / locale / filename
    en_file = locales_dir / "en" / filename

    if verbose:
        print(f"Validating {locale}/{filename}...")

    # 1. JSON Syntax (fail fast)
    is_valid, error_msg = validate_json_syntax(locale_file)
    if not is_valid:
        issues.append(
            ValidationIssue(
                file=filename,
                locale=locale,
                key="",
                severity="error",
                category="json",
                message=f"JSON syntax error: {error_msg}",
                details={"error": error_msg},
            )
        )
        return issues  # Can't continue if JSON is invalid

    # Check if English file exists
    if not en_file.exists():
        issues.append(
            ValidationIssue(
                file=filename,
                locale=locale,
                key="",
                severity="warning",
                category="structure",
                message=f"No English baseline found for {filename}",
                details={},
            )
        )
        return issues

    # Load both files
    try:
        with open(en_file, "r", encoding="utf-8") as f:
            en_data = flatten_json(json.load(f))
        with open(locale_file, "r", encoding="utf-8") as f:
            locale_data = flatten_json(json.load(f))
    except Exception as e:
        issues.append(
            ValidationIssue(
                file=filename,
                locale=locale,
                key="",
                severity="error",
                category="json",
                message=f"Failed to load files: {e}",
                details={"error": str(e)},
            )
        )
        return issues

    # 5. Key Structure
    validate_key_structure(set(en_data.keys()), set(locale_data.keys()), locale, filename, issues)

    # Validate each key
    for key, source_text in en_data.items():
        if should_skip_key(key):
            continue

        locale_text = locale_data.get(key, "")

        # Skip if translation doesn't exist
        if not locale_text or key not in locale_data:
            continue

        # 2. Template Variables
        validate_variables(key, source_text, locale_text, locale, filename, issues)

        # 3. ERB Format
        validate_erb_format(key, locale_text, locale, filename, issues)

        # 4. Security Namespace
        validate_security_namespace(key, locale_text, locale, filename, issues)

    return issues


def print_human_format(result: ValidationResult, verbose: bool = False) -> None:
    """Print validation results in human-readable format."""
    if result.passed:
        print(f"✓ All checks passed")
        print(f"  Files checked: {result.files_checked}")
        print(f"  Locales: {', '.join(sorted(result.locales_checked))}")
        return

    print(f"✗ Validation failed with {result.error_count} errors, {result.warning_count} warnings")
    print(f"  Files checked: {result.files_checked}")
    print(f"  Locales: {', '.join(sorted(result.locales_checked))}")
    print()

    # Group issues by file and locale
    by_file = {}
    for issue in result.issues:
        key = f"{issue.locale}/{issue.file}"
        if key not in by_file:
            by_file[key] = []
        by_file[key].append(issue)

    # Print issues grouped by file
    for file_key in sorted(by_file.keys()):
        file_issues = by_file[file_key]
        print(f"\n{file_key}:")

        for issue in file_issues:
            icon = "✗" if issue.severity == "error" else "⚠"
            print(f"  {icon} [{issue.category}] {issue.message}")

            if verbose and issue.key:
                print(f"    Key: {issue.key}")

            if verbose and issue.details:
                for detail_key, detail_value in issue.details.items():
                    if detail_key in ["source_text", "locale_text"]:
                        print(f"    {detail_key}: \"{detail_value}\"")
                    elif isinstance(detail_value, list):
                        print(f"    {detail_key}: {', '.join(str(v) for v in detail_value)}")
                    else:
                        print(f"    {detail_key}: {detail_value}")


def print_json_format(result: ValidationResult) -> None:
    """Print validation results in JSON format for PR comments."""
    output = {
        "passed": result.passed,
        "summary": {
            "errors": result.error_count,
            "warnings": result.warning_count,
            "files_checked": result.files_checked,
            "locales": sorted(result.locales_checked),
        },
        "issues": [
            {
                "file": f"{i.locale}/{i.file}",
                "locale": i.locale,
                "key": i.key,
                "severity": i.severity,
                "category": i.category,
                "message": i.message,
                "details": i.details,
            }
            for i in result.issues
        ],
    }

    print(json.dumps(output, indent=2, ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate locale files in pull requests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--base",
        default="develop",
        help="Base branch for git diff (default: develop)",
    )
    parser.add_argument(
        "--files",
        nargs="+",
        help="Specific files to validate (format: locale/file.json)",
    )
    parser.add_argument(
        "--format",
        choices=["human", "json"],
        default="human",
        help="Output format (default: human)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Detailed progress and issue details",
    )

    args = parser.parse_args()

    # Determine locales directory
    script_dir = Path(__file__).resolve().parent
    # Navigate from src/scripts/locales to src/locales
    locales_dir = script_dir.parent.parent / "locales"

    if not locales_dir.exists():
        print(f"Error: Locales directory not found: {locales_dir}", file=sys.stderr)
        return 1

    # Get files to validate
    if args.files:
        # Manual file specification
        files_to_check = []
        for file_spec in args.files:
            match = re.match(r"^([^/]+)/([^/]+\.json)$", file_spec)
            if match:
                locale, filename = match.groups()
                files_to_check.append((locale, filename))
            else:
                print(f"Error: Invalid file format: {file_spec}", file=sys.stderr)
                print("Expected format: locale/file.json", file=sys.stderr)
                return 1
    else:
        # Get changed files from git
        files_to_check = get_changed_locale_files(args.base)

    if not files_to_check:
        if args.verbose:
            print("No locale files to validate")
        return 0

    if args.verbose:
        print(f"Validating {len(files_to_check)} file(s)...")

    # Validate all files
    result = ValidationResult()
    result.files_checked = len(files_to_check)

    for locale, filename in files_to_check:
        result.locales_checked.add(locale)
        issues = validate_file(locale, filename, locales_dir, args.verbose)
        result.issues.extend(issues)

    # Print results
    if args.format == "json":
        print_json_format(result)
    else:
        print_human_format(result, args.verbose)

    # Exit with error if validation failed
    return 0 if result.passed else 1


if __name__ == "__main__":
    sys.exit(main())
