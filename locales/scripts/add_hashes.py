#!/usr/bin/env python3
"""
Add SHA256 hashes to source language keys and propagate to all locales.

Hashes are computed from normalized source text (lowercase, stripped whitespace)
to ensure stability across minor formatting changes.

Usage:
    python add_hashes.py              # Add hashes to en, copy to all locales
    python add_hashes.py --dry-run    # Show what would be done
"""

import argparse
import hashlib
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
CONTENT_DIR = SCRIPT_DIR.parent / "content"
SOURCE_LOCALE = "en"


def normalize_source_message(text: str) -> str:
    """Normalize source text for consistent hashing.

    Strips leading/trailing whitespace and converts to lowercase.
    This ensures hash stability across minor formatting changes.
    """
    return text.strip()  # don't modify case


def compute_hash(text: str) -> str:
    """Compute SHA256 hash of normalized text, truncated to 8 chars."""
    normalized = normalize_source_message(text).encode("utf-8")
    return hashlib.sha256(normalized).hexdigest()[:8]


def add_hashes_to_source(dry_run: bool = False) -> dict[str, dict[str, str]]:
    """Add sha256 hashes to all English source files.

    Returns:
        Dict mapping filename -> {key_path: hash}
    """
    source_dir = CONTENT_DIR / SOURCE_LOCALE
    all_hashes: dict[str, dict[str, str]] = {}

    for json_file in sorted(source_dir.glob("*.json")):
        with open(json_file, encoding="utf-8") as f:
            data = json.load(f)

        file_hashes: dict[str, str] = {}
        modified = False

        for key_path, entry in data.items():
            if not isinstance(entry, dict):
                continue

            text = entry.get("text", "")
            if not text:
                continue

            new_hash = compute_hash(text)
            file_hashes[key_path] = new_hash

            if entry.get("sha256") != new_hash:
                entry["sha256"] = new_hash
                modified = True

        all_hashes[json_file.name] = file_hashes

        if modified and not dry_run:
            with open(json_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
                f.write("\n")
            print(f"{json_file.name}: updated {len(file_hashes)} hashes")
        elif modified:
            print(f"{json_file.name}: would update {len(file_hashes)} hashes")
        else:
            print(f"{json_file.name}: {len(file_hashes)} hashes (no changes)")

    return all_hashes


def propagate_hashes_to_locales(
    source_hashes: dict[str, dict[str, str]], dry_run: bool = False
) -> None:
    """Copy source hashes to all locale files."""
    locale_dirs = [
        d
        for d in CONTENT_DIR.iterdir()
        if d.is_dir() and d.name != SOURCE_LOCALE and not d.name.startswith(".")
    ]

    for locale_dir in sorted(locale_dirs):
        locale = locale_dir.name
        updates = 0

        for filename, hashes in source_hashes.items():
            locale_file = locale_dir / filename
            if not locale_file.exists():
                continue

            with open(locale_file, encoding="utf-8") as f:
                data = json.load(f)

            modified = False
            for key_path, source_hash in hashes.items():
                if key_path not in data:
                    continue

                entry = data[key_path]
                if not isinstance(entry, dict):
                    continue

                if entry.get("sha256") != source_hash:
                    entry["sha256"] = source_hash
                    modified = True
                    updates += 1

            if modified and not dry_run:
                with open(locale_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)
                    f.write("\n")

        if updates > 0:
            action = "would update" if dry_run else "updated"
            print(f"{locale}: {action} {updates} hashes")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Add SHA256 hashes to source keys and propagate to locales."
    )
    parser.add_argument(
        "--dry-run", "-n", action="store_true", help="Show what would be done"
    )
    args = parser.parse_args()

    print(f"Source locale: {SOURCE_LOCALE}")
    print(f"Content dir: {CONTENT_DIR}\n")

    print("=== Adding hashes to source ===")
    source_hashes = add_hashes_to_source(dry_run=args.dry_run)

    print("\n=== Propagating to locales ===")
    propagate_hashes_to_locales(source_hashes, dry_run=args.dry_run)

    print("\nDone.")


if __name__ == "__main__":
    main()
