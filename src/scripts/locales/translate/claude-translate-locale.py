#!/usr/bin/env python3
"""
Translate a single locale using Claude CLI.

This script:
1. Harmonizes a locale (copies English placeholders for missing keys)
2. Extracts git diff of changed strings only
3. Loads locale's export-guide.md for translation context
4. Sends diff to Claude CLI for translation (isolated session)
5. Parses Claude's JSON output and applies to locale files
6. Validates JSON syntax
7. Commits changes with [#I18N] prefix

Usage:
    ./claude-translate-locale.py LOCALE [OPTIONS]

Examples:
    ./claude-translate-locale.py pt_PT
    ./claude-translate-locale.py ru --dry-run
    ./claude-translate-locale.py de_AT --no-commit
    ./claude-translate-locale.py es --verbose

Prerequisites:
    - Claude CLI installed and authenticated (`claude --version`)
    - Python 3 for harmonize script and JSON processing

Notes:
    - Each invocation is a fresh Claude session (no cross-locale contamination)
    - Only translates strings in the diff, not the entire file
    - Preserves all variables: {time}, {count}, {0}, {{var}}, etc.
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Optional


# ANSI color codes
class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    NC = "\033[0m"  # No Color


def log_info(msg: str) -> None:
    """Print info message in green."""
    print(f"{Colors.GREEN}[INFO]{Colors.NC} {msg}")


def log_warn(msg: str) -> None:
    """Print warning message in yellow."""
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")


def log_error(msg: str) -> None:
    """Print error message in red."""
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}", file=sys.stderr)


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    capture: bool = True,
    check: bool = True,
) -> subprocess.CompletedProcess:
    """Run a shell command and return the result."""
    return subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=capture,
        text=True,
        check=check,
    )


def get_available_locales(locales_dir: Path) -> list[str]:
    """Get list of available locale directories."""
    if not locales_dir.is_dir():
        return []
    return sorted(
        d.name
        for d in locales_dir.iterdir()
        if d.is_dir() and not d.name.startswith(".") and d.name != "en"
    )


def set_nested(obj: dict, key_path: str, value: Any) -> None:
    """Set a nested value in a dict using dot notation.

    Example: set_nested(d, "web.secrets.key", "value")
    """
    keys = key_path.split(".")
    for key in keys[:-1]:
        obj = obj.setdefault(key, {})
    obj[keys[-1]] = value


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


def build_prompt(
    locale: str,
    diff_output: str,
    locales_readme: Optional[str],
    export_guide: Optional[str],
) -> str:
    """Build the prompt to send to Claude."""
    prompt_parts = []

    # Header with instructions
    prompt_parts.append("""You are translating locale files for OneTime Secret, a secure message sharing service.

## Your Task
Translate the English placeholder strings shown in the git diff below into the target language.
Only translate strings that were added (lines starting with +).
Preserve all variables exactly: {time}, {count}, {limit}, {0}, {1}, {{var}}, etc.

## Critical Rules
1. PRESERVE ALL VARIABLES EXACTLY - {time} must stay {time}, not {Zeit} or {tiempo}
2. Keep HTML tags intact: <a>, <strong>, <br>, etc.
3. Maintain the same JSON structure
4. Use terminology from the export-guide.md if provided
5. For "secret" - use the culturally appropriate term (not always literal translation)
6. Distinguish: password (account login) vs passphrase (protects individual secrets)
7. DO NOT translate keys starting with underscore (_README, _context, etc.) - keep in English
8. Security messages must remain generic per OWASP guidelines

## Output Format
For each file, output the corrected JSON content for ONLY the keys that need translation.
Use this format:

### FILE: path/to/file.json
```json
{
  "key.path.here": "Translated value",
  "another.key": "Another translation"
}
```
""")

    # Add locales README for general guidelines
    if locales_readme:
        prompt_parts.append("\n## Translation Guidelines (from README.md)")
        prompt_parts.append("```markdown")
        prompt_parts.append(locales_readme)
        prompt_parts.append("```")

    # Add export guide if available
    if export_guide:
        prompt_parts.append(f"\n## Export Guide for {locale}")
        prompt_parts.append("```markdown")
        prompt_parts.append(export_guide)
        prompt_parts.append("```")

    # Add the diff
    prompt_parts.append(f"""
## Git Diff to Translate
Target locale: {locale}

```diff
{diff_output}
```

Now translate the added English strings (+ lines) into {locale}. Output ONLY the translations needed.""")

    return "\n".join(prompt_parts)


def parse_claude_output(output: str, locale: str, locales_dir: Path, verbose: bool = False) -> int:
    """Parse Claude's output and apply translations to locale files.

    Returns the number of translations applied.
    """
    # Pattern to match FILE markers and JSON blocks
    pattern = r"### FILE:\s*(.+?\.json)\s*\n```json\s*\n(.*?)\n```"
    matches = re.findall(pattern, output, re.DOTALL)

    if not matches:
        log_error("No translation blocks found in Claude output")
        if verbose:
            log_warn("Raw output preview:")
            print(output[:1000])
        return 0

    total_updated = 0

    for filepath, json_block in matches:
        # Normalize filepath - remove src/locales/ prefix if present
        if filepath.startswith("src/locales/"):
            filepath = filepath.replace("src/locales/", "")

        # Extract just the filename
        filename = Path(filepath).name
        target_file = locales_dir / locale / filename

        if not target_file.exists():
            log_warn(f"Target file not found: {target_file}")
            continue

        try:
            translations = json.loads(json_block)
        except json.JSONDecodeError as e:
            log_warn(f"Invalid JSON for {filepath}: {e}")
            continue

        # Load existing file
        with open(target_file, "r", encoding="utf-8") as f:
            existing = json.load(f)

        # Apply translations (handles nested keys like "web.secrets.key")
        updated = 0
        for key, value in translations.items():
            try:
                set_nested(existing, key, value)
                updated += 1
            except Exception as e:
                log_warn(f"Could not set {key}: {e}")

        # Write back
        with open(target_file, "w", encoding="utf-8") as f:
            json.dump(existing, f, ensure_ascii=False, indent=2)
            f.write("\n")

        if verbose or updated > 0:
            log_info(f"Updated {target_file.name}: {updated} translations")

        total_updated += updated

    return total_updated


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Translate a single locale using Claude CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    %(prog)s pt_PT                    # Translate Portuguese (Portugal)
    %(prog)s ru --dry-run             # Preview without changes
    %(prog)s de_AT --no-commit        # Apply translations, skip commit
    %(prog)s es -v                    # Verbose output
        """,
    )
    parser.add_argument("locale", help="Locale code (e.g., pt_PT, ru, de_AT)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without modifying files or calling Claude",
    )
    parser.add_argument(
        "--no-commit",
        action="store_true",
        help="Apply translations but skip git commit",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose output",
    )
    parser.add_argument(
        "--base-locale",
        default="en",
        help="Base locale (default: en)",
    )

    args = parser.parse_args()

    # Determine directories
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parents[3]  # translate -> locales -> scripts -> src -> root
    locales_dir = project_root / "src" / "locales"
    harmonize_script = script_dir.parent / "harmonize" / "harmonize-locale-file.py"

    # Validate locale exists
    locale_dir = locales_dir / args.locale
    if not locale_dir.is_dir():
        log_error(f"Locale directory not found: {locale_dir}")
        available = get_available_locales(locales_dir)
        if available:
            print(f"Available locales: {', '.join(available)}")
        return 1

    # Check for export-guide.md
    export_guide_path = locale_dir / "export-guide.md"
    export_guide: Optional[str] = None
    if export_guide_path.is_file():
        export_guide = export_guide_path.read_text(encoding="utf-8")
    else:
        log_warn(f"No export-guide.md found for {args.locale} - translations may be less accurate")

    # Check for locales README
    locales_readme_path = locales_dir / "README.md"
    locales_readme: Optional[str] = None
    if locales_readme_path.is_file():
        locales_readme = locales_readme_path.read_text(encoding="utf-8")

    log_info(f"Starting translation for locale: {args.locale}")

    # Step 1: Harmonize locale (copy English for missing keys)
    log_info("Step 1: Harmonizing locale files...")
    if not args.dry_run:
        try:
            result = run_command(
                ["python3", str(harmonize_script), "-c", args.locale],
                cwd=project_root,
            )
            if args.verbose and result.stdout:
                print(result.stdout)
        except subprocess.CalledProcessError as e:
            log_error(f"Harmonize script failed: {e}")
            if e.stderr:
                print(e.stderr, file=sys.stderr)
            return 1
    else:
        log_info(f"[DRY-RUN] Would run: harmonize-locale-file.py -c {args.locale}")

    # Step 2: Check if there are changes to translate
    try:
        result = run_command(
            ["git", "diff", "--name-only", f"src/locales/{args.locale}/"],
            cwd=project_root,
            check=False,
        )
        changed_files = result.stdout.strip()
    except Exception as e:
        log_error(f"Git diff failed: {e}")
        return 1

    if not changed_files:
        log_info(f"No changes detected for {args.locale} - already up to date")
        return 0

    log_info("Changed files:")
    for f in changed_files.splitlines():
        print(f"  {f}")

    # Step 3: Generate the diff for Claude
    result = run_command(
        ["git", "diff", f"src/locales/{args.locale}/"],
        cwd=project_root,
    )
    diff_output = result.stdout
    diff_lines = len(diff_output.splitlines())
    log_info(f"Diff contains {diff_lines} lines of changes")

    # Step 4: Build the Claude prompt
    prompt = build_prompt(args.locale, diff_output, locales_readme, export_guide)

    if args.dry_run:
        log_info("[DRY-RUN] Would send to Claude:")
        print("---")
        # Show first 50 lines
        prompt_lines = prompt.splitlines()
        print("\n".join(prompt_lines[:50]))
        if len(prompt_lines) > 50:
            print(f"... (truncated, {diff_lines} lines of diff)")
        print("---")
        return 0

    # Step 5: Call Claude CLI
    log_info("Step 2: Sending to Claude for translation...")

    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        f.write(prompt)
        prompt_file = Path(f.name)

    try:
        # Call Claude CLI with the prompt
        result = subprocess.run(
            ["claude", "--print", "--dangerously-skip-permissions"],
            stdin=open(prompt_file, "r"),
            capture_output=True,
            text=True,
            cwd=project_root,
        )

        if result.returncode != 0:
            log_error("Claude CLI failed")
            if result.stderr:
                print(result.stderr, file=sys.stderr)
            if result.stdout:
                print(result.stdout)
            return 1

        claude_output = result.stdout
        log_info(f"Claude response received ({len(claude_output.splitlines())} lines)")

    except FileNotFoundError:
        log_error("Claude CLI not found. Please install it with: npm install -g @anthropic-ai/claude-cli")
        return 1
    except Exception as e:
        log_error(f"Claude CLI failed: {e}")
        return 1
    finally:
        prompt_file.unlink(missing_ok=True)

    # Step 6: Apply translations
    log_info("Step 3: Applying translations...")
    translations_applied = parse_claude_output(
        claude_output, args.locale, locales_dir, args.verbose
    )

    if translations_applied == 0:
        log_warn("No translations were applied")
        return 1

    log_info(f"Applied {translations_applied} translations")

    # Step 7: Validate JSON
    log_info("Step 4: Validating JSON...")
    validation_failed = False
    for json_file in locale_dir.glob("*.json"):
        is_valid, error_msg = validate_json_file(json_file)
        if not is_valid:
            log_error(f"Invalid JSON: {json_file}")
            if error_msg:
                print(f"  {error_msg}", file=sys.stderr)
            validation_failed = True

    if validation_failed:
        log_error("JSON validation failed - not committing")
        return 1

    log_info("All JSON files valid")

    # Step 8: Commit
    if not args.no_commit:
        log_info("Step 5: Committing changes...")
        try:
            # Stage changes
            run_command(
                ["git", "add", f"src/locales/{args.locale}/"],
                cwd=project_root,
            )

            # Commit with heredoc-style message
            commit_msg = f"""[#I18N] i18n({args.locale}): Translate harmonized locale files

Automated translation of new/missing keys using Claude.
"""
            result = run_command(
                ["git", "commit", "-m", commit_msg],
                cwd=project_root,
                check=False,
            )

            if result.returncode == 0:
                log_info(f"Committed changes for {args.locale}")
            else:
                log_warn("Nothing to commit (no changes)")

        except Exception as e:
            log_warn(f"Commit failed: {e}")
    else:
        log_info("[NO-COMMIT] Skipping commit step")

    log_info(f"Translation complete for {args.locale}")
    print()
    print(f"Review changes with: git diff HEAD~1 src/locales/{args.locale}/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
