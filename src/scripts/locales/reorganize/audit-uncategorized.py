#!/usr/bin/env python3
"""
Audits uncategorized.json files for quality issues before reorganization.

Detects:
- Near-duplicate keys (similarity threshold 0.85)
- Near-duplicate values (similarity threshold 0.95)
- Malformed values (backticks, unclosed placeholders)
- Empty values
- Truncated keys (ending in ellipsis patterns)

Usage:
    ./audit-uncategorized.py --locale en           # Audit single locale
    ./audit-uncategorized.py --all                 # Audit all locales
    ./audit-uncategorized.py --locale en --json    # Output JSON only

Exit codes:
    0 = No issues found
    1 = Issues detected
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass, field, asdict
from difflib import SequenceMatcher
from pathlib import Path
from typing import Optional


@dataclass
class LineInfo:
    """Information about a key's location in the source file."""
    line_number: int
    key: str
    value: str


@dataclass
class DuplicateIssue:
    """A pair of near-duplicate keys or values."""
    line1: int
    key1: str
    line2: int
    key2: str
    similarity: float
    issue_type: str  # 'key' or 'value'
    value1: str = ""
    value2: str = ""


@dataclass
class MalformedIssue:
    """A malformed value issue."""
    line: int
    key: str
    value: str
    issue_type: str  # 'backtick', 'unclosed_placeholder', 'template_literal'
    description: str


@dataclass
class EmptyIssue:
    """An empty value issue."""
    line: int
    key: str


@dataclass
class TruncatedIssue:
    """A truncated key issue."""
    line: int
    key: str
    value: str
    description: str


@dataclass
class AuditReport:
    """Complete audit report for a locale."""
    locale: str
    file_path: str
    total_keys: int
    duplicates: list[DuplicateIssue] = field(default_factory=list)
    malformed: list[MalformedIssue] = field(default_factory=list)
    empty: list[EmptyIssue] = field(default_factory=list)
    truncated: list[TruncatedIssue] = field(default_factory=list)

    @property
    def has_issues(self) -> bool:
        return bool(self.duplicates or self.malformed or self.empty or self.truncated)

    @property
    def issue_count(self) -> int:
        return len(self.duplicates) + len(self.malformed) + len(self.empty) + len(self.truncated)


def build_line_map(file_path: Path) -> list[LineInfo]:
    """Build a map of keys to their line numbers by parsing the raw file."""
    line_map = []

    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Pattern to match JSON key-value pairs
    # Handles: "key": "value" or "key": "value",
    key_pattern = re.compile(r'^\s*"([^"]+)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$')

    for line_num, line in enumerate(lines, start=1):
        match = key_pattern.match(line)
        if match:
            key = match.group(1)
            value = match.group(2)
            # Unescape JSON string escapes
            value = value.replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t')
            line_map.append(LineInfo(line_number=line_num, key=key, value=value))

    return line_map


def find_near_duplicates(
    line_map: list[LineInfo],
    key_threshold: float = 0.85,
    value_threshold: float = 0.95
) -> list[DuplicateIssue]:
    """Find near-duplicate keys and values using SequenceMatcher."""
    duplicates = []
    seen_pairs: set[tuple[int, int]] = set()

    for i, item1 in enumerate(line_map):
        for j, item2 in enumerate(line_map):
            if i >= j:
                continue

            # Skip if we've already seen this pair
            pair = (i, j)
            if pair in seen_pairs:
                continue

            # Check key similarity
            key_ratio = SequenceMatcher(None, item1.key, item2.key).ratio()
            if key_ratio >= key_threshold and key_ratio < 1.0:
                seen_pairs.add(pair)
                duplicates.append(DuplicateIssue(
                    line1=item1.line_number,
                    key1=item1.key,
                    line2=item2.line_number,
                    key2=item2.key,
                    similarity=key_ratio,
                    issue_type='key',
                    value1=item1.value,
                    value2=item2.value
                ))

            # Check value similarity (only for non-empty values of reasonable length)
            if item1.value and item2.value and len(item1.value) > 10 and len(item2.value) > 10:
                value_ratio = SequenceMatcher(None, item1.value, item2.value).ratio()
                if value_ratio >= value_threshold and value_ratio < 1.0:
                    if pair not in seen_pairs:
                        seen_pairs.add(pair)
                        duplicates.append(DuplicateIssue(
                            line1=item1.line_number,
                            key1=item1.key,
                            line2=item2.line_number,
                            key2=item2.key,
                            similarity=value_ratio,
                            issue_type='value',
                            value1=item1.value,
                            value2=item2.value
                        ))

    return duplicates


def find_malformed_values(line_map: list[LineInfo]) -> list[MalformedIssue]:
    """Find malformed values: backticks, unclosed placeholders, template literals."""
    malformed = []

    for item in line_map:
        value = item.value

        # Check for backticks (JS template literals leaked into JSON)
        if '`' in value:
            malformed.append(MalformedIssue(
                line=item.line_number,
                key=item.key,
                value=value,
                issue_type='backtick',
                description='Contains backtick character (possible JS template literal)'
            ))

        # Check for unclosed placeholders like {0 without closing }
        # Pattern: {digit(s) not followed by }
        unclosed_pattern = re.compile(r'\{\d+(?![^{]*\})')
        if unclosed_pattern.search(value):
            malformed.append(MalformedIssue(
                line=item.line_number,
                key=item.key,
                value=value,
                issue_type='unclosed_placeholder',
                description='Contains unclosed interpolation placeholder'
            ))

        # Check for JS template literal syntax: ${...} or `...`
        if re.search(r'\$\{[^}]*\}', value):
            malformed.append(MalformedIssue(
                line=item.line_number,
                key=item.key,
                value=value,
                issue_type='template_literal',
                description='Contains JS template literal syntax ${...}'
            ))

        # Check for incomplete ternary expressions (common copy-paste error)
        if re.search(r'\?\s*`[^`]*`\s*:\s*`[^`]*', value) or '? `' in value:
            malformed.append(MalformedIssue(
                line=item.line_number,
                key=item.key,
                value=value,
                issue_type='template_literal',
                description='Contains JS ternary with template literals'
            ))

    return malformed


def find_empty_values(line_map: list[LineInfo]) -> list[EmptyIssue]:
    """Find keys with empty string values."""
    return [
        EmptyIssue(line=item.line_number, key=item.key)
        for item in line_map
        if item.value == ""
    ]


def find_truncated_keys(line_map: list[LineInfo]) -> list[TruncatedIssue]:
    """Find keys that appear to be truncated."""
    truncated = []

    for item in line_map:
        key = item.key

        # Check for keys ending with common truncation patterns
        # e.g., "this-is-an-interactive-preview-o" (ends abruptly)
        if re.search(r'-[a-z]$', key) and len(key) > 30:
            # Likely truncated - single letter at end after dash
            truncated.append(TruncatedIssue(
                line=item.line_number,
                key=key,
                value=item.value,
                description='Key appears truncated (ends with single letter after dash)'
            ))

        # Check for keys with trailing numbers that might indicate duplicates
        # e.g., "about-onetime-secret-0" vs "about-onetime-secret"
        if re.search(r'-\d+$', key):
            base_key = re.sub(r'-\d+$', '', key)
            # Check if base key exists
            for other in line_map:
                if other.key == base_key:
                    truncated.append(TruncatedIssue(
                        line=item.line_number,
                        key=key,
                        value=item.value,
                        description=f'Key has numeric suffix; base key "{base_key}" exists at line {other.line_number}'
                    ))
                    break

    return truncated


def audit_locale(locale_dir: Path, locale: str) -> Optional[AuditReport]:
    """Audit the uncategorized.json file for a locale."""
    uncategorized_file = locale_dir / "uncategorized.json"

    if not uncategorized_file.exists():
        return None

    # Build line map
    line_map = build_line_map(uncategorized_file)

    # Load JSON to get total keys
    with open(uncategorized_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    report = AuditReport(
        locale=locale,
        file_path=str(uncategorized_file),
        total_keys=len(data)
    )

    # Run all checks
    report.duplicates = find_near_duplicates(line_map)
    report.malformed = find_malformed_values(line_map)
    report.empty = find_empty_values(line_map)
    report.truncated = find_truncated_keys(line_map)

    return report


def print_report(report: AuditReport, verbose: bool = True) -> None:
    """Print a human-readable audit report."""
    print(f"\n{'='*60}")
    print(f"Audit Report: {report.locale}")
    print(f"File: {report.file_path}")
    print(f"Total keys: {report.total_keys}")
    print(f"{'='*60}")

    if not report.has_issues:
        print("\nNo issues found.")
        return

    print(f"\nTotal issues: {report.issue_count}")

    if report.duplicates:
        print(f"\n--- Near-Duplicates ({len(report.duplicates)}) ---")
        for dup in report.duplicates:
            print(f"\n  Lines {dup.line1}/{dup.line2}: {dup.issue_type} similarity {dup.similarity:.2f}")
            print(f"    Key 1: {dup.key1}")
            print(f"    Key 2: {dup.key2}")
            if verbose and dup.issue_type == 'value':
                val1 = dup.value1[:80] + "..." if len(dup.value1) > 80 else dup.value1
                val2 = dup.value2[:80] + "..." if len(dup.value2) > 80 else dup.value2
                print(f"    Value 1: {val1}")
                print(f"    Value 2: {val2}")

    if report.malformed:
        print(f"\n--- Malformed Values ({len(report.malformed)}) ---")
        for issue in report.malformed:
            print(f"\n  Line {issue.line}: {issue.key}")
            print(f"    Type: {issue.issue_type}")
            print(f"    Description: {issue.description}")
            if verbose:
                val = issue.value[:100] + "..." if len(issue.value) > 100 else issue.value
                print(f"    Value: {val}")

    if report.empty:
        print(f"\n--- Empty Values ({len(report.empty)}) ---")
        for issue in report.empty:
            print(f"  Line {issue.line}: {issue.key}")

    if report.truncated:
        print(f"\n--- Truncated/Duplicate Keys ({len(report.truncated)}) ---")
        for issue in report.truncated:
            print(f"\n  Line {issue.line}: {issue.key}")
            print(f"    Description: {issue.description}")


def report_to_dict(report: AuditReport) -> dict:
    """Convert report to JSON-serializable dict."""
    return {
        "locale": report.locale,
        "file_path": report.file_path,
        "total_keys": report.total_keys,
        "issue_count": report.issue_count,
        "has_issues": report.has_issues,
        "duplicates": [asdict(d) for d in report.duplicates],
        "malformed": [asdict(m) for m in report.malformed],
        "empty": [asdict(e) for e in report.empty],
        "truncated": [asdict(t) for t in report.truncated]
    }


def get_relative_path(path: Path) -> str:
    """Get path relative to current working directory."""
    try:
        resolved = path.resolve()
        return str(resolved.relative_to(Path.cwd().resolve()))
    except ValueError:
        return str(path)


def main():
    parser = argparse.ArgumentParser(
        description="Audit uncategorized.json files for quality issues"
    )
    parser.add_argument(
        "--locale",
        help="Locale code to audit (e.g., 'en', 'fr_FR')"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Audit all locales"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output JSON report only"
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write JSON report to file"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show detailed values in report"
    )
    parser.add_argument(
        "-q", "--quiet",
        action="store_true",
        help="Minimal output (exit code only)"
    )
    parser.add_argument(
        "--key-threshold",
        type=float,
        default=0.85,
        help="Similarity threshold for near-duplicate keys (default: 0.85)"
    )
    parser.add_argument(
        "--value-threshold",
        type=float,
        default=0.95,
        help="Similarity threshold for near-duplicate values (default: 0.95)"
    )

    args = parser.parse_args()

    # Validate arguments
    if not args.locale and not args.all:
        parser.error("Either --locale or --all must be specified")

    if args.locale and args.all:
        parser.error("Cannot specify both --locale and --all")

    # Determine locales directory
    script_dir = Path(__file__).parent
    locales_dir = (script_dir / "../../../locales").resolve()

    if not locales_dir.is_dir():
        print(f"Error: Locales directory not found: {locales_dir}", file=sys.stderr)
        return 1

    # Determine which locales to audit
    locales_to_audit = []
    if args.all:
        locales_to_audit = [
            d.name for d in locales_dir.iterdir()
            if d.is_dir() and not d.name.startswith(".")
        ]
    else:
        locales_to_audit = [args.locale]

    # Run audits
    reports = []
    total_issues = 0

    for locale in sorted(locales_to_audit):
        locale_dir = locales_dir / locale
        if not locale_dir.is_dir():
            if not args.quiet and not args.json:
                print(f"Warning: Locale directory not found: {locale}", file=sys.stderr)
            continue

        report = audit_locale(locale_dir, locale)
        if report:
            reports.append(report)
            total_issues += report.issue_count

    # Output results
    if args.json or args.output:
        output_data = {
            "summary": {
                "locales_audited": len(reports),
                "total_issues": total_issues,
                "locales_with_issues": sum(1 for r in reports if r.has_issues)
            },
            "reports": [report_to_dict(r) for r in reports]
        }

        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(output_data, f, indent=2, ensure_ascii=False)
                f.write("\n")
            if not args.quiet:
                print(f"Report written to: {args.output}")
        else:
            print(json.dumps(output_data, indent=2, ensure_ascii=False))
    elif not args.quiet:
        for report in reports:
            print_report(report, verbose=args.verbose)

        # Summary
        print(f"\n{'='*60}")
        print("SUMMARY")
        print(f"{'='*60}")
        print(f"Locales audited: {len(reports)}")
        print(f"Total issues: {total_issues}")
        locales_with_issues = [r.locale for r in reports if r.has_issues]
        if locales_with_issues:
            print(f"Locales with issues: {', '.join(locales_with_issues)}")
        else:
            print("All locales clean.")

    # Exit code
    return 1 if total_issues > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
