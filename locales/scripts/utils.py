#!/usr/bin/env python3
"""
Shared utilities for translation scripts.

Provides common functions for JSON file handling and key traversal.
"""

import json
import sys
from pathlib import Path
from typing import Any, Iterator


def walk_keys(obj: dict[str, Any], prefix: str = "") -> Iterator[tuple[str, str]]:
    """Recursively walk a nested dict, yielding (key_path, value) tuples.

    Skips metadata keys (prefixed with '_').
    Only yields leaf string values.

    Args:
        obj: Dictionary to walk.
        prefix: Current key path prefix.

    Yields:
        Tuples of (full_key_path, string_value).
    """
    for key, value in obj.items():
        # Skip metadata keys
        if key.startswith("_"):
            continue

        full_key = f"{prefix}.{key}" if prefix else key

        if isinstance(value, dict):
            yield from walk_keys(value, full_key)
        elif isinstance(value, str):
            yield (full_key, value)
        # Skip non-string, non-dict values (arrays, numbers, etc.)


def load_json_file(file_path: Path) -> dict:
    """Load a JSON file, returning empty dict if not found or invalid.

    Args:
        file_path: Path to JSON file.

    Returns:
        Parsed JSON as dict, or empty dict on error.
    """
    if file_path.exists():
        try:
            with open(file_path, encoding="utf-8") as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"Warning: Invalid JSON in {file_path}: {e}", file=sys.stderr)
            return {}
    return {}


def save_json_file(file_path: Path, data: dict) -> None:
    """Save a dictionary to a JSON file with consistent formatting.

    Creates parent directories if needed.

    Args:
        file_path: Path to write.
        data: Dictionary to serialize.
    """
    file_path.parent.mkdir(parents=True, exist_ok=True)

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


class KeyPathConflictError(ValueError):
    """Raised when a key path conflicts with existing non-dict value."""

    pass


def set_nested_value(
    obj: dict,
    key_path: str,
    value: str,
    *,
    strict: bool = True,
) -> None:
    """Set a value in a nested dict using dot-notation key path.

    Args:
        obj: Dictionary to modify.
        key_path: Dot-notation path (e.g., 'web.COMMON.tagline').
        value: Value to set.
        strict: If True, raise KeyPathConflictError on type conflicts.
                If False, silently overwrite (legacy behavior).

    Raises:
        KeyPathConflictError: If strict=True and an intermediate key
            exists but is not a dict.
    """
    parts = key_path.split(".")
    current = obj

    # Navigate/create nested structure
    for part in parts[:-1]:
        if part not in current:
            current[part] = {}
        elif not isinstance(current[part], dict):
            if strict:
                raise KeyPathConflictError(
                    f"Cannot set '{key_path}': '{part}' exists but is not a dict "
                    f"(value: {current[part]!r})"
                )
            # Legacy behavior: overwrite
            current[part] = {}
        current = current[part]

    # Set the final value
    current[parts[-1]] = value
