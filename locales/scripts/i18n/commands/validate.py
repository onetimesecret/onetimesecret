# locales/scripts/i18n/commands/validate.py

"""``validate`` command group.

Ports the legacy locale validation scripts as subcommands:

* ``pr``        -- ports ``locales/scripts/validate/pr.py`` (PR/git-diff based
  structural validation: JSON syntax, variable preservation, ERB format,
  security namespace, key structure).
* ``variables`` -- ports ``locales/scripts/validate/variables.py`` (variable
  discrepancy audit between the source locale and translations).

Path constants come from :mod:`i18n.config` (``CONTENT_DIR``, ``SOURCE_LOCALE``,
``iter_locale_dirs``) instead of being re-derived from this file's location or
the ``.git`` directory. All flags, defaults, help text, output formatting and
exit codes are otherwise preserved verbatim from the old scripts.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from ..config import CONTENT_DIR, RESOLVED_DIR, SOURCE_LOCALE, iter_locale_dirs
from ..io import classify_entry, load_json_file, read_entries, walk_keys
from ..tokens import (  # noqa: F401  (re-exported: historical public names)
    ERB_VAR_PATTERN,
    PRINTF_PATTERN,
    VUE_VAR_PATTERN,
    extract_variables,
)

# ---------------------------------------------------------------------------
# Shared variable patterns
# ---------------------------------------------------------------------------
# The patterns and `extract_variables` moved to :mod:`i18n.tokens` -- ONE
# definition of "what is a token", shared with ``tasks audit``. Twin
# normalizers drifting apart has bitten this repo twice (#4023, #4047), so do
# not re-declare them here. Imported under their historical names, so every
# call site below (and any outside importer) is unchanged.

# Files that must use Ruby ERB format only (%{var}), not Vue ({var}).
# Email templates are rendered server-side by Ruby, not by Vue.
RUBY_ONLY_FILES = {"email.json"}


# ===========================================================================
# Subcommand: validate pr   (ported from locales/scripts/validate/pr.py)
# ===========================================================================

# Security namespace forbidden patterns
SECURITY_FORBIDDEN_PATTERNS = [
    # Credential-specific reveals
    (
        r"\b(wrong|incorrect|invalid)\s+(password|otp|code|recovery)",
        "credential-specific failure",
    ),
    (
        r"\bpassword\s+(wrong|incorrect|invalid|failed)",
        "credential-specific failure",
    ),
    (
        r"\botp\s+(wrong|incorrect|invalid|failed)",
        "credential-specific failure",
    ),
    (
        r"\b(recovery\s+)?code\s+(wrong|incorrect|invalid|does\s+not\s+exist)",
        "credential-specific failure",
    ),
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


def should_skip_key_pr(key: str) -> bool:
    """Check if a key should be skipped (metadata keys with _ prefix)."""
    parts = key.split(".")
    return any(part.startswith("_") for part in parts)


def get_changed_locale_files(base_branch: str) -> list[tuple[str, str]]:
    """Get list of changed locale files from git diff.

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

            # Match locales/content/{locale}/{file.json}
            match = re.match(r"^locales/content/([^/]+)/([^/]+\.json)$", line)
            if match:
                locale, filename = match.groups()
                if locale != SOURCE_LOCALE:  # Skip source baseline
                    changed_files.append((locale, filename))

        return changed_files

    except subprocess.CalledProcessError as e:
        print(f"Error running git diff: {e}", file=sys.stderr)
        return []


def validate_json_syntax(file_path: Path) -> tuple[bool, str]:
    """Validate JSON syntax and UTF-8 encoding.

    Returns:
        Tuple of (is_valid, error_message). Error message is empty on success.
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
                message="Use %{var} instead of {var} in email templates",
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
                        "guide": "See locales/guides/SECURITY-TRANSLATION-GUIDE.md",
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
    en_real_keys = {k for k in en_keys if not should_skip_key_pr(k)}
    locale_real_keys = {k for k in locale_keys if not should_skip_key_pr(k)}

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
    """
    issues = []

    locale_file = locales_dir / locale / filename
    en_file = locales_dir / SOURCE_LOCALE / filename

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

    # Load both files. Entry-aware: keys are the real dotted paths, and each
    # entry's authoring metadata stays metadata. The field-blind flattener this
    # replaces made every translated file trip the "Extra keys not in English"
    # structure check on `<key>.source_hash` — a warning, so `passed` stayed
    # true and nobody noticed. Same root cause as #4080; making that check
    # blocking without this would have reopened it in the PR gate.
    try:
        with open(en_file, "r", encoding="utf-8") as f:
            en_entries = read_entries(json.load(f))
        with open(locale_file, "r", encoding="utf-8") as f:
            locale_entries = read_entries(json.load(f))
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
    validate_key_structure(
        set(en_entries.keys()),
        set(locale_entries.keys()),
        locale,
        filename,
        issues,
    )

    # 6. Entry schema. `io.METADATA_FIELDS` is the single declaration of what an
    # entry may carry; anything else is a field nobody taught the readers about,
    # and a field-blind reader would guess at it. Surface it here rather than
    # letting the next added field silently become translatable.
    unknown_fields = sorted(
        {field for entry in locale_entries.values() for field in entry.extra}
    )
    if unknown_fields:
        issues.append(
            ValidationIssue(
                file=filename,
                locale=locale,
                key="",
                severity="warning",
                category="structure",
                message=(
                    "Unrecognized entry field(s): "
                    f"{', '.join(unknown_fields)} — declare them in "
                    "i18n.io.METADATA_FIELDS or remove them"
                ),
                details={"unknown_fields": unknown_fields},
            )
        )

    # Validate each key
    for key, en_entry in en_entries.items():
        if should_skip_key_pr(key):
            continue

        source_text = en_entry.text
        if source_text is None:
            continue

        # Only a live translation can be compared. `skipped` (deliberate
        # non-translation) and `missing` (absent or empty) are coverage states,
        # reported by `tasks next`, not placeholder defects.
        if classify_entry(locale_entries.get(key)) != "current":
            continue

        locale_text = locale_entries[key].text or ""

        # 2. Template Variables
        validate_variables(
            key, source_text, locale_text, locale, filename, issues
        )

        # 3. ERB Format
        validate_erb_format(key, locale_text, locale, filename, issues)

        # 4. Security Namespace
        validate_security_namespace(key, locale_text, locale, filename, issues)

    return issues


def print_human_format(result: ValidationResult, verbose: bool = False) -> None:
    """Print validation results in human-readable format."""
    if result.passed:
        print("✓ All checks passed")
        print(f"  Files checked: {result.files_checked}")
        print(f"  Locales: {', '.join(sorted(result.locales_checked))}")
        return

    print(
        f"✗ Validation failed with {result.error_count} errors, {result.warning_count} warnings"
    )
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
                        print(f'    {detail_key}: "{detail_value}"')
                    elif isinstance(detail_value, list):
                        print(
                            f"    {detail_key}: {', '.join(str(v) for v in detail_value)}"
                        )
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


def _pr_handler(args) -> int:
    """Handler for ``validate pr`` (ported from validate/pr.py:main)."""
    locales_dir = CONTENT_DIR

    if not locales_dir.exists():
        print(
            f"Error: Locales directory not found: {locales_dir}",
            file=sys.stderr,
        )
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
                print(
                    f"Error: Invalid file format: {file_spec}", file=sys.stderr
                )
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


# ===========================================================================
# Subcommand: validate variables (ported from validate/variables.py)
# ===========================================================================

# Date stamp for error IDs (MMDD format)
DATE_STAMP = datetime.now().strftime("%m%d")


def should_skip_key_vars(
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


# Every finding carries a `category`. Splitting them is what lets the shell
# gate read the report as-is: `untranslated` is a COVERAGE signal (the en key
# has placeholders and the locale has no translation yet), not a placeholder
# defect, and export-all.sh already gates coverage upstream on `tasks next
# --stats` reporting pending: 0. Counting it here made every locale report a
# permanent, unfixable "34 variable mismatches" after a byte-perfect export —
# which is exactly why the previous gate post-filtered the report in shell, and
# why that filter then had to guess at key shapes. A gate consumers must
# post-filter is a gate that will be mis-filtered.
ISSUE_CATEGORIES = ("variables", "format", "untranslated", "error")
ADVISORY_CATEGORIES = frozenset({"untranslated"})


def format_var(var_type: str, var: str) -> str:
    """Render one extracted variable back into its source syntax."""
    if var_type == "printf":
        return var
    if var_type == "erb":
        return f"%{{{var}}}"
    return f"{{{var}}}"


def format_vars(by_type: dict[str, set[str]]) -> list[str]:
    """Render a ``{var_type: {var, ...}}`` mapping as a sorted display list."""
    return [
        format_var(var_type, var)
        for var_type in sorted(by_type)
        for var in sorted(by_type[var_type])
    ]


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

        # Entry-aware: keys are the real dotted paths, `text` is the only field
        # compared, and skip/absent/empty stay distinguishable (io.Entry keeps
        # all three; the text-only view collapses them).
        try:
            with open(en_file, "r", encoding="utf-8") as f:
                en_entries = read_entries(json.load(f))
            with open(locale_file, "r", encoding="utf-8") as f:
                locale_entries = read_entries(json.load(f))
        except (OSError, json.JSONDecodeError) as e:
            issues[en_file.name].append(
                {
                    "key": "_file_error",
                    "category": "error",
                    "error": str(e),
                }
            )
            continue

        for key, en_entry in en_entries.items():
            if should_skip_key_vars(key, filter_prefix, exclude_prefix):
                continue

            source_text = en_entry.text
            if source_text is None:
                continue

            # No en hash is passed: placeholder parity does not care whether a
            # translation is stale — a stale one still has text to compare — so
            # the states that matter here are skipped / missing / current.
            state = classify_entry(locale_entries.get(key))
            locale_text = (
                locale_entries[key].text or "" if state == "current" else ""
            )

            # Wrong variable format in Ruby-only files (e.g. email.json): the
            # English source should use %{var}, not {var}. A property of the
            # source, so it is reported whether or not the locale has caught up.
            wrong_format_en = check_wrong_format(source_text, en_file.name)
            if wrong_format_en:
                issues[en_file.name].append(
                    {
                        "key": key,
                        "category": "format",
                        "source_text": source_text,
                        "locale_text": locale_text,
                        "wrong_format": wrong_format_en,
                        "wrong_format_source": "en",
                        "hint": "Use %{var} instead of {var} for Ruby i18n",
                    }
                )
                # Continue to also check for other issues

            # A skip-marked entry is a deliberate non-translation (keep the
            # source as-is). It is not an empty translation and not a defect.
            if state == "skipped":
                continue

            if state == "missing":
                all_vars = format_vars(extract_variables(source_text))
                if all_vars:
                    issues[en_file.name].append(
                        {
                            "key": key,
                            "category": "untranslated",
                            "source_text": source_text,
                            "locale_text": "[EMPTY]",
                            "missing": all_vars,
                            "extra": [],
                            "empty_with_vars": True,
                        }
                    )
                continue

            # Check wrong format in the translation too
            wrong_format_locale = check_wrong_format(locale_text, en_file.name)
            if wrong_format_locale:
                issues[en_file.name].append(
                    {
                        "key": key,
                        "category": "format",
                        "source_text": source_text,
                        "locale_text": locale_text,
                        "wrong_format": wrong_format_locale,
                        "wrong_format_source": "locale",
                        "hint": "Use %{var} instead of {var} for Ruby i18n",
                    }
                )

            # Compare variables
            discrepancies = compare_variables(source_text, locale_text)

            if discrepancies:
                issues[en_file.name].append(
                    {
                        "key": key,
                        "category": "variables",
                        "source_text": source_text,
                        "locale_text": locale_text,
                        "missing": format_vars(
                            {t: d["missing"] for t, d in discrepancies.items()}
                        ),
                        "extra": format_vars(
                            {t: d["extra"] for t, d in discrepancies.items()}
                        ),
                    }
                )

    return dict(issues)


def count_by_category(files: dict[str, list[dict]]) -> dict[str, int]:
    """Count one locale's findings per :data:`ISSUE_CATEGORIES`."""
    counts = dict.fromkeys(ISSUE_CATEGORIES, 0)
    for file_issues in files.values():
        for issue in file_issues:
            category = issue.get("category", "variables")
            counts[category] = counts.get(category, 0) + 1
    return counts


def blocking_count(counts: dict[str, int]) -> int:
    """Findings that gate an export: everything not explicitly advisory.

    A deny-list, deliberately: a category added later counts by default rather
    than slipping past the gate because nobody updated an allow-list.
    """
    return sum(n for c, n in counts.items() if c not in ADVISORY_CATEGORIES)


def print_summary(results: dict[str, dict[str, list[dict]]]) -> None:
    """Print summary of discrepancies by locale."""
    rows = []
    for locale, files in results.items():
        counts = count_by_category(files)
        if any(counts.values()):
            rows.append((locale, counts, blocking_count(counts)))

    if not rows:
        print("0 blocking, 0 untranslated")
        return

    rows.sort(key=lambda row: (-row[2], -sum(row[1].values()), row[0]))

    for locale, counts, blocking in rows:
        print(
            f"{locale}: {blocking} blocking, "
            f"{counts['untranslated']} untranslated"
        )

    totals = dict.fromkeys(ISSUE_CATEGORIES, 0)
    for _, counts, _ in rows:
        for category, n in counts.items():
            totals[category] = totals.get(category, 0) + n

    print(
        f"TOTAL: {blocking_count(totals)} blocking "
        f"({totals['variables']} variable, {totals['format']} format, "
        f"{totals['error']} error), {totals['untranslated']} untranslated"
    )


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

                print(
                    f"  key:      {issue['key']}  "
                    f"[{issue.get('category', 'variables')}]"
                )
                print(f'  en:       "{issue["source_text"]}"')
                print(f"  {locale}:".ljust(12) + f'"{issue["locale_text"]}"')
                if issue.get("wrong_format"):
                    source = issue.get("wrong_format_source", "unknown")
                    print(
                        f"  wrong_fmt: {', '.join(issue['wrong_format'])} (in {source})"
                    )
                    print(f"  hint:     {issue.get('hint', '')}")
                if issue.get("missing"):
                    print(f"  missing:  {', '.join(issue['missing'])}")
                if issue.get("extra"):
                    print(f"  comment:  {', '.join(issue['extra'])}")
                print(f"  errorid:  {error_id}")
                print()


def print_json(results: dict[str, dict[str, list[dict]]]) -> None:
    """Print machine-readable JSON output.

    ``summary`` is per-locale, per-category; ``blocking`` is the single number
    a gate should read (the sum of every non-advisory category across every
    locale). Consumers that predate this shape summed ``summary`` as integers —
    ``blocking`` exists so they do not have to re-derive the policy, and so the
    next category cannot silently change what a gate counts.
    """
    output = {
        "date": DATE_STAMP,
        "blocking": 0,
        "summary": {},
        "details": {},
    }

    for locale, files in results.items():
        counts = count_by_category(files)
        if any(counts.values()):
            output["summary"][locale] = counts
            output["blocking"] += blocking_count(counts)

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


def _variables_handler(args) -> int:
    """Handler for ``validate variables`` (ported from variables.py:main)."""
    content_dir = CONTENT_DIR

    if not content_dir.exists():
        print(
            f"Error: Content directory not found: {content_dir}",
            file=sys.stderr,
        )
        return 1

    source_dir = content_dir / SOURCE_LOCALE
    if not source_dir.exists():
        print(f"Error: Source locale not found: {source_dir}", file=sys.stderr)
        return 1

    # Get list of locales to check
    if args.locale:
        locale_dirs = [content_dir / args.locale]
        if not locale_dirs[0].exists():
            print(f"Error: Locale not found: {args.locale}", file=sys.stderr)
            return 1
    else:
        locale_dirs = iter_locale_dirs(include_source=False)

    # Audit each locale
    results = {}
    warned_missing_file: set[str] = set()
    for locale_dir in sorted(locale_dirs):
        locale_name = locale_dir.name
        issues = audit_locale(
            source_dir,
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

    # Exit code is the BLOCKING count (max 100) for CI. Untranslated keys are
    # reported but not counted here: coverage is `tasks next`'s gate, and an
    # exit code that mixes the two is one more number consumers have to
    # post-filter.
    total_blocking = sum(
        blocking_count(count_by_category(files)) for files in results.values()
    )
    return min(total_blocking, 100)


# ===========================================================================
# Subcommand: validate glossary (bound-glossary divergence, advisory)
# ===========================================================================

# What counts as "the term appears" in the English source. A glossary term is an
# English word (secret, burn, email); match it whole-word, case-insensitive, so
# "secret" does not fire on "secretary".
def _term_regex(term: str) -> re.Pattern:
    return re.compile(rf"\b{re.escape(term)}\b", re.IGNORECASE)


def load_bound_glossary(locale: str) -> dict[str, list[str]] | None:
    """Load the BOUND glossary for ``locale`` from the resolved governance file.

    Returns ``{en_term: [rendering, ...]}`` drawn from each entry's
    ``senses[*].target`` (plus a top-level ``target`` if present) — the binding
    renderings a translation is expected to use. Distinct from the committable DB
    ``glossary`` table (local decisions); this is the upstream authority agents
    honor, derived on demand by ``derive-governance.sh``.

    Returns ``None`` when the resolved file is absent (governance not derived, or
    the locale is ungoverned at the pin) so the caller can skip cleanly.
    """
    resolved = RESOLVED_DIR / f"{locale}.json"
    if not resolved.exists():
        return None

    try:
        with open(resolved, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None

    glossary = data.get("glossary")
    if not isinstance(glossary, dict):
        return {}

    bound: dict[str, list[str]] = {}
    for term, info in glossary.items():
        if not isinstance(info, dict):
            continue
        en_term = info.get("en") or term
        renderings: list[str] = []
        senses = info.get("senses")
        if isinstance(senses, dict):
            for sense in senses.values():
                if isinstance(sense, dict) and sense.get("target"):
                    renderings.append(sense["target"])
        if info.get("target"):
            renderings.append(info["target"])
        # Keep only non-empty string renderings, and MERGE into any existing
        # entry: two glossary keys can share one `en` (e.g. secret_noun +
        # secret_adjective both en="secret"), and overwriting would drop one
        # sense's renderings and manufacture spurious divergences. Preserve
        # first-seen order, de-dup across the merge.
        existing = bound.setdefault(en_term, [])
        for r in renderings:
            if isinstance(r, str) and r.strip() and r not in existing:
                existing.append(r)
        if not existing:
            del bound[en_term]
    return bound


def audit_glossary_locale(
    locale: str, bound: dict[str, list[str]]
) -> list[dict[str, Any]]:
    """Flag translated keys whose source uses a bound term but whose translation
    contains none of that term's bound renderings.

    Heuristic and advisory: rendering match is a case-insensitive substring
    (citation form), so morphology/inflection can produce false positives —
    every finding is a prompt for human judgment, not a hard failure. Only keys
    with a live en source string and a non-empty, non-skipped translation are
    considered.
    """
    findings: list[dict[str, Any]] = []
    term_patterns = {term: _term_regex(term) for term in bound}

    locale_dir = CONTENT_DIR / locale
    source_dir = CONTENT_DIR / SOURCE_LOCALE
    if not locale_dir.exists():
        return findings

    for locale_file in sorted(locale_dir.glob("*.json")):
        en_file = source_dir / locale_file.name
        if not en_file.exists():
            continue

        # The translatable-text view is the right reader here: a glossary term
        # can only diverge in a live translation, and walk_keys drops exactly
        # the entries (skipped, untranslated) this heuristic must not judge.
        en_data = dict(walk_keys(load_json_file(en_file)))
        locale_data = dict(walk_keys(load_json_file(locale_file)))

        for key, source_text in en_data.items():
            if should_skip_key_pr(key):
                continue
            translation = locale_data.get(key, "")
            if not translation:
                continue

            translation_cf = translation.casefold()
            for term, pattern in term_patterns.items():
                if not pattern.search(source_text):
                    continue
                renderings = bound[term]
                if any(r.casefold() in translation_cf for r in renderings):
                    continue
                findings.append(
                    {
                        "file": locale_file.name,
                        "key": key,
                        "term": term,
                        "expected": renderings,
                        "source_text": source_text,
                        "locale_text": translation,
                    }
                )

    return findings


def _glossary_handler(args) -> int:
    """Handler for ``validate glossary`` (bound-glossary divergence)."""
    if args.locale:
        locales = [args.locale]
    else:
        locales = [d.name for d in iter_locale_dirs(include_source=False)]

    total = 0
    checked = 0
    skipped: list[str] = []

    for locale in locales:
        bound = load_bound_glossary(locale)
        if bound is None:
            skipped.append(locale)
            continue
        checked += 1
        if not bound:
            continue

        findings = audit_glossary_locale(locale, bound)
        total += len(findings)

        if findings:
            print(f"\n{locale}: {len(findings)} possible divergence(s)")
            for f in findings:
                print(f"  {f['file']} · {f['key']}")
                print(f"    term:     {f['term']} → expected {f['expected']}")
                print(f'    en:       "{f["source_text"]}"')
                print(f'    {locale}: "{f["locale_text"]}"')

    if skipped:
        print(
            f"\nSkipped (no resolved governance — run derive-governance.sh): "
            f"{', '.join(sorted(skipped))}",
            file=sys.stderr,
        )
    if checked == 0:
        print(
            "No resolved governance found for any target locale; nothing checked.",
            file=sys.stderr,
        )

    print(f"\nTOTAL: {total} possible glossary divergence(s) across {checked} locale(s)")
    # Advisory by default (heuristic → false positives). --strict gates for CI:
    # fail on any divergence, and also fail when NOTHING could be checked (no
    # resolved governance) — a gate that verifies nothing must not read green.
    if args.strict and (total or checked == 0):
        return 1
    return 0


# ===========================================================================
# validate hashes  (en source content_hash freshness gate)
# ===========================================================================


def _hashes_handler(args) -> int:
    """Verify every en source key's ``content_hash`` matches its ``text``.

    Mirrors the invariant maintained by ``content hashes``
    (:func:`_hashes_add_to_source`): every entry with non-empty ``text`` in
    ``locales/content/en/*.json`` must carry ``content_hash`` equal to
    ``sha256(text.strip())[:8]``. A stale or missing hash means the stamping
    step lagged a source edit — run ``content hashes`` to repair.
    """
    from .content import _hashes_compute_hash

    source_dir = CONTENT_DIR / SOURCE_LOCALE
    mismatched: list[tuple[str, str, str, str]] = []  # file, key, stored, computed
    missing: list[tuple[str, str, str]] = []  # file, key, computed
    checked = 0

    for json_file in sorted(source_dir.glob("*.json")):
        data = load_json_file(json_file)
        for key_path, entry in data.items():
            if not isinstance(entry, dict):
                continue
            text = entry.get("text", "")
            if not isinstance(text, str) or not text:
                continue
            checked += 1
            computed = _hashes_compute_hash(text)
            stored = entry.get("content_hash")
            if not stored:
                missing.append((json_file.name, key_path, computed))
            elif stored != computed:
                mismatched.append((json_file.name, key_path, stored, computed))

    for file_name, key, stored, computed in mismatched:
        print(f"STALE   {file_name} · {key}: stored {stored} != computed {computed}")
    for file_name, key, computed in missing:
        print(f"MISSING {file_name} · {key}: no content_hash (computed {computed})")

    print(
        f"\nChecked {checked} en source key(s): "
        f"{len(mismatched)} stale, {len(missing)} missing content_hash"
    )
    if mismatched or missing:
        print(
            "Fix: python3 locales/scripts/i18n content hashes",
            file=sys.stderr,
        )
        return 1
    return 0


# ===========================================================================
# Registration
# ===========================================================================

_VARIABLES_EPILOG = """
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
"""


def register(subparsers) -> None:
    g = subparsers.add_parser("validate", help="Locale validation checks")
    gsub = g.add_subparsers(dest="cmd", required=True)

    # ----- validate pr -----
    pr = gsub.add_parser(
        "pr",
        help="Validate changed locale files in pull requests",
        description="Validate locale files in pull requests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    pr.add_argument(
        "--base",
        default="develop",
        help="Base branch for git diff (default: develop)",
    )
    pr.add_argument(
        "--files",
        nargs="+",
        help="Specific files to validate (format: locale/file.json)",
    )
    pr.add_argument(
        "--format",
        choices=["human", "json"],
        default="human",
        help="Output format (default: human)",
    )
    pr.add_argument(
        "--verbose",
        action="store_true",
        help="Detailed progress and issue details",
    )
    pr.set_defaults(func=_pr_handler)

    # ----- validate variables -----
    variables = gsub.add_parser(
        "variables",
        help="Detect variable discrepancies between locales",
        description="Detect variable discrepancies in i18n locale files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=_VARIABLES_EPILOG,
    )
    output_group = variables.add_mutually_exclusive_group()
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
    variables.add_argument(
        "--locale",
        metavar="XX",
        help="Check only specific locale (e.g., es, fr_FR)",
    )
    variables.add_argument(
        "--file",
        metavar="FILE",
        help="Check only specific file (e.g., email.json)",
    )
    variables.add_argument(
        "--filter",
        metavar="PREFIX",
        help="Only include keys starting with PREFIX (e.g., email.welcome)",
    )
    variables.add_argument(
        "--exclude",
        metavar="PREFIX",
        help="Exclude keys starting with PREFIX (e.g., web.COMMON)",
    )
    variables.set_defaults(func=_variables_handler)

    # ----- validate glossary -----
    glossary = gsub.add_parser(
        "glossary",
        help="Flag translations diverging from bound glossary renderings",
        description=(
            "Advisory check: for each translated key whose English source uses a "
            "bound glossary term, verify the translation contains one of that "
            "term's bound renderings (senses[*].target from "
            "generated/i18n/.resolved/<locale>.json). Heuristic — substring match "
            "on the citation form, so inflection can yield false positives; "
            "findings are prompts for review, not hard errors."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Requires resolved governance (run locales/scripts/derive-governance.sh first).
Locales without it are skipped with a warning.

Examples:
  %(prog)s de              # check one locale
  %(prog)s                 # check every governed target locale
  %(prog)s de --strict     # exit non-zero if any divergence (CI gate)
""",
    )
    glossary.add_argument(
        "locale",
        nargs="?",
        help="Target locale code (e.g., 'de'). Omit to check all governed locales.",
    )
    glossary.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero when divergences are found (default: advisory, exit 0).",
    )
    glossary.set_defaults(func=_glossary_handler)

    # ----- validate hashes -----
    hashes = gsub.add_parser(
        "hashes",
        help="Verify en source content_hash values match the current text",
        description=(
            "CI gate: recompute sha256(text.strip())[:8] for every en source "
            "key with non-empty text and compare against its stored "
            "content_hash. Exits non-zero listing stale or missing hashes; "
            "repair with 'content hashes'."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    hashes.set_defaults(func=_hashes_handler)
