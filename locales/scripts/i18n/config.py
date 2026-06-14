"""Single source of truth for locale-tooling paths and constants.

Everything is resolved from this file's location so the package works
regardless of the current working directory. The default ``DB_FILE`` path is
identical to the legacy ``locales/scripts/store.py`` value, so default
behavior is unchanged; ``I18N_DB_FILE`` provides an override for isolated
testing.
"""

from __future__ import annotations

import os
from pathlib import Path

# Directory layout (resolved from this file):
#   locales/scripts/i18n/config.py
#   parents[0] = i18n   parents[1] = scripts   parents[2] = locales
LOCALES_DIR: Path = Path(__file__).resolve().parents[2]
SCRIPTS_DIR: Path = Path(__file__).resolve().parents[1]

# Source locale (e.g. "en"); overridable to translate from a different base.
SOURCE_LOCALE: str = os.environ.get("I18N_DEFAULT_LOCALE", "en")

# Content (flat-key JSON, version-controlled source of truth).
CONTENT_DIR: Path = LOCALES_DIR / "content"
EN_DIR: Path = CONTENT_DIR / SOURCE_LOCALE

# App-consumable merged output. Mirrors build/compile.py's GENERATED_LOCALES_DIR
# (PROJECT_ROOT / "generated" / "locales", where PROJECT_ROOT == LOCALES_DIR.parent).
GENERATED_DIR: Path = LOCALES_DIR.parent / "generated" / "locales"

# Working database for translation workflows.
DB_DIR: Path = LOCALES_DIR / "db"
SCHEMA_FILE: Path = DB_DIR / "schema.sql"
DB_FILE: Path = Path(os.environ.get("I18N_DB_FILE", DB_DIR / "tasks.db"))

# Tables that can be exported/imported for version control.
COMMITTABLE_TABLES: list[str] = ["glossary", "session_log", "translation_issues"]


def iter_locale_dirs(include_source: bool = False) -> list[Path]:
    """Return content locale directories, sorted by name.

    Args:
        include_source: If True, include the source locale directory
            (e.g. ``content/en``). Defaults to False.

    Returns:
        Sorted list of directory paths under ``CONTENT_DIR``, excluding
        hidden directories (names starting with ``.``) and, unless
        ``include_source`` is set, the source locale.
    """
    if not CONTENT_DIR.exists():
        return []

    dirs = [
        d
        for d in CONTENT_DIR.iterdir()
        if d.is_dir()
        and not d.name.startswith(".")
        and (include_source or d.name != SOURCE_LOCALE)
    ]
    return sorted(dirs, key=lambda d: d.name)
