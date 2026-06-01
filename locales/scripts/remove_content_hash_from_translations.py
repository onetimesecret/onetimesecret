#!/usr/bin/env python3
"""Remove content_hash fields from non-source locale files.

content_hash belongs only in the source locale (en). Translation locales
use source_hash as their staleness watermark. This cleans up any
content_hash that leaked into translation files.
"""

import json
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
CONTENT_DIR = SCRIPT_DIR.parent / "content"
SOURCE_LOCALE = os.environ.get("I18N_DEFAULT_LOCALE", "en")

locale_dirs = sorted(
    d for d in CONTENT_DIR.iterdir()
    if d.is_dir() and d.name != SOURCE_LOCALE and not d.name.startswith(".")
)

for locale_dir in locale_dirs:
    for json_file in sorted(locale_dir.glob("*.json")):
        with open(json_file, encoding="utf-8") as f:
            data = json.load(f)

        removed = 0
        for key_path, entry in data.items():
            if isinstance(entry, dict) and "content_hash" in entry:
                del entry["content_hash"]
                removed += 1

        if removed:
            with open(json_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
                f.write("\n")
            print(f"{locale_dir.name}/{json_file.name}: removed {removed}")
