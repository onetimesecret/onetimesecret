#!/usr/bin/env python3
"""
Add content hashes to source language keys.

Hashes are computed from normalized source text and stored in each locale
file under context-specific field names:

  - Source locale (e.g. en): "content_hash" — hash of this entry's own text
  - Translation locales: "source_hash" — snapshot of the source content_hash
    at translation time, used as a staleness watermark

When the source text changes, its content_hash updates. Translators can
compare their locale's stored source_hash against the current source
content_hash to detect which strings need re-translation.

The source locale defaults to 'en' but can be overridden via the
I18N_DEFAULT_LOCALE environment variable.

Usage:
    python add_hashes.py              # Add/update hashes in source, init missing in locales
    python add_hashes.py --dry-run    # Show what would be done
    I18N_DEFAULT_LOCALE=de python add_hashes.py  # Use German as source
"""

import argparse
import hashlib
import json
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
CONTENT_DIR = SCRIPT_DIR.parent / "content"
SOURCE_LOCALE = os.environ.get("I18N_DEFAULT_LOCALE", "en")


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
    """Add content_hash to all source locale files.

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

            if entry.get("content_hash") != new_hash:
                entry["content_hash"] = new_hash
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


def init_missing_hashes_in_locales(
    source_hashes: dict[str, dict[str, str]], dry_run: bool = False
) -> None:
    """Initialize missing source_hash in translation locale files.

    Only adds hashes to entries that don't have one yet. Existing hashes
    are preserved so translators can compare against current source
    content_hash to detect which strings need re-translation.
    """
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

                # Only set hash if missing — preserve existing hashes
                # so translators can detect when source text changed
                if "source_hash" not in entry:
                    entry["source_hash"] = source_hash
                    modified = True
                    updates += 1

            if modified and not dry_run:
                with open(locale_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)
                    f.write("\n")

        if updates > 0:
            action = "would add" if dry_run else "added"
            print(f"{locale}: {action} {updates} missing hashes")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Add content hashes to source keys and propagate to locales."
    )
    parser.add_argument(
        "--dry-run", "-n", action="store_true", help="Show what would be done"
    )
    args = parser.parse_args()

    print(f"Source locale: {SOURCE_LOCALE}")
    print(f"Content dir: {CONTENT_DIR}\n")

    print("=== Adding content_hash to source ===")
    source_hashes = add_hashes_to_source(dry_run=args.dry_run)

    print("\n=== Initializing missing source_hash in locales ===")
    init_missing_hashes_in_locales(source_hashes, dry_run=args.dry_run)

    print("\nDone.")


if __name__ == "__main__":
    main()
