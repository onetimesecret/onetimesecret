"""``content`` command group.

Locale content-file operations, ported behavior-for-behavior from the legacy
standalone scripts:

  - ``compile``    <- ``locales/scripts/build/compile.py``
  - ``decompile``  <- ``locales/scripts/build/decompile.py``
  - ``hashes``     <- ``locales/scripts/add_hashes.py``
  - ``add-field``  <- ``locales/scripts/add_field.py``

Path constants and the source locale come from :mod:`i18n.config`; JSON file
handling and key traversal come from :mod:`i18n.io`. No module re-derives path
constants or re-implements those primitives.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from ..config import CONTENT_DIR, GENERATED_DIR, LOCALES_DIR, SOURCE_LOCALE
from ..io import (
    KeyPathConflictError,
    load_json_file,
    save_json_file,
    set_nested_value,
    walk_keys,
)

# compile.py / decompile.py standard mode read-write the app's nested locale
# files under ``<project_root>/src/locales``. config exposes LOCALES_DIR
# (== legacy LOCALES_DIR), and PROJECT_ROOT == LOCALES_DIR.parent, so this is
# the exact legacy ``PROJECT_ROOT / "src" / "locales"`` derivation.
SRC_LOCALES_DIR: Path = LOCALES_DIR.parent / "src" / "locales"


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------


def register(subparsers) -> None:
    g = subparsers.add_parser("content", help="Locale content file operations")
    gsub = g.add_subparsers(dest="cmd", required=True)

    _register_compile(gsub)
    _register_decompile(gsub)
    _register_hashes(gsub)
    _register_add_field(gsub)


def _register_compile(gsub) -> None:
    c = gsub.add_parser(
        "compile",
        help="Sync translations from content JSON to generated/locales.",
        description="Sync translations from content JSON to generated/locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python compile.py eo --dry-run
    python compile.py eo --file auth.json
    python compile.py eo
    python compile.py --all
    python compile.py --all --dry-run
    python compile.py eo --clobber       # Replace files instead of merging
    python compile.py --all --merged     # Output single merged file per locale
    python compile.py --all --merged --output-dir generated/locales
        """,
    )
    c.add_argument(
        "locale",
        nargs="?",
        help="Target locale code (e.g., 'eo', 'de')",
    )
    c.add_argument(
        "--all",
        action="store_true",
        help="Sync all locales in content directory",
    )
    c.add_argument(
        "--file",
        dest="file_filter",
        help="Only sync this file (e.g., 'auth.json')",
    )
    c.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be synced without making changes",
    )
    c.add_argument(
        "--clobber",
        action="store_true",
        help="Replace target files entirely instead of merging with existing",
    )
    c.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose output",
    )
    c.add_argument(
        "--merged",
        action="store_true",
        help="Output single merged JSON file per locale (for backend consumption)",
    )
    c.add_argument(
        "--output-dir",
        dest="output_dir",
        type=Path,
        default=GENERATED_DIR,
        help=f"Output directory for merged files (default: {GENERATED_DIR})",
    )
    c.set_defaults(func=_compile_handler, _parser=c)


def _register_decompile(gsub) -> None:
    c = gsub.add_parser(
        "decompile",
        help="Sync translations from generated/locales to content JSON.",
        description="Sync translations from generated/locales to content JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python decompile.py en --dry-run
    python decompile.py en --file feature-organizations.json
    python decompile.py en
    python decompile.py --all
    python decompile.py en --report-orphans
        """,
    )
    c.add_argument(
        "locale",
        nargs="?",
        help="Target locale code (e.g., 'en', 'de')",
    )
    c.add_argument(
        "--all",
        action="store_true",
        help="Sync all locales in generated/locales directory",
    )
    c.add_argument(
        "--file",
        dest="file_filter",
        help="Only sync this file (e.g., 'feature-organizations.json')",
    )
    c.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be synced without making changes",
    )
    c.add_argument(
        "--report-orphans",
        action="store_true",
        help="Report keys in content that don't exist in src",
    )
    c.add_argument(
        "--remove",
        action="store_true",
        help="Remove keys from content that don't exist in src (dangerous)",
    )
    c.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose output",
    )
    c.set_defaults(func=_decompile_handler, _parser=c)


def _register_hashes(gsub) -> None:
    c = gsub.add_parser(
        "hashes",
        help="Add content hashes to source keys and propagate to locales.",
        description="Add content hashes to source keys and propagate to locales.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    c.add_argument(
        "--dry-run", "-n", action="store_true", help="Show what would be done"
    )
    c.set_defaults(func=_hashes_handler, _parser=c)


def _register_add_field(gsub) -> None:
    c = gsub.add_parser(
        "add-field",
        help="Add a named field to every entry in the given locale JSON files.",
        description="Add a named field to every entry in the given locale JSON files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        # Mirrors the legacy add_field.py, whose epilog was `__doc__` (the full
        # module docstring). Reproduced literally here since this module's own
        # __doc__ differs.
        epilog="""
Add a field to all entries in locale content JSON files.

Inserts the field after "text" and before "content_hash"/"source_hash" for
consistent ordering. Entries that already have the field are skipped.

Usage:
    # Dry run (default)
    python3 locales/scripts/add_field.py --name renderer --value erb \\
        locales/content/*/email.json

    # Apply changes
    python3 locales/scripts/add_field.py --name renderer --value erb --apply \\
        locales/content/*/email.json

    # Null value (field present, value is null)
    python3 locales/scripts/add_field.py --name needs_review --apply \\
        locales/content/*/email.json

    # Non-string value (number, boolean, array, object) via JSON
    python3 locales/scripts/add_field.py --name priority --value-json 1 --apply \\
        locales/content/*/email.json
    python3 locales/scripts/add_field.py --name reviewed --value-json false --apply \\
        locales/content/*/email.json
""",
    )
    c.add_argument(
        "files",
        nargs="+",
        type=Path,
        help="Locale JSON files to process.",
    )
    c.add_argument(
        "--name",
        required=True,
        help="Field name to add.",
    )
    value_group = c.add_mutually_exclusive_group()
    value_group.add_argument(
        "--value",
        default=None,
        help="Field value as a string. Omit (and --value-json) for null.",
    )
    value_group.add_argument(
        "--value-json",
        default=None,
        help=(
            "Field value parsed as JSON. Use for numbers, booleans, arrays, "
            'or objects (e.g. --value-json true, --value-json \'["a","b"]\').'
        ),
    )
    c.add_argument(
        "--apply",
        action="store_true",
        help="Write changes. Default is dry run.",
    )
    c.set_defaults(func=_add_field_handler, _parser=c)


# ---------------------------------------------------------------------------
# compile  (<- build/compile.py)
# ---------------------------------------------------------------------------


def _compile_get_translations(content: dict[str, Any]) -> dict[str, str]:
    """Extract translations from content format.

    Only returns keys that have a non-empty 'text' field and no 'skip' flag.
    """
    translations = {}

    for key, entry in content.items():
        if not isinstance(entry, dict):
            continue
        if entry.get("skip"):
            continue
        text = entry.get("text", "")
        if text:
            translations[key] = text

    return translations


def _compile_is_metadata_key(key: str) -> bool:
    """Check if a key is metadata (has underscore-prefixed segment)."""
    return any(part.startswith("_") for part in key.split("."))


def _compile_get_source_keys(locale_dir: Path) -> set[str]:
    """Get the set of valid translation keys for a locale.

    Returns keys that have non-empty 'text', no 'skip' flag, and are not
    metadata keys (no underscore-prefixed segments in the key path).
    """
    keys: set[str] = set()

    if not locale_dir.exists():
        return keys

    for content_file in locale_dir.glob("*.json"):
        content = load_json_file(content_file)
        if not content:
            continue

        for key, entry in content.items():
            if _compile_is_metadata_key(key):
                continue
            if not isinstance(entry, dict):
                continue
            if entry.get("skip"):
                continue
            if entry.get("text", ""):
                keys.add(key)

    return keys


def _compile_sync_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
    clobber: bool = False,
) -> dict[str, int]:
    """Sync translations from content JSON to src/locales."""
    content_dir = CONTENT_DIR / locale
    target_dir = SRC_LOCALES_DIR / locale

    if not content_dir.exists():
        print(f"No content found for '{locale}'")
        print(f"  Expected: {content_dir}")
        return {}

    content_files = sorted(content_dir.glob("*.json"))
    if file_filter:
        content_files = [f for f in content_files if f.name == file_filter]

    if not content_files:
        print(f"No content files found in {content_dir}")
        return {}

    stats: dict[str, int] = {}

    for content_file in content_files:
        file_name = content_file.name
        target_file = target_dir / file_name

        content = load_json_file(content_file)
        if not content:
            continue

        translations = _compile_get_translations(content)
        if not translations:
            if verbose:
                print(f"  {file_name}: no translations yet")
            continue

        stats[file_name] = len(translations)

        if dry_run:
            print(
                f"\n[DRY-RUN] Would update {file_name} ({len(translations)} keys)"
            )
            if verbose:
                sample = list(translations.items())[:5]
                for key, value in sample:
                    print(f"  {key}: {value[:50]}...")
                if len(translations) > 5:
                    print(f"  ... and {len(translations) - 5} more")
            continue

        target_data = {} if clobber else load_json_file(target_file)

        for key, translation in translations.items():
            try:
                set_nested_value(target_data, key, translation, strict=True)
            except KeyPathConflictError as e:
                print(f"Error in {file_name}: {e}", file=sys.stderr)
                print(
                    "  This indicates conflicting key structures.",
                    file=sys.stderr,
                )
                print("  Fix the source data before syncing.", file=sys.stderr)
                return {}

        save_json_file(target_file, target_data)
        print(f"Updated {target_file}: {len(translations)} keys")

        if verbose:
            sample = list(translations.items())[:3]
            for key, value in sample:
                print(f"  {key}: {value[:40]}...")

    return stats


def _compile_sync_locale_merged(
    locale: str,
    output_dir: Path,
    dry_run: bool = False,
    verbose: bool = False,
) -> int:
    """Sync all translations for a locale into a single merged JSON file."""
    content_dir = CONTENT_DIR / locale

    if not content_dir.exists():
        if verbose:
            print(f"No content found for '{locale}'")
            print(f"  Expected: {content_dir}")
        return 0

    content_files = sorted(content_dir.glob("*.json"))

    if not content_files:
        if verbose:
            print(f"No content files found in {content_dir}")
        return 0

    all_translations: dict[str, str] = {}

    for content_file in content_files:
        content = load_json_file(content_file)
        if not content:
            continue

        translations = _compile_get_translations(content)
        all_translations.update(translations)

        if verbose:
            print(f"  {content_file.name}: {len(translations)} keys")

    if not all_translations:
        if verbose:
            print(f"No translations found for '{locale}'")
        return 0

    if dry_run:
        print(
            f"\n[DRY-RUN] Would write {output_dir / f'{locale}.json'} ({len(all_translations)} keys)"
        )
        if verbose:
            sample = list(all_translations.items())[:5]
            for key, value in sample:
                print(f"  {key}: {value[:50]}...")
            if len(all_translations) > 5:
                print(f"  ... and {len(all_translations) - 5} more")
        return len(all_translations)

    merged_data: dict[str, Any] = {}

    for key, translation in all_translations.items():
        try:
            set_nested_value(merged_data, key, translation, strict=True)
        except KeyPathConflictError as e:
            print(f"Error in {locale}: {e}", file=sys.stderr)
            print(
                "  This indicates conflicting key structures.", file=sys.stderr
            )
            print("  Fix the source data before syncing.", file=sys.stderr)
            sys.exit(1)

    output_file = output_dir / f"{locale}.json"
    save_json_file(output_file, merged_data)

    if verbose:
        print(f"Updated {output_file}: {len(all_translations)} keys")

    return len(all_translations)


def _compile_handler(args) -> int:
    parser: argparse.ArgumentParser = args._parser

    if not args.locale and not args.all:
        parser.error("Either LOCALE or --all must be specified")
    if args.locale and args.all:
        parser.error("Cannot specify both LOCALE and --all")
    if args.merged and args.file_filter:
        parser.error("Cannot use --file with --merged mode")
    if args.merged and args.clobber:
        parser.error("--clobber is not applicable in --merged mode")

    if args.all:
        locale_dirs = sorted(
            [d.name for d in CONTENT_DIR.iterdir() if d.is_dir()]
        )
        if not locale_dirs:
            print(f"No locale directories found in {CONTENT_DIR}")
            return 1
        print(
            f"Syncing {len(locale_dirs)} locales: {', '.join(locale_dirs[:5])}{'...' if len(locale_dirs) > 5 else ''}"
        )
        print()
    else:
        locale_dirs = [args.locale]

    # Merged mode
    if args.merged:
        output_dir = args.output_dir
        if args.verbose:
            print(f"Output directory: {output_dir}")

        all_key_counts: dict[str, int] = {}
        default_locale = SOURCE_LOCALE  # Used for percentage calculation

        for locale in locale_dirs:
            if args.verbose:
                if args.all:
                    print(f"\n{'=' * 60}")
                    print(f"Locale: {locale}")
                    print(f"{'=' * 60}")

                print(f"Syncing translations for '{locale}' (merged mode)")
                print(f"  From: {CONTENT_DIR / locale}")
                print(f"  To:   {output_dir / f'{locale}.json'}")
                print()

            key_count = _compile_sync_locale_merged(
                locale=locale,
                output_dir=output_dir,
                dry_run=args.dry_run,
                verbose=args.verbose,
            )

            if key_count > 0:
                all_key_counts[locale] = key_count

        if args.all and all_key_counts and not args.dry_run:
            source_keys = _compile_get_source_keys(CONTENT_DIR / default_locale)
            source_key_count = len(source_keys)

            locale_stats: dict[str, tuple[int, int, bool]] = {}
            for locale in all_key_counts:
                locale_keys = _compile_get_source_keys(CONTENT_DIR / locale)
                translated = len(source_keys & locale_keys)
                has_orphans = bool(locale_keys - source_keys)
                locale_stats[locale] = (
                    translated,
                    all_key_counts[locale],
                    has_orphans,
                )

            other_locales = [
                (loc, stats)
                for loc, stats in locale_stats.items()
                if loc != default_locale
            ]
            other_locales.sort(key=lambda x: x[1][0], reverse=True)

            print(f"\n{'=' * 60}")
            print(f"Locale sync complete ({len(all_key_counts)} locales)")
            print(f"{'=' * 60}")

            if default_locale in locale_stats:
                translated, total, _ = locale_stats[default_locale]
                print(
                    f"  {default_locale:8} {source_key_count:5} keys (100.0%)"
                )
                print()

            grand_total = sum(all_key_counts.values())
            for locale, (translated, total, has_orphans) in other_locales:
                if source_key_count > 0:
                    pct = (translated / source_key_count) * 100
                    pct_str = f"{pct:5.1f}%"
                else:
                    pct_str = "  N/A"
                marker = " *" if has_orphans else ""
                print(f"  {locale:8} {translated:5} keys ({pct_str}){marker}")

            print(f"{'=' * 60}")
            print(
                f"Total: {grand_total} keys  (* = has orphaned keys not in source)"
            )

        return 0

    # Standard (non-merged) mode
    all_stats: dict[str, dict[str, int]] = {}

    for locale in locale_dirs:
        if args.all:
            print(f"\n{'=' * 60}")
            print(f"Locale: {locale}")
            print(f"{'=' * 60}")

        print(f"Syncing translations for '{locale}'")
        print(f"  From: {CONTENT_DIR / locale}")
        print(f"  To:   {SRC_LOCALES_DIR / locale}")
        print()

        stats = _compile_sync_locale(
            locale=locale,
            file_filter=args.file_filter,
            dry_run=args.dry_run,
            verbose=args.verbose,
            clobber=args.clobber,
        )

        if stats:
            all_stats[locale] = stats
            if not args.dry_run and not args.all:
                total = sum(stats.values())
                print(
                    f"\nSynced {total} translations across {len(stats)} files"
                )

    if args.all and all_stats and not args.dry_run:
        print(f"\n{'=' * 60}")
        print("Summary")
        print(f"{'=' * 60}")
        grand_total = 0
        for locale, stats in sorted(all_stats.items()):
            locale_total = sum(stats.values())
            grand_total += locale_total
            print(f"  {locale}: {locale_total} keys across {len(stats)} files")
        print(f"{'=' * 60}")
        print(f"Total: {grand_total} keys across {len(all_stats)} locales")

    return 0


# ---------------------------------------------------------------------------
# decompile  (<- build/decompile.py)
# ---------------------------------------------------------------------------


def _decompile_sync_locale(
    locale: str,
    file_filter: str | None = None,
    dry_run: bool = False,
    verbose: bool = False,
    report_orphans: bool = False,
    remove_orphans: bool = False,
) -> dict[str, dict[str, int]]:
    """Sync translations from src/locales to content JSON."""
    src_dir = SRC_LOCALES_DIR / locale
    content_dir = CONTENT_DIR / locale

    if not src_dir.exists():
        print(f"No source found for '{locale}'")
        print(f"  Expected: {src_dir}")
        return {}

    src_files = sorted(src_dir.glob("*.json"))
    if file_filter:
        src_files = [f for f in src_files if f.name == file_filter]

    if not src_files:
        print(f"No source files found in {src_dir}")
        return {}

    stats: dict[str, dict[str, int]] = {}

    for src_file in src_files:
        file_name = src_file.name
        content_file = content_dir / file_name

        src_data = load_json_file(src_file)
        if not src_data:
            continue

        src_keys = dict(walk_keys(src_data))
        if not src_keys:
            if verbose:
                print(f"  {file_name}: no keys found")
            continue

        content_data = load_json_file(content_file)

        added = 0
        updated = 0
        unchanged = 0
        removed = 0
        orphans = []

        for key_path, value in src_keys.items():
            if key_path in content_data:
                existing = content_data[key_path]
                if isinstance(existing, dict):
                    if existing.get("text") != value:
                        if dry_run:
                            if verbose:
                                print(f"  [UPDATE] {key_path}")
                                print(
                                    f"    old: {existing.get('text', '')[:50]}..."
                                )
                                print(f"    new: {value[:50]}...")
                        existing["text"] = value
                        updated += 1
                    else:
                        unchanged += 1
                else:
                    content_data[key_path] = {"text": value}
                    updated += 1
            else:
                content_data[key_path] = {"text": value}
                added += 1
                if dry_run and verbose:
                    print(f"  [ADD] {key_path}: {value[:50]}...")

        if report_orphans or remove_orphans:
            for key_path in list(content_data.keys()):
                if key_path not in src_keys:
                    orphans.append(key_path)
                    if remove_orphans:
                        if dry_run and verbose:
                            print(f"  [REMOVE] {key_path}")
                        del content_data[key_path]
                        removed += 1

        stats[file_name] = {
            "added": added,
            "updated": updated,
            "unchanged": unchanged,
            "removed": removed,
            "orphans": len(orphans),
        }

        if dry_run:
            msg = f"\n[DRY-RUN] {file_name}: {added} new, {updated} updated, {unchanged} unchanged"
            if remove_orphans:
                msg += f", {removed} to remove"
            print(msg)
            if (report_orphans or remove_orphans) and orphans:
                print(f"  Orphaned keys ({len(orphans)}):")
                for key in orphans[:10]:
                    print(f"    - {key}")
                if len(orphans) > 10:
                    print(f"    ... and {len(orphans) - 10} more")
            continue

        if added > 0 or updated > 0 or removed > 0:
            save_json_file(content_file, content_data)
            msg = f"Updated {content_file}: {added} added, {updated} updated"
            if removed > 0:
                msg += f", {removed} removed"
            print(msg)
        elif verbose:
            print(f"  {file_name}: no changes")

        if report_orphans and orphans:
            print(f"  Orphaned keys in {file_name} ({len(orphans)}):")
            for key in orphans[:10]:
                print(f"    - {key}")
            if len(orphans) > 10:
                print(f"    ... and {len(orphans) - 10} more")

    return stats


def _decompile_handler(args) -> int:
    parser: argparse.ArgumentParser = args._parser

    if not args.locale and not args.all:
        parser.error("Either LOCALE or --all must be specified")
    if args.locale and args.all:
        parser.error("Cannot specify both LOCALE and --all")

    if args.all:
        locale_dirs = sorted(
            [d.name for d in SRC_LOCALES_DIR.iterdir() if d.is_dir()]
        )
        if not locale_dirs:
            print(f"No locale directories found in {SRC_LOCALES_DIR}")
            return 1
        print(
            f"Syncing {len(locale_dirs)} locales: {', '.join(locale_dirs[:5])}{'...' if len(locale_dirs) > 5 else ''}"
        )
        print()
    else:
        locale_dirs = [args.locale]

    all_stats: dict[str, dict[str, dict[str, int]]] = {}

    for locale in locale_dirs:
        if args.all:
            print(f"\n{'=' * 60}")
            print(f"Locale: {locale}")
            print(f"{'=' * 60}")

        print(f"Syncing translations for '{locale}'")
        print(f"  From: {SRC_LOCALES_DIR / locale}")
        print(f"  To:   {CONTENT_DIR / locale}")
        print()

        stats = _decompile_sync_locale(
            locale=locale,
            file_filter=args.file_filter,
            dry_run=args.dry_run,
            verbose=args.verbose,
            report_orphans=args.report_orphans,
            remove_orphans=args.remove,
        )

        if stats:
            all_stats[locale] = stats
            if not args.dry_run and not args.all:
                total_added = sum(s["added"] for s in stats.values())
                total_updated = sum(s["updated"] for s in stats.values())
                print(
                    f"\nSynced {total_added} new, {total_updated} updated across {len(stats)} files"
                )

    if args.all and all_stats and not args.dry_run:
        print(f"\n{'=' * 60}")
        print("Summary")
        print(f"{'=' * 60}")
        grand_added = 0
        grand_updated = 0
        for locale, file_stats in sorted(all_stats.items()):
            locale_added = sum(s["added"] for s in file_stats.values())
            locale_updated = sum(s["updated"] for s in file_stats.values())
            grand_added += locale_added
            grand_updated += locale_updated
            print(
                f"  {locale}: {locale_added} added, {locale_updated} updated across {len(file_stats)} files"
            )
        print(f"{'=' * 60}")
        print(
            f"Total: {grand_added} added, {grand_updated} updated across {len(all_stats)} locales"
        )

    return 0


# ---------------------------------------------------------------------------
# hashes  (<- add_hashes.py)
# ---------------------------------------------------------------------------


def _hashes_normalize_source_message(text: str) -> str:
    """Normalize source text for consistent hashing."""
    return text.strip()  # don't modify case


def _hashes_compute_hash(text: str) -> str:
    """Compute SHA256 hash of normalized text, truncated to 8 chars."""
    normalized = _hashes_normalize_source_message(text).encode("utf-8")
    return hashlib.sha256(normalized).hexdigest()[:8]


def _hashes_add_to_source(dry_run: bool = False) -> dict[str, dict[str, str]]:
    """Add content_hash to all source locale files."""
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

            new_hash = _hashes_compute_hash(text)
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


def _hashes_init_missing_in_locales(
    source_hashes: dict[str, dict[str, str]], dry_run: bool = False
) -> None:
    """Initialize missing source_hash in translation locale files."""
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


def _hashes_handler(args) -> int:
    print(f"Source locale: {SOURCE_LOCALE}")
    print(f"Content dir: {CONTENT_DIR}\n")

    print("=== Adding content_hash to source ===")
    source_hashes = _hashes_add_to_source(dry_run=args.dry_run)

    print("\n=== Initializing missing source_hash in locales ===")
    _hashes_init_missing_in_locales(source_hashes, dry_run=args.dry_run)

    print("\nDone.")
    return 0


# ---------------------------------------------------------------------------
# add-field  (<- add_field.py)
# ---------------------------------------------------------------------------


def _add_field_to_file(
    path: Path,
    name: str,
    value: object,
    *,
    dry_run: bool = True,
) -> int:
    """Add a field to all entries in a locale JSON file.

    Returns count of entries modified.
    """
    data = json.loads(path.read_text(encoding="utf-8"))
    modified = 0

    for key, entry in data.items():
        if not isinstance(entry, dict):
            continue
        if name in entry:
            continue

        new_entry: dict[str, object] = {}
        inserted = False
        for k, v in entry.items():
            new_entry[k] = v
            if k == "text" and not inserted:
                new_entry[name] = value
                inserted = True
        if not inserted:
            new_entry[name] = value

        data[key] = new_entry
        modified += 1

    if modified > 0 and not dry_run:
        path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    return modified


def _add_field_handler(args) -> int:
    if args.value_json is not None:
        try:
            value: object = json.loads(args.value_json)
        except json.JSONDecodeError as exc:
            print(
                f"Error: --value-json is not valid JSON: {exc}", file=sys.stderr
            )
            return 2
    else:
        value = args.value

    dry_run = not args.apply
    if dry_run:
        print("DRY RUN (use --apply to write changes)\n")

    total_modified = 0
    total_files = 0

    for path in args.files:
        if not path.exists():
            print(f"  {path}: not found, skipping")
            continue
        if not path.is_file():
            continue

        total_files += 1
        count = _add_field_to_file(path, args.name, value, dry_run=dry_run)

        if count > 0:
            status = "would update" if dry_run else "updated"
            print(f"  {path}: {status} {count} entries")
        else:
            print(f"  {path}: no changes needed")

        total_modified += count

    label = "would modify" if dry_run else "modified"
    print(
        f"\nTotal: {label} {total_modified} entries across {total_files} files"
    )
    return 0
