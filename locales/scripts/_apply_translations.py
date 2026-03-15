#!/usr/bin/env python3
"""Apply translations to locale files.

Usage: echo '[{"file":"x.json","key":"y","translated":"z"}]' | python3 _apply_translations.py LOCALE
"""
import json, sys
from pathlib import Path

def main():
    locale = sys.argv[1]
    translations = json.load(sys.stdin)
    project = Path(__file__).resolve().parents[2]
    locale_dir = project / "locales" / "content" / locale

    if not locale_dir.is_dir():
        print(f"Error: {locale_dir} not found", file=sys.stderr)
        return 1

    # Group by file
    by_file = {}
    for t in translations:
        f = t.get("file", "")
        if f:
            by_file.setdefault(f, []).append(t)

    total = 0
    for filename, items in sorted(by_file.items()):
        filepath = locale_dir / filename
        if not filepath.is_file():
            print(f"  Skip {filename} (not found)")
            continue

        with open(filepath, encoding="utf-8") as f:
            data = json.load(f)

        changed = 0
        for item in items:
            key = item["key"]
            translated = item.get("translated", "")
            if not translated or translated == item.get("english", ""):
                continue
            if key in data and isinstance(data[key], dict) and "text" in data[key]:
                if data[key]["text"] != translated:
                    data[key]["text"] = translated
                    changed += 1

        if changed:
            with open(filepath, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
                f.write("\n")
            total += changed
            print(f"  {filename}: {changed} translations applied")

    print(f"Total: {total} translations applied for {locale}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
