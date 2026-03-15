#!/usr/bin/env python3
"""Extract untranslated strings from a harmonized locale by comparing to English source.

Usage: python3 _extract_english.py LOCALE
Output: JSON array of {file, key, english} entries where text == English source
"""
import json, sys
from pathlib import Path

def main():
    locale = sys.argv[1]
    project = Path(__file__).resolve().parents[2]
    content = project / "locales" / "content"
    en_dir = content / "en"
    locale_dir = content / locale

    if not locale_dir.is_dir():
        print("[]")
        return

    entries = []
    for en_file in sorted(en_dir.glob("*.json")):
        locale_file = locale_dir / en_file.name
        if not locale_file.is_file():
            continue

        with open(en_file, encoding="utf-8") as f:
            en_data = json.load(f)
        with open(locale_file, encoding="utf-8") as f:
            locale_data = json.load(f)

        for key, en_val in en_data.items():
            if not isinstance(en_val, dict) or "text" not in en_val:
                continue
            en_text = en_val["text"]
            if not en_text.strip():
                continue

            locale_val = locale_data.get(key)
            if not isinstance(locale_val, dict):
                continue
            locale_text = locale_val.get("text", "")

            # If locale text matches English exactly, it needs translation
            if locale_text == en_text:
                entries.append({
                    "file": en_file.name,
                    "key": key,
                    "english": en_text
                })

    print(json.dumps(entries, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
