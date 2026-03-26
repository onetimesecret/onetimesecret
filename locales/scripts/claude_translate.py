#!/usr/bin/env python3
"""
Translate a single locale using Claude CLI.

Uses subprocess with stream-json for real-time streaming output,
or Claude Agent SDK for batch mode with typed message handling.

Usage:
    ./claude-translate-locale.py LOCALE [OPTIONS]

Examples:
    ./claude-translate-locale.py pt_PT
    ./claude-translate-locale.py ru --dry-run
    ./claude-translate-locale.py de_AT --stream --commit

Batch Processing:
    Process all locales with changed email.json files:

    git diff --name-only | grep 'email.json' | sed 's|src/locales/\\(.*\\)/email.json|\\1|' | while read locale; do
      ./claude-translate-locale.py "$locale" --verbose --stream
    done
"""

import argparse
import asyncio
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# SDK imports - optional, used for batch mode
try:
    from claude_agent_sdk import (
        AssistantMessage,
        ClaudeAgentOptions,
        ClaudeSDKError,
        ResultMessage,
        TextBlock,
        query,
    )

    HAS_SDK = True
except ImportError:
    HAS_SDK = False


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
    line: int
    key: str
    english: str
    translated: str = ""


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, check=check
    )


def get_available_locales(locales_dir: Path) -> list[str]:
    if not locales_dir.is_dir():
        return []
    return sorted(
        d.name
        for d in locales_dir.iterdir()
        if d.is_dir() and not d.name.startswith(".") and d.name != "en"
    )


def extract_entries_from_diff(diff_output: str) -> list[TranslationEntry]:
    """Extract translation entries from git diff with line numbers.

    Parses diff hunks to track exact line numbers in the new file.
    """
    entries: list[TranslationEntry] = []
    current_file = None
    current_line = 0

    # Pattern for hunk header: @@ -old_start,old_count +new_start,new_count @@
    hunk_pattern = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
    # Pattern for JSON key-value: "key": "value" (handles escaped quotes in values)
    kv_pattern = re.compile(r'^\+\s*"([^"]+)"\s*:\s*"((?:[^"\\]|\\.)*)"')

    for line in diff_output.splitlines():
        # Track current file
        if line.startswith("diff --git"):
            match = re.search(r"b/src/locales/[^/]+/([^/]+\.json)", line)
            if match:
                current_file = match.group(1)
                current_line = 0

        # Track line numbers from hunk headers
        elif line.startswith("@@"):
            match = hunk_pattern.match(line)
            if match:
                current_line = int(match.group(1))

        # Context line (in both old and new)
        elif line.startswith(" "):
            current_line += 1

        # Removed line (only in old file, doesn't affect new line count)
        elif line.startswith("-") and not line.startswith("---"):
            pass  # Don't increment

        # Added line (only in new file)
        elif line.startswith("+") and not line.startswith("+++"):
            match = kv_pattern.match(line)
            if match and current_file:
                key = match.group(1)
                value = match.group(2)

                if value and is_english(value):
                    entries.append(
                        TranslationEntry(
                            file=current_file,
                            line=current_line,
                            key=key,
                            english=value,
                        )
                    )
            current_line += 1

    return entries


def is_english(value: str) -> bool:
    """Check if string appears to be English (needs translation)."""
    if not value.strip():
        return False
    if value.startswith(("http://", "https://", "mailto:")):
        return False
    if re.match(r"^[\{\}0-9a-z_@:\.]+$", value):
        return False
    ascii_ratio = sum(1 for c in value if ord(c) < 128) / len(value)
    return ascii_ratio > 0.8


def build_prompt(
    locale: str,
    entries: list[TranslationEntry],
    guide_path: Optional[Path],
) -> str:
    """Build prompt with JSON array of entries and @ file reference for guide."""
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

    if guide_path and guide_path.is_file():
        prompt += f"\n## Translation Guide\nRead and follow the full translation guide: @{guide_path}\n"

    prompt += f"\n## Strings to Translate\n{json.dumps(items, indent=2, ensure_ascii=False)}"

    return prompt


def extract_translations_from_text(result_text: str) -> list[dict]:
    """Extract translation array from result text."""
    text = result_text.strip()

    # Strip markdown code fences if present
    if "```" in text:
        match = re.search(r"```(?:json)?\s*(\[.*?\])\s*```", text, re.DOTALL)
        if match:
            text = match.group(1)

    # Find the JSON array
    start = text.find("[")
    end = text.rfind("]") + 1
    if start >= 0 and end > start:
        text = text[start:end]

    return json.loads(text)


def run_claude_streaming(
    prompt: str,
    project_root: Path,
    verbose: bool = False,
) -> tuple[str, bool]:
    """Run Claude with stream-json for real-time token streaming.

    Returns (result_text, success).
    """
    cmd = [
        "claude",
        "--print",
        "--verbose",
        "--dangerously-skip-permissions",
        "--output-format",
        "stream-json",
    ]

    result_text = ""
    content_parts: list[str] = []
    success = False

    # Write prompt to temp file for stdin
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False
    ) as f:
        f.write(prompt)
        prompt_file = Path(f.name)

    try:
        with open(prompt_file) as pf:
            proc = subprocess.Popen(
                cmd,
                stdin=pf,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd=project_root,
            )

            # Process streaming output line by line
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue

                try:
                    event = json.loads(line)
                    event_type = event.get("type", "")

                    if event_type == "assistant":
                        # Assistant message with content
                        message = event.get("message", {})
                        content_list = message.get("content", [])
                        for block in content_list:
                            if block.get("type") == "text":
                                text = block.get("text", "")
                                content_parts.append(text)
                                print(".", end="", flush=True)

                    elif event_type == "content_block_delta":
                        # Streaming content delta
                        delta = event.get("delta", {})
                        if delta.get("type") == "text_delta":
                            text = delta.get("text", "")
                            content_parts.append(text)
                            print(".", end="", flush=True)

                    elif event_type == "result":
                        # Final result
                        print()  # Newline after dots

                        if verbose:
                            subtype = event.get("subtype", "")
                            cost = event.get("cost_cad", 0)
                            duration = event.get("duration_ms", 0)
                            log_info(
                                f"Result: {subtype}, cost: ${cost:.4f}, duration: {duration}ms"
                            )

                        if event.get("is_error"):
                            log_error(
                                f"Claude error: {event.get('result', 'Unknown')}"
                            )
                            success = False
                        else:
                            result_text = event.get("result", "")
                            success = True

                except json.JSONDecodeError:
                    # Skip malformed lines
                    if verbose:
                        log_warn(f"Skipped malformed line: {line[:50]}")

            proc.wait()

            # If we didn't get a result event, try to use accumulated content
            if not result_text and content_parts:
                result_text = "".join(content_parts)
                success = True

            if proc.returncode != 0 and not success:
                stderr = proc.stderr.read() if proc.stderr else ""
                log_error(f"Claude failed (exit {proc.returncode}): {stderr}")
                return "", False

    except FileNotFoundError:
        log_error("Claude CLI not found")
        return "", False

    finally:
        prompt_file.unlink(missing_ok=True)

    return result_text, success


def run_claude_batch(
    prompt: str,
    project_root: Path,
    verbose: bool = False,
) -> tuple[str, bool]:
    """Run Claude with JSON output format (batch mode, no streaming).

    Returns (result_text, success).
    """
    cmd = [
        "claude",
        "--print",
        "--dangerously-skip-permissions",
        "--output-format",
        "json",
    ]

    # Write prompt to temp file for stdin
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False
    ) as f:
        f.write(prompt)
        prompt_file = Path(f.name)

    try:
        with open(prompt_file) as pf:
            result = subprocess.run(
                cmd,
                stdin=pf,
                capture_output=True,
                text=True,
                cwd=project_root,
            )

        if result.returncode != 0:
            log_error(f"Claude failed: {result.stderr}")
            return "", False

        claude_output = result.stdout

        if verbose:
            print("--- Claude output ---")
            print(claude_output[:1000])
            print("---")

        # Parse the JSON envelope
        try:
            envelope = json.loads(claude_output)

            if verbose:
                log_info(
                    f"Response type: {envelope.get('type')}, "
                    f"subtype: {envelope.get('subtype')}"
                )
                if envelope.get("cost_cad"):
                    log_info(f"Cost: ${envelope.get('cost_cad', 0):.4f}")

            if envelope.get("is_error"):
                log_error(
                    f"Claude returned error: {envelope.get('result', 'Unknown error')}"
                )
                return "", False

            result_text = envelope.get("result", "")
            if not result_text:
                log_error("No result in Claude response")
                return "", False

            return result_text, True

        except json.JSONDecodeError as e:
            log_error(f"Failed to parse JSON envelope: {e}")
            log_warn(f"Raw output:\n{claude_output[:500]}")
            return "", False

    except FileNotFoundError:
        log_error("Claude CLI not found")
        return "", False

    finally:
        prompt_file.unlink(missing_ok=True)


async def run_claude_sdk(
    prompt: str,
    project_root: Path,
    verbose: bool = False,
) -> tuple[str, bool]:
    """Run Claude using the claude-agent-sdk (batch mode with typed messages).

    Args:
        prompt: The translation prompt
        project_root: Working directory for Claude
        verbose: Whether to show progress output

    Returns:
        (result_text, success) tuple

    Note:
        Caller must check HAS_SDK before calling this function.
    """
    options = ClaudeAgentOptions(
        cwd=str(project_root),
        allowed_tools=["Read"],  # Only need file read for guide
        max_turns=1,  # Single-turn translation task
    )

    result_text = ""
    content_parts: list[str] = []

    try:
        async for message in query(prompt=prompt, options=options):
            if isinstance(message, AssistantMessage):
                # Extract text from assistant message content blocks
                for block in message.content:
                    if isinstance(block, TextBlock):
                        content_parts.append(block.text)

            elif isinstance(message, ResultMessage):
                if verbose:
                    cost = getattr(message, "cost_cad", 0) or 0
                    duration = getattr(message, "duration_ms", 0) or 0
                    log_info(f"Cost: ${cost:.4f}, duration: {duration}ms")

                if getattr(message, "is_error", False):
                    error_msg = getattr(message, "result", "Unknown error")
                    log_error(f"Claude error: {error_msg}")
                    return "", False

                # Get result from message
                result_text = getattr(message, "result", "") or ""

        # If no result from ResultMessage, use accumulated content
        if not result_text and content_parts:
            result_text = "".join(content_parts)

        if not result_text:
            log_error("No response received from Claude")
            return "", False

        return result_text, True

    except ClaudeSDKError as e:
        log_error(f"Claude SDK error: {e}")
        return "", False

    except Exception as e:
        log_error(f"Unexpected error: {e}")
        return "", False


def apply_translations_with_sed(
    locale_dir: Path,
    entries: list[TranslationEntry],
    translations: list[dict],
    verbose: bool = False,
) -> int:
    """Apply translations using sed for precise line-based replacement."""
    # Build lookup: english -> translated
    trans_map = {
        t["english"]: t.get("translated", "")
        for t in translations
        if t.get("translated")
    }

    if verbose:
        log_info(f"Translation map has {len(trans_map)} entries")

    total_replaced = 0

    for entry in entries:
        if entry.english not in trans_map:
            if verbose:
                log_warn(f"No translation for: {entry.english}")
            continue

        translated = trans_map[entry.english]
        filepath = locale_dir / entry.file

        if not filepath.exists():
            log_warn(f"File not found: {filepath}")
            continue

        # Escape special characters for sed
        # For the search pattern, escape regex metacharacters and sed delimiters
        old_escaped = re.escape(entry.english).replace("/", r"\/")
        # For replacement, escape backslashes first, then & and /
        new_escaped = (
            translated.replace("\\", r"\\")
            .replace("&", r"\&")
            .replace("/", r"\/")
        )

        # Use sed to replace on specific line: sed -i '' 'LINEs/old/new/' file (macOS)
        sed_cmd = [
            "sed",
            "-i",
            "",
            f'{entry.line}s/"{old_escaped}"/"{new_escaped}"/',
            str(filepath),
        ]

        try:
            result = subprocess.run(sed_cmd, capture_output=True, text=True)
            if result.returncode == 0:
                total_replaced += 1
                if verbose:
                    print(
                        f"  L{entry.line} [{entry.file}] {entry.key}: {entry.english} -> {translated}"
                    )
            else:
                log_warn(f"sed failed for {entry.key}: {result.stderr}")
        except Exception as e:
            log_warn(f"sed error for {entry.key}: {e}")

    # Group by file for summary
    files_updated = set(e.file for e in entries if e.english in trans_map)
    for f in files_updated:
        count = sum(
            1 for e in entries if e.file == f and e.english in trans_map
        )
        log_info(f"Updated {f}: {count} translations")

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


async def async_main(args: argparse.Namespace) -> int:
    """Async main entry point."""
    # Setup paths
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parents[3]
    locales_dir = project_root / "src" / "locales"
    locale_dir = locales_dir / args.locale
    harmonize_script = (
        script_dir.parent / "harmonize" / "harmonize-locale-file.py"
    )

    if not locale_dir.is_dir():
        log_error(f"Locale not found: {locale_dir}")
        available = get_available_locales(locales_dir)
        if available:
            print(f"Available: {', '.join(available)}")
        return 1

    # Path to export guide (will be passed as @ reference to Claude)
    guide_path = locale_dir / "export-guide.md"

    log_info(f"Starting translation for: {args.locale}")

    # Step 1: Harmonize (optional)
    if args.harmonize:
        log_info("Step 1: Harmonizing...")
        harmonize_cmd = ["python3", str(harmonize_script), "-c", args.locale]
        if not args.dry_run:
            try:
                run_command(harmonize_cmd, cwd=project_root)
            except subprocess.CalledProcessError as e:
                log_error(f"Harmonize failed: {e}")
                return 1
        else:
            log_info(f"[DRY-RUN] Would run: {' '.join(harmonize_cmd)}")
            return 0
    else:
        log_info("Step 1: Skipping harmonize (use --harmonize to enable)")

    # Step 2: Extract from diff with line numbers
    result = run_command(
        ["git", "diff", f"src/locales/{args.locale}/"],
        cwd=project_root,
        check=False,
    )
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
            print(f"  L{e.line} [{e.file}] {e.key}: {e.english}")

    # Step 3: Build prompt
    prompt = build_prompt(args.locale, entries, guide_path)

    if args.dry_run:
        log_info("[DRY-RUN] Prompt preview:")
        print("---")
        print(prompt)
        print("---")
        return 0

    # Step 4: Call Claude
    if args.stream:
        log_info("Step 2: Calling Claude (streaming)...")
        result_text, success = run_claude_streaming(
            prompt=prompt,
            project_root=project_root,
            verbose=args.verbose,
        )
    elif HAS_SDK:
        log_info("Step 2: Calling Claude (SDK batch)...")
        result_text, success = await run_claude_sdk(
            prompt=prompt,
            project_root=project_root,
            verbose=args.verbose,
        )
    else:
        log_info("Step 2: Calling Claude (subprocess batch)...")
        result_text, success = run_claude_batch(
            prompt=prompt,
            project_root=project_root,
            verbose=args.verbose,
        )

    if not success:
        return 1

    log_info(f"Got response ({len(result_text)} chars)")

    # Parse translations from result text
    try:
        translations = extract_translations_from_text(result_text)
    except json.JSONDecodeError as e:
        log_error(f"Failed to parse translations: {e}")
        log_warn(f"Raw result:\n{result_text[:500]}")
        return 1

    # Validate we got translations
    if not translations:
        log_error("Failed to parse translations")
        return 1

    log_info(f"Parsed {len(translations)} translations")

    # Step 5: Apply with sed
    log_info("Step 3: Applying translations with sed...")
    replaced = apply_translations_with_sed(
        locale_dir, entries, translations, args.verbose
    )

    if replaced == 0:
        log_warn("No translations applied")
        return 1

    # Step 6: Validate
    log_info("Step 4: Validating JSON...")
    if not validate_json_files(locale_dir):
        log_error("JSON validation failed")
        return 1
    log_info("JSON valid")

    # Step 7: Commit (optional)
    if args.commit:
        log_info("Step 5: Committing...")
        run_command(
            ["git", "add", f"src/locales/{args.locale}/"], cwd=project_root
        )
        msg = f"i18n({args.locale}): Translate harmonized locale files"
        commit_result = run_command(
            ["git", "commit", "-m", msg], cwd=project_root, check=False
        )
        if commit_result.returncode == 0:
            log_info("Committed")
        else:
            log_warn("Nothing to commit")
        log_info(f"Done! Review: git diff HEAD~1 src/locales/{args.locale}/")
    else:
        log_info(
            "Done! Review changes with: git diff src/locales/{}/".format(
                args.locale
            )
        )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Translate locale using Claude CLI"
    )
    parser.add_argument("locale", help="Locale code (e.g., pt_PT, ru)")
    parser.add_argument(
        "--dry-run", action="store_true", help="Preview without changes"
    )
    parser.add_argument(
        "--commit",
        action="store_true",
        help="Git add and commit locale changes",
    )
    parser.add_argument(
        "--harmonize",
        action="store_true",
        help="Run harmonize script first (default: use existing git diff)",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Verbose output"
    )
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Stream real-time progress (subprocess with stream-json)",
    )
    args = parser.parse_args()

    return asyncio.run(async_main(args))


if __name__ == "__main__":
    sys.exit(main())
