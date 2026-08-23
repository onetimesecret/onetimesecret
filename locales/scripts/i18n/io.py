# locales/scripts/i18n/io.py

"""JSON file handling and key traversal.

Ported verbatim from the legacy ``locales/scripts/keys.py``. Provides the
shared primitives for reading, walking, and writing the flat/nested locale
content files.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, Optional

# ---------------------------------------------------------------------------
# The entry model
# ---------------------------------------------------------------------------
# ONE declaration of what a content entry is. ``text`` is the only translatable
# field; every other name below is authoring or bookkeeping metadata that
# ``tasks export`` never writes into a target locale.
#
# Two readers with two different answers to "what is a key" is what produced
# #4080: a field-blind flattener compared ``<key>.context`` as if it were
# translatable, and swapping in the text-only view then collapsed
# ``skip: true``, empty text, and absent-key into one indistinguishable
# "not there". Everything derives from :func:`read_entries` now, so a field
# added here cannot silently become translatable in whichever reader happens to
# be field-blind that week. Same lesson as the twin token normalizers (#4023,
# #4047): declare it once, derive the views.

TEXT_FIELD = "text"

METADATA_FIELDS = frozenset(
    {
        "skip",  # intentional non-translation; source stays as-is
        "context",  # en-only authoring note for translators
        "note",  # en-only authoring note
        "renderer",  # which template engine renders this string
        "source_hash",  # target: the en content_hash this was translated against
        "content_hash",  # en: watermark of the current source text
    }
)


@dataclass(frozen=True)
class Entry:
    """One content entry, read with no policy applied.

    ``text is None`` means the field was absent or not a string. That is
    distinct from ``text == ""`` (present but untranslated), which is in turn
    distinct from the key having no ``Entry`` at all (absent from the file) —
    three states the text-only view cannot tell apart.

    ``extra`` lists field names that are neither ``text`` nor a declared
    metadata field, so a gate can surface a new field instead of letting a
    field-blind reader guess at it.
    """

    key: str
    text: Optional[str] = None
    skip: bool = False
    source_hash: Optional[str] = None
    content_hash: Optional[str] = None
    extra: tuple[str, ...] = ()


def _nonempty_str(value: Any) -> Optional[str]:
    return value if isinstance(value, str) and value else None


def read_entries(obj: dict[str, Any], prefix: str = "") -> dict[str, Entry]:
    """Read a content dict into ``key_path -> Entry``, applying no policy.

    Supports the same two formats as :func:`walk_keys`:

    1. Flat format (locales/content/): dot-notation keys whose values are entry
       objects: ``{"web.COMMON.tagline": {"text": "...", "context": "..."}}``
    2. Nested format (legacy, generated Vue locales): nested dicts with string
       leaves: ``{"web": {"COMMON": {"tagline": "..."}}}``

    Underscore-prefixed keys (file-level guidance blocks) are dropped in both
    formats — they are not content and have no entry shape. Nothing else is
    filtered: ``skip``, empty text, and stale watermarks are all preserved for
    the caller to classify.
    """
    out: dict[str, Entry] = {}
    for key, value in obj.items():
        # Skip metadata keys (any dotted segment starting with underscore)
        if any(part.startswith("_") for part in key.split(".")):
            continue

        full_key = f"{prefix}.{key}" if prefix else key

        # Flat format: the presence of `text` is what makes a dict an entry.
        # (Deliberately the same discriminator the text-only view has always
        # used — every entry in the corpus carries `text`, including skipped
        # ones, so a stricter or looser test would only change behaviour on
        # shapes that do not exist.)
        if isinstance(value, dict) and TEXT_FIELD in value:
            text = value[TEXT_FIELD]
            out[full_key] = Entry(
                key=full_key,
                text=text if isinstance(text, str) else None,
                skip=bool(value.get("skip", False)),
                source_hash=_nonempty_str(value.get("source_hash")),
                content_hash=_nonempty_str(value.get("content_hash")),
                extra=tuple(
                    sorted(
                        field
                        for field in value
                        if field != TEXT_FIELD
                        and field not in METADATA_FIELDS
                        and not field.startswith("_")
                    )
                ),
            )
        # Nested format: recurse into nested dicts
        elif isinstance(value, dict):
            out.update(read_entries(value, full_key))
        # Nested format: leaf string value
        elif isinstance(value, str):
            out[full_key] = Entry(key=full_key, text=value)
        # Skip non-string, non-dict values (arrays, numbers, etc.)

    return out


def classify_entry(entry: Optional[Entry], en_hash: Optional[str] = None) -> str:
    """Classify one en key's state in a target locale.

    ``entry`` is the target's entry for the key (``None`` if absent);
    ``en_hash`` is the key's current en ``content_hash`` (``None`` if the source
    is unhashed, or if the caller does not care about staleness).

    Returns one of:
      - ``"skipped"``  — target marked it skip (an intentional non-translation).
      - ``"missing"``  — absent, or empty text without a skip flag.
      - ``"stale"``    — translated, but its ``source_hash`` watermark no longer
                         matches en (English moved after translation). Requires a
                         present watermark AND a present en hash: an absent
                         watermark can't prove drift, so it reads as ``current``.
      - ``"current"``  — translated and the watermark still matches en.
    """
    if entry is not None and entry.skip:
        return "skipped"
    if entry is None or not entry.text:
        return "missing"
    if en_hash and entry.source_hash and entry.source_hash != en_hash:
        return "stale"
    return "current"


def walk_keys(
    obj: dict[str, Any], prefix: str = ""
) -> Iterator[tuple[str, str]]:
    """Walk a dict, yielding (key_path, text_value) tuples.

    The translatable-text view of :func:`read_entries`: skip-marked entries and
    entries whose ``text`` is absent or non-string are dropped, so an absent key
    and a deliberately-skipped one are indistinguishable here. Callers that must
    tell those apart read :func:`read_entries` and classify.

    Args:
        obj: Dictionary to walk.
        prefix: Current key path prefix (used for nested format recursion).

    Yields:
        Tuples of (full_key_path, string_value).
    """
    for entry in read_entries(obj, prefix).values():
        if entry.skip or entry.text is None:
            continue
        yield (entry.key, entry.text)


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

    # Write to a sibling temp file and rename into place so readers never
    # observe a half-written file (e.g. the Ruby backend booting while
    # `content compile --all` is mid-write, or a compile killed with Ctrl-C).
    # The name must be unique per writer: two concurrent compiles of the same
    # locale sharing one temp name interleave their writes and rename the torn
    # result into place, which is the failure this function exists to prevent.
    fd, tmp_name = tempfile.mkstemp(
        dir=file_path.parent, prefix=f".{file_path.name}.", suffix=".tmp"
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        # mkstemp creates 0600; these are generated, world-readable artifacts.
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, file_path)
    finally:
        tmp_path.unlink(missing_ok=True)


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
