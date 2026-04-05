#!/usr/bin/env python3
"""
Fix invalid sha256 hashes in locale files.

Replaces empty strings, "placeholder", and known fake sequential patterns
(a1b2c3d4, b2c3d4e5, etc.) with the correct hash from the English source.

Usage:
    python fix_hashes.py              # Fix all bad hashes
    python fix_hashes.py --dry-run    # Show what would be done
"""

import argparse
import hashlib
import json
import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
CONTENT_DIR = SCRIPT_DIR.parent / "content"
SOURCE_LOCALE = "en"

# Known fake hash patterns
FAKE_PATTERNS = {
    "",
    "placeholder",
    "a1b2c3d4",
    "b2c3d4e5",
    "c3d4e5f6",
    "d4e5f6a7",
    "e5f6a7b8",
    "f6a7b8c9",
    "a7b8c9d0",
    "cafecafe",
}


def compute_hash(text: str) -> str:
    """Compute SHA256 hash of text, truncated to 8 chars."""
    return hashlib.sha256(text.strip().encode("utf-8")).hexdigest()[:8]


def is_fake_hash(h: str) -> bool:
    """Check if a hash value is a known fake/placeholder."""
    if h in FAKE_PATTERNS:
        return True
    # Sequential hex pattern like a1b2c3d4
    if re.match(r"^[a-f][0-9][a-f][0-9][a-f][0-9][a-f][0-9]$", h):
        return True
    return False


def load_source_hashes() -> dict[str, dict[str, str]]:
    """Load all hashes from English source files."""
    source_dir = CONTENT_DIR / SOURCE_LOCALE
    all_hashes: dict[str, dict[str, str]] = {}

    for json_file in sorted(source_dir.glob("*.json")):
        with open(json_file, encoding="utf-8") as f:
            data = json.load(f)

        file_hashes: dict[str, str] = {}
        for key_path, entry in data.items():
            if not isinstance(entry, dict):
                continue
            text = entry.get("text", "")
            if not text:
                continue
            h = entry.get("sha256", "")
            if h and not is_fake_hash(h):
                file_hashes[key_path] = h
            else:
                # Compute from source text
                file_hashes[key_path] = compute_hash(text)

        all_hashes[json_file.name] = file_hashes

    return all_hashes


def fix_locale_hashes(
    source_hashes: dict[str, dict[str, str]], dry_run: bool = False
) -> int:
    """Fix bad hashes in all non-source locale files."""
    total_fixed = 0

    locale_dirs = sorted(
        d
        for d in CONTENT_DIR.iterdir()
        if d.is_dir() and d.name != SOURCE_LOCALE and not d.name.startswith(".")
    )

    for locale_dir in locale_dirs:
        locale = locale_dir.name
        locale_fixed = 0

        for filename, hashes in source_hashes.items():
            locale_file = locale_dir / filename
            if not locale_file.exists():
                continue

            with open(locale_file, encoding="utf-8") as f:
                data = json.load(f)

            modified = False
            for key_path, correct_hash in hashes.items():
                if key_path not in data:
                    continue

                entry = data[key_path]
                if not isinstance(entry, dict):
                    continue

                current = entry.get("sha256", "")
                if is_fake_hash(current):
                    entry["sha256"] = correct_hash
                    modified = True
                    locale_fixed += 1

            if modified and not dry_run:
                with open(locale_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)
                    f.write("\n")

        if locale_fixed > 0:
            action = "would fix" if dry_run else "fixed"
            print(f"  {locale}: {action} {locale_fixed} hashes")
            total_fixed += locale_fixed

    return total_fixed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fix invalid sha256 hashes in locale files."
    )
    parser.add_argument(
        "--dry-run", "-n", action="store_true", help="Show what would be done"
    )
    args = parser.parse_args()

    print("Loading source hashes...")
    source_hashes = load_source_hashes()
    total_keys = sum(len(h) for h in source_hashes.values())
    print(f"  {len(source_hashes)} files, {total_keys} keys\n")

    # Also fix source file fakes
    source_dir = CONTENT_DIR / SOURCE_LOCALE
    source_fixed = 0
    for json_file in sorted(source_dir.glob("*.json")):
        with open(json_file, encoding="utf-8") as f:
            data = json.load(f)
        modified = False
        for key_path, entry in data.items():
            if not isinstance(entry, dict):
                continue
            text = entry.get("text", "")
            if not text:
                continue
            current = entry.get("sha256", "")
            if is_fake_hash(current):
                entry["sha256"] = compute_hash(text)
                modified = True
                source_fixed += 1
        if modified and not args.dry_run:
            with open(json_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
                f.write("\n")
    if source_fixed:
        action = "would fix" if args.dry_run else "fixed"
        print(f"  en (source): {action} {source_fixed} hashes\n")

    print("Fixing locale hashes...")
    total = fix_locale_hashes(source_hashes, dry_run=args.dry_run)
    print(
        f"\nTotal: {total + source_fixed} hashes {'would be ' if args.dry_run else ''}fixed"
    )


if __name__ == "__main__":
    main()
