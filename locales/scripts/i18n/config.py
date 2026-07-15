# locales/scripts/i18n/config.py

"""Single source of truth for locale-tooling paths and constants.

Everything is resolved from this file's location so the package works
regardless of the current working directory. All path defaults are identical
to the legacy loose-script values, so default behavior is unchanged.

Four environment overrides relocate the filesystem surfaces for isolated
testing (the suite under ``locales/scripts/tests`` drives the real CLI
against a throwaway tmp tree via these):

* ``I18N_CONTENT_DIR``   -- source-of-truth flat-key JSON tree
* ``I18N_GENERATED_DIR`` -- app-consumable merged compiled output
* ``I18N_DB_DIR``        -- schema/exports/working-DB directory
* ``I18N_DB_FILE``       -- the working SQLite file (defaults under DB_DIR)

``I18N_DEFAULT_LOCALE`` additionally overrides the source locale.
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
CONTENT_DIR: Path = Path(os.environ.get("I18N_CONTENT_DIR", LOCALES_DIR / "content"))
EN_DIR: Path = CONTENT_DIR / SOURCE_LOCALE

# App-consumable merged output. The live compile target: merged per-locale
# JSON under PROJECT_ROOT / "generated" / "locales" (PROJECT_ROOT == LOCALES_DIR.parent).
GENERATED_DIR: Path = Path(
    os.environ.get("I18N_GENERATED_DIR", LOCALES_DIR.parent / "generated" / "locales")
)

# Resolved per-locale governance, derived on demand (not vendored) by
# locales/scripts/derive-governance.sh into generated/i18n/.resolved/<locale>.json.
# Sibling of GENERATED_DIR under the same generated/ root, so it tracks the
# I18N_GENERATED_DIR override. Carries the BOUND glossary (senses[*].target) that
# `validate glossary` checks translations against — distinct from the committable
# DB `glossary` table (local decisions). Absent until derive-governance.sh runs.
RESOLVED_DIR: Path = Path(
    os.environ.get("I18N_RESOLVED_DIR", GENERATED_DIR.parent / "i18n" / ".resolved")
)

# Working database for translation workflows.
DB_DIR: Path = Path(os.environ.get("I18N_DB_DIR", LOCALES_DIR / "db"))
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
