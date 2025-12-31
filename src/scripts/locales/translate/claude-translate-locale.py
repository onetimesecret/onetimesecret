#!/usr/bin/env python3
"""
Translate a single locale using Claude CLI.

Usage:
    ./claude-translate-locale.py LOCALE [OPTIONS]

Examples:
    ./claude-translate-locale.py pt_PT
    ./claude-translate-locale.py ru --dry-run
    ./claude-translate-locale.py de_AT --no-commit
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional


class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    NC = "\033[0m"


def log_info(msg: str) -> None:
    print(f"{Colors.GREEN}[INFO]{Colors.NC} {msg}")


def log_warn(msg: str) -> None:
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")


def log_error(msg: str) -> None:
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}", file=sys.stderr)


@dataclass
class TranslationEntry:
    """A single string to translate."""
    file: str
    key: str
    english: str
    translated: str = ""


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=check)


def get_available_locales(locales_dir: Path) -> list[str]:
    if not locales_dir.is_dir():
        return []
    return sorted(
        d.name for d in locales_dir.iterdir()
        if d.is_dir() and not d.name.startswith(".") and d.name != "en"
    )


def extract_entries_from_diff(diff_output: str) -> list[TranslationEntry]:
    """Extract translation entries from git diff.

    Parses added lines like: +  "key": "English value",
    Returns list of TranslationEntry objects.
    """
    entries: list[TranslationEntry] = []
    current_file = None

    # Pattern: +  "key": "value"  or  +  "key": "value",
    line_pattern = re.compile(r'^\+\s*"([^"]+)"\s*:\s*"([^"]*)"')

    for line in diff_output.splitlines():
        # Track current file from diff header
        if line.startswith("diff --git"):
            match = re.search(r'b/src/locales/[^/]+/([^/]+\.json)', line)
            if match:
                current_file = match.group(1)

        # Extract from added lines (skip +++ header)
        elif line.startswith("+") and not line.startswith("+++"):
            match = line_pattern.match(line)
            if match and current_file:
                key = match.group(1)
                value = match.group(2)

                # Skip if not English (already translated)
                if value and is_english(value):
                    entries.append(TranslationEntry(
                        file=current_file,
                        key=key,
                        english=value,
                    ))

    return entries


def is_english(value: str) -> bool:
    """Check if string appears to be English (needs translation)."""
    if not value.strip():
        return False
    # Skip URLs
    if value.startswith(("http://", "https://", "mailto:")):
        return False
    # Skip pure placeholders
    if re.match(r'^[\{\}0-9a-z_@:\.]+$', value):
        return False
    # Check if mostly ASCII (English)
    ascii_ratio = sum(1 for c in value if ord(c) < 128) / len(value)
    return ascii_ratio > 0.8


def build_prompt(locale: str, entries: list[TranslationEntry], export_guide: Optional[str]) -> str:
    """Build prompt with JSON array of entries."""
    # Convert entries to simple dicts for Claude
    items = [{"key": e.key, "english": e.english} for e in entries]

    prompt = f"""Translate these UI strings from English to {locale} for OneTime Secret.

## Rules
1. PRESERVE variables exactly: {{time}}, {{count}}, {{0}}, {{1}}, etc.
2. Keep HTML tags: <a>, <strong>, <br>
3. "secret" = culturally appropriate term
4. password (login) vs passphrase (protects secrets)

## Output Format
Return a JSON array with translations added. Example:
[
  {{"key": "example_key", "english": "Hello", "translated": "مرحبا"}},
  ...
]

Return ONLY the JSON array, no markdown, no explanation.
"""

    if export_guide:
        prompt += f"\n## Translation Guide\n{export_guide[:2000]}\n"

    prompt += f"\n## Strings to Translate\n{json.dumps(items, indent=2, ensure_ascii=False)}"

    return prompt


def parse_response(claude_output: str) -> list[dict]:
    """Parse Claude's JSON array response."""
    # Try to find JSON array in output
    # Remove markdown code blocks if present
    text = claude_output.strip()
    if "```" in text:
        match = re.search(r'```(?:json)?\s*(\[.*?\])\s*```', text, re.DOTALL)
        if match:
            text = match.group(1)

    # Find the array
    start = text.find("[")
    end = text.rfind("]") + 1
    if start >= 0 and end > start:
        text = text[start:end]

    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        log_error(f"Failed to parse JSON: {e}")
        log_warn(f"Raw output:\n{claude_output[:500]}")
        return []


def apply_translations(
    locale_dir: Path,
    entries: list[TranslationEntry],
    translations: list[dict],
    verbose: bool = False,
) -> int:
    """Apply translations by replacing English strings in files."""
    # Build lookup: english -> translated
    trans_map = {t["english"]: t.get("translated", "") for t in translations if t.get("translated")}

    if verbose:
        log_info(f"Translation map has {len(trans_map)} entries")

    # Group entries by file
    by_file: dict[str, list[TranslationEntry]] = {}
    for entry in entries:
        by_file.setdefault(entry.file, []).append(entry)

    total_replaced = 0

    for filename, file_entries in by_file.items():
        filepath = locale_dir / filename
        if not filepath.exists():
            log_warn(f"File not found: {filepath}")
            continue

        content = filepath.read_text(encoding="utf-8")
        original = content
        replaced = 0

        for entry in file_entries:
            if entry.english in trans_map:
                translated = trans_map[entry.english]
                # Replace: "English text" -> "Translated text"
                old = f'"{entry.english}"'
                new = f'"{translated}"'
                if old in content:
                    content = content.replace(old, new, 1)  # Replace first occurrence
                    replaced += 1
                    if verbose:
                        print(f"  {entry.key}: {entry.english} → {translated}")

        if content != original:
            filepath.write_text(content, encoding="utf-8")
            log_info(f"Updated {filename}: {replaced} translations")
            total_replaced += replaced

    return total_replaced


def validate_json_files(locale_dir: Path) -> bool:
    """Validate all JSON files."""
    valid = True
    for f in locale_dir.glob("*.json"):
        try:
            json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            log_error(f"Invalid JSON in {f.name}: {e}")
            valid = False
    return valid


def main() -> int:
    parser = argparse.ArgumentParser(description="Translate locale using Claude CLI")
    parser.add_argument("locale", help="Locale code (e.g., pt_PT, ru)")
    parser.add_argument("--dry-run", action="store_true", help="Preview without changes")
    parser.add_argument("--no-commit", action="store_true", help="Skip git commit")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    args = parser.parse_args()

    # Setup paths
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parents[3]
    locales_dir = project_root / "src" / "locales"
    locale_dir = locales_dir / args.locale
    harmonize_script = script_dir.parent / "harmonize" / "harmonize-locale-file.py"

    if not locale_dir.is_dir():
        log_error(f"Locale not found: {locale_dir}")
        available = get_available_locales(locales_dir)
        if available:
            print(f"Available: {', '.join(available)}")
        return 1

    # Load export guide
    export_guide = None
    guide_path = locale_dir / "export-guide.md"
    if guide_path.is_file():
        export_guide = guide_path.read_text(encoding="utf-8")

    log_info(f"Starting translation for: {args.locale}")

    # Step 1: Harmonize
    log_info("Step 1: Harmonizing...")
    if not args.dry_run:
        try:
            run_command(["python3", str(harmonize_script), "-c", args.locale], cwd=project_root)
        except subprocess.CalledProcessError as e:
            log_error(f"Harmonize failed: {e}")
            return 1
    else:
        log_info("[DRY-RUN] Would harmonize")

    # Step 2: Extract from diff
    result = run_command(["git", "diff", f"src/locales/{args.locale}/"], cwd=project_root, check=False)
    if not result.stdout.strip():
        log_info("No changes - already up to date")
        return 0

    entries = extract_entries_from_diff(result.stdout)
    if not entries:
        log_info("No English strings found to translate")
        return 0

    log_info(f"Found {len(entries)} strings to translate")
    if args.verbose:
        for e in entries:
            print(f"  [{e.file}] {e.key}: {e.english}")

    # Step 3: Build prompt
    prompt = build_prompt(args.locale, entries, export_guide)

    if args.dry_run:
        log_info("[DRY-RUN] Prompt preview:")
        print("---")
        print(prompt[:3000])
        print("---")
        return 0

    # Step 4: Call Claude
    log_info("Step 2: Calling Claude...")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        f.write(prompt)
        prompt_file = Path(f.name)

    try:
        with open(prompt_file) as pf:
            result = subprocess.run(
                ["claude", "--print", "--dangerously-skip-permissions"],
                stdin=pf,
                capture_output=True,
                text=True,
                cwd=project_root,
            )
        if result.returncode != 0:
            log_error(f"Claude failed: {result.stderr}")
            return 1

        claude_output = result.stdout
        log_info(f"Got response ({len(claude_output)} chars)")

        if args.verbose:
            print("--- Claude output ---")
            print(claude_output[:1000])
            print("---")

    except FileNotFoundError:
        log_error("Claude CLI not found")
        return 1
    finally:
        prompt_file.unlink(missing_ok=True)

    # Step 5: Parse response
    translations = parse_response(claude_output)
    if not translations:
        log_error("Failed to parse translations")
        return 1

    log_info(f"Parsed {len(translations)} translations")

    # Step 6: Apply
    log_info("Step 3: Applying translations...")
    replaced = apply_translations(locale_dir, entries, translations, args.verbose)

    if replaced == 0:
        log_warn("No translations applied")
        return 1

    # Step 7: Validate
    log_info("Step 4: Validating JSON...")
    if not validate_json_files(locale_dir):
        log_error("JSON validation failed")
        return 1
    log_info("JSON valid")

    # Step 8: Commit
    if not args.no_commit:
        log_info("Step 5: Committing...")
        run_command(["git", "add", f"src/locales/{args.locale}/"], cwd=project_root)
        msg = f"i18n({args.locale}): Translate harmonized locale files"
        result = run_command(["git", "commit", "-m", msg], cwd=project_root, check=False)
        if result.returncode == 0:
            log_info("Committed")
        else:
            log_warn("Nothing to commit")
    else:
        log_info("[NO-COMMIT] Skipped commit")

    log_info(f"Done! Review: git diff HEAD~1 src/locales/{args.locale}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
