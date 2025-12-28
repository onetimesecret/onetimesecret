#!/usr/bin/env python3
"""
Reorganizes keys from uncategorized.json into proper locale files based on category mappings.

Reads a category-mapping.json configuration file that defines:
- Source keys in uncategorized.json
- Target file and nested path for each key

Features:
- Atomic writes with backup (.bak files)
- Verification pass to ensure no keys lost
- Dry-run mode for safe testing
- Parallel processing for --all mode
- Merges into existing files (preserves existing keys)

Usage:
    ./reorganize-uncategorized.py --locale en --dry-run    # Preview changes
    ./reorganize-uncategorized.py --locale en              # Apply to single locale
    ./reorganize-uncategorized.py --all                    # Apply to all locales
    ./reorganize-uncategorized.py --all --backup           # Keep backup files

Exit codes:
    0 = Success
    1 = Errors occurred
"""

import argparse
import json
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional


@dataclass
class KeyMapping:
    """Mapping for a single key from uncategorized to target."""
    source_key: str
    target_file: str
    target_path: str  # Dot-separated path, e.g., "web.domains.key-name"


@dataclass
class MoveResult:
    """Result of moving a single key."""
    source_key: str
    target_file: str
    target_path: str
    success: bool
    error: Optional[str] = None


@dataclass
class ReorganizeResult:
    """Result of reorganizing a locale."""
    locale: str
    total_keys: int
    keys_moved: int
    keys_skipped: int
    keys_failed: int
    files_created: list[str] = field(default_factory=list)
    files_modified: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    dry_run: bool = False

    @property
    def success(self) -> bool:
        return self.keys_failed == 0 and not self.errors


def load_category_mapping(mapping_file: Path) -> list[KeyMapping]:
    """Load category mapping configuration from JSON file."""
    with open(mapping_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    mappings = []
    for item in data.get("mappings", []):
        mappings.append(KeyMapping(
            source_key=item["source_key"],
            target_file=item["target_file"],
            target_path=item["target_path"]
        ))

    return mappings


def set_nested_value(obj: dict, path: str, value: Any) -> None:
    """Set a value at a nested path (dot-separated) in a dict."""
    parts = path.split(".")
    current = obj

    # Navigate to parent, creating intermediate dicts as needed
    for part in parts[:-1]:
        if part not in current:
            current[part] = {}
        elif not isinstance(current[part], dict):
            # Path conflict - can't set nested value on non-dict
            raise ValueError(f"Path conflict: {part} is not a dict")
        current = current[part]

    # Set the final value
    final_key = parts[-1]
    current[final_key] = value


def get_nested_value(obj: dict, path: str) -> Optional[Any]:
    """Get a value at a nested path (dot-separated) from a dict."""
    parts = path.split(".")
    current = obj

    for part in parts:
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]

    return current


def load_json_file(file_path: Path) -> dict:
    """Load a JSON file, returning empty dict if file doesn't exist."""
    if not file_path.exists():
        return {}

    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json_file(file_path: Path, data: dict, backup: bool = False) -> None:
    """Save a JSON file with optional backup."""
    if backup and file_path.exists():
        backup_path = file_path.with_suffix(".json.bak")
        shutil.copy2(file_path, backup_path)

    # Ensure parent directory exists
    file_path.parent.mkdir(parents=True, exist_ok=True)

    # Write to temp file first (atomic write)
    temp_path = file_path.with_suffix(".json.tmp")
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # Move temp file to final location
    temp_path.replace(file_path)


def reorganize_locale(
    locale_dir: Path,
    locale: str,
    mappings: list[KeyMapping],
    dry_run: bool = False,
    backup: bool = True,
    verify: bool = True
) -> ReorganizeResult:
    """Reorganize uncategorized.json for a single locale."""
    result = ReorganizeResult(
        locale=locale,
        total_keys=0,
        keys_moved=0,
        keys_skipped=0,
        keys_failed=0,
        dry_run=dry_run
    )

    uncategorized_file = locale_dir / "uncategorized.json"
    if not uncategorized_file.exists():
        result.errors.append(f"uncategorized.json not found in {locale_dir}")
        return result

    # Load uncategorized data
    try:
        uncategorized = load_json_file(uncategorized_file)
        result.total_keys = len(uncategorized)
    except json.JSONDecodeError as e:
        result.errors.append(f"Failed to parse uncategorized.json: {e}")
        return result

    # Build mapping lookup
    mapping_lookup = {m.source_key: m for m in mappings}

    # Track which target files need to be modified
    target_files: dict[str, dict] = {}  # filename -> data
    keys_to_remove: list[str] = []

    for source_key, value in uncategorized.items():
        if source_key not in mapping_lookup:
            result.keys_skipped += 1
            continue

        mapping = mapping_lookup[source_key]
        target_file = mapping.target_file
        target_path = mapping.target_path

        # Load target file if not already loaded
        if target_file not in target_files:
            target_path_full = locale_dir / target_file
            target_files[target_file] = {
                "path": target_path_full,
                "data": load_json_file(target_path_full),
                "existed": target_path_full.exists()
            }

        # Check if target path already has a value
        existing = get_nested_value(target_files[target_file]["data"], target_path)
        if existing is not None:
            result.errors.append(
                f"Target path already exists: {target_file}:{target_path} (key: {source_key})"
            )
            result.keys_failed += 1
            continue

        # Set the value at target path
        try:
            set_nested_value(target_files[target_file]["data"], target_path, value)
            keys_to_remove.append(source_key)
            result.keys_moved += 1
        except ValueError as e:
            result.errors.append(f"Failed to set {target_path} in {target_file}: {e}")
            result.keys_failed += 1

    # Track created vs modified files
    for filename, file_info in target_files.items():
        if file_info["existed"]:
            result.files_modified.append(filename)
        else:
            result.files_created.append(filename)

    # Apply changes if not dry run
    if not dry_run and result.keys_moved > 0:
        # Save modified target files
        for filename, file_info in target_files.items():
            try:
                save_json_file(file_info["path"], file_info["data"], backup=backup)
            except Exception as e:
                result.errors.append(f"Failed to save {filename}: {e}")
                result.keys_failed += result.keys_moved
                result.keys_moved = 0
                return result

        # Update uncategorized.json (remove moved keys)
        for key in keys_to_remove:
            del uncategorized[key]

        try:
            save_json_file(uncategorized_file, uncategorized, backup=backup)
        except Exception as e:
            result.errors.append(f"Failed to update uncategorized.json: {e}")
            # Note: target files already saved, this is a partial failure

    # Verification pass
    if verify and not dry_run and result.keys_moved > 0:
        verification_errors = verify_reorganization(
            locale_dir, keys_to_remove, mapping_lookup
        )
        result.errors.extend(verification_errors)

    return result


def verify_reorganization(
    locale_dir: Path,
    moved_keys: list[str],
    mapping_lookup: dict[str, KeyMapping]
) -> list[str]:
    """Verify that all moved keys can be found at their target locations."""
    errors = []

    for source_key in moved_keys:
        mapping = mapping_lookup[source_key]
        target_file = locale_dir / mapping.target_file

        if not target_file.exists():
            errors.append(f"Verification failed: {mapping.target_file} not found")
            continue

        try:
            data = load_json_file(target_file)
            value = get_nested_value(data, mapping.target_path)
            if value is None:
                errors.append(
                    f"Verification failed: {source_key} not found at "
                    f"{mapping.target_file}:{mapping.target_path}"
                )
        except Exception as e:
            errors.append(f"Verification error for {source_key}: {e}")

    return errors


def print_result(result: ReorganizeResult, verbose: bool = False) -> None:
    """Print a human-readable result summary."""
    prefix = "[DRY RUN] " if result.dry_run else ""

    print(f"\n{prefix}Locale: {result.locale}")
    print(f"  Total keys: {result.total_keys}")
    print(f"  Keys moved: {result.keys_moved}")
    print(f"  Keys skipped: {result.keys_skipped}")
    print(f"  Keys failed: {result.keys_failed}")

    if result.files_created:
        print(f"  Files created: {', '.join(result.files_created)}")
    if result.files_modified:
        print(f"  Files modified: {', '.join(result.files_modified)}")

    if result.errors and verbose:
        print("  Errors:")
        for error in result.errors[:10]:  # Limit to first 10
            print(f"    - {error}")
        if len(result.errors) > 10:
            print(f"    ... and {len(result.errors) - 10} more")


def process_locale_wrapper(args_tuple) -> ReorganizeResult:
    """Wrapper for parallel processing."""
    locale_dir, locale, mappings, dry_run, backup, verify = args_tuple
    return reorganize_locale(locale_dir, locale, mappings, dry_run, backup, verify)


def main():
    parser = argparse.ArgumentParser(
        description="Reorganize keys from uncategorized.json into proper locale files"
    )
    parser.add_argument(
        "--locale",
        help="Locale code to reorganize (e.g., 'en', 'fr_FR')"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Reorganize all locales"
    )
    parser.add_argument(
        "--mapping",
        type=Path,
        help="Path to category-mapping.json (default: ./category-mapping.json)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without modifying files"
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        default=True,
        help="Create .bak backup files (default: True)"
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Do not create backup files"
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        default=True,
        help="Verify keys after moving (default: True)"
    )
    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="Skip verification after moving"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Show detailed output"
    )
    parser.add_argument(
        "-q", "--quiet",
        action="store_true",
        help="Minimal output"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Number of parallel workers for --all mode (default: 4)"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    # Validate arguments
    if not args.locale and not args.all:
        parser.error("Either --locale or --all must be specified")

    if args.locale and args.all:
        parser.error("Cannot specify both --locale and --all")

    # Resolve backup and verify flags
    backup = args.backup and not args.no_backup
    verify = args.verify and not args.no_verify

    # Determine paths
    script_dir = Path(__file__).parent
    locales_dir = (script_dir / "../../../locales").resolve()

    if not locales_dir.is_dir():
        print(f"Error: Locales directory not found: {locales_dir}", file=sys.stderr)
        return 1

    # Load category mapping
    mapping_file = args.mapping or (script_dir / "category-mapping.json")
    if not mapping_file.exists():
        print(f"Error: Category mapping file not found: {mapping_file}", file=sys.stderr)
        print("\nCreate a category-mapping.json file with the following structure:")
        print(json.dumps({
            "mappings": [
                {
                    "source_key": "example-key",
                    "target_file": "feature-example.json",
                    "target_path": "web.example.key-name"
                }
            ]
        }, indent=2))
        return 1

    try:
        mappings = load_category_mapping(mapping_file)
    except Exception as e:
        print(f"Error loading category mapping: {e}", file=sys.stderr)
        return 1

    if not mappings:
        print("Warning: No mappings found in category-mapping.json", file=sys.stderr)
        return 0

    if not args.quiet:
        print(f"Loaded {len(mappings)} key mappings from {mapping_file}")

    # Determine which locales to process
    locales_to_process = []
    if args.all:
        locales_to_process = [
            d.name for d in locales_dir.iterdir()
            if d.is_dir() and not d.name.startswith(".")
        ]
    else:
        locales_to_process = [args.locale]

    # Process locales
    results = []

    if args.all and len(locales_to_process) > 1:
        # Parallel processing
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = {
                executor.submit(
                    process_locale_wrapper,
                    (locales_dir / locale, locale, mappings, args.dry_run, backup, verify)
                ): locale
                for locale in locales_to_process
            }

            for future in as_completed(futures):
                locale = futures[future]
                try:
                    result = future.result()
                    results.append(result)
                except Exception as e:
                    results.append(ReorganizeResult(
                        locale=locale,
                        total_keys=0,
                        keys_moved=0,
                        keys_skipped=0,
                        keys_failed=0,
                        errors=[str(e)]
                    ))
    else:
        # Sequential processing
        for locale in locales_to_process:
            locale_dir = locales_dir / locale
            if not locale_dir.is_dir():
                if not args.quiet:
                    print(f"Warning: Locale directory not found: {locale}", file=sys.stderr)
                continue

            result = reorganize_locale(
                locale_dir, locale, mappings,
                dry_run=args.dry_run,
                backup=backup,
                verify=verify
            )
            results.append(result)

    # Output results
    if args.json:
        output = {
            "summary": {
                "locales_processed": len(results),
                "total_keys_moved": sum(r.keys_moved for r in results),
                "total_failures": sum(r.keys_failed for r in results),
                "dry_run": args.dry_run
            },
            "results": [
                {
                    "locale": r.locale,
                    "total_keys": r.total_keys,
                    "keys_moved": r.keys_moved,
                    "keys_skipped": r.keys_skipped,
                    "keys_failed": r.keys_failed,
                    "files_created": r.files_created,
                    "files_modified": r.files_modified,
                    "errors": r.errors,
                    "success": r.success
                }
                for r in results
            ]
        }
        print(json.dumps(output, indent=2, ensure_ascii=False))
    elif not args.quiet:
        for result in sorted(results, key=lambda r: r.locale):
            print_result(result, verbose=args.verbose)

        # Summary
        print("\n" + "=" * 60)
        print("SUMMARY")
        print("=" * 60)
        total_moved = sum(r.keys_moved for r in results)
        total_failed = sum(r.keys_failed for r in results)
        total_skipped = sum(r.keys_skipped for r in results)

        if args.dry_run:
            print("[DRY RUN MODE - No files modified]")

        print(f"Locales processed: {len(results)}")
        print(f"Total keys moved: {total_moved}")
        print(f"Total keys skipped: {total_skipped}")
        print(f"Total keys failed: {total_failed}")

        failed_locales = [r.locale for r in results if not r.success]
        if failed_locales:
            print(f"Locales with errors: {', '.join(failed_locales)}")

    # Exit code
    has_failures = any(not r.success for r in results)
    return 1 if has_failures else 0


if __name__ == "__main__":
    sys.exit(main())
