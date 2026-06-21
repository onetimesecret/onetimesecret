# locales/scripts/i18n/db.py

"""SQLite connection management and schema lifecycle.

Ported from the legacy ``locales/scripts/store.py`` (connection + schema
pieces only). Query/export/import logic lives with the ``db`` command group,
not here. Path constants come from :mod:`i18n.config`.

Concurrency is the tool's job, not the caller's. ``tasks.db`` is a single
file shared by every parallel locale agent, so :func:`get_connection` sets
two pragmas on every connect:

- ``journal_mode=WAL`` — readers never block the writer and vice versa, which
  is what makes one-writer-per-locale fan-out safe. WAL is persisted on the
  file, but we set it each connect so a freshly created or copied DB is always
  in WAL without an out-of-band step.
- ``busy_timeout`` (= the connect ``timeout``, in ms) — on lock contention
  SQLite blocks and retries internally for this long instead of raising
  ``database is locked`` immediately. Callers and agents therefore do not need
  their own "wait and retry on locked" loop.
"""

from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from typing import Iterator

from .config import DB_DIR, DB_FILE, SCHEMA_FILE

# How long (seconds) a connection waits on a held lock before giving up.
# Drives both the sqlite3 connect timeout and the busy_timeout pragma.
BUSY_TIMEOUT_SECONDS = 30


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    """Context manager for database connections.

    Enables WAL and a busy timeout on every connection so concurrent locale
    agents tolerate lock contention without caller-side retry logic.
    Abstracts connection handling for future migration to libsql.
    """
    conn = sqlite3.connect(DB_FILE, timeout=BUSY_TIMEOUT_SECONDS)
    conn.row_factory = sqlite3.Row
    # Set outside any transaction (connection is in autocommit here).
    # journal_mode=WAL fails harmlessly (returns the existing mode) on a
    # read-only or :memory: DB, so guard nothing — just apply.
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(f"PRAGMA busy_timeout={BUSY_TIMEOUT_SECONDS * 1000}")
    try:
        yield conn
    finally:
        conn.close()


# Schema versions - add new entries when schema changes
SCHEMA_VERSIONS = [
    ("001", "initial_tables"),
    ("002", "translation_tasks"),
    ("003", "glossary"),
    ("004", "session_log"),
    ("005", "source_status"),
    ("006", "rename_columns"),
    ("007", "translation_issues"),
]


def init_database(force: bool = False) -> None:
    """Initialize database from schema.sql.

    Creates a fresh database with all tables defined in schema.sql.

    Args:
        force: If True, delete existing database and recreate.
    """
    if not SCHEMA_FILE.exists():
        raise FileNotFoundError(f"Schema file not found: {SCHEMA_FILE}")

    if DB_FILE.exists():
        if force:
            DB_FILE.unlink()
            print(f"Removed existing database: {DB_FILE}")
        else:
            print(f"Database already exists: {DB_FILE}")
            print("Use --force to recreate.")
            return

    # Ensure db directory exists
    DB_DIR.mkdir(parents=True, exist_ok=True)

    schema_sql = SCHEMA_FILE.read_text(encoding="utf-8")

    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.executescript(schema_sql)
            conn.commit()
        except sqlite3.Error as e:
            raise RuntimeError(f"SQL error during schema creation: {e}") from e

    print(f"Created database: {DB_FILE}")


def migrate_schema() -> None:
    """Apply schema updates to existing database.

    Runs schema.sql which uses CREATE TABLE IF NOT EXISTS,
    so it safely adds new tables without affecting existing ones.
    Tracks applied migrations in schema_migrations table.
    """
    if not SCHEMA_FILE.exists():
        raise FileNotFoundError(f"Schema file not found: {SCHEMA_FILE}")

    if not DB_FILE.exists():
        print(f"Database does not exist: {DB_FILE}")
        print("Use 'python store.py init' to create it first.")
        return

    schema = SCHEMA_FILE.read_text(encoding="utf-8")

    with get_connection() as conn:
        # Apply schema (idempotent due to IF NOT EXISTS)
        conn.executescript(schema)

        # Check which versions are already recorded
        cursor = conn.cursor()
        cursor.execute("SELECT version FROM schema_migrations")
        applied = {row[0] for row in cursor.fetchall()}

        # Record any missing versions
        new_versions = []
        for version, name in SCHEMA_VERSIONS:
            if version not in applied:
                cursor.execute(
                    "INSERT INTO schema_migrations (version, name) VALUES (?, ?)",
                    (version, name),
                )
                new_versions.append(f"{version}_{name}")

        conn.commit()

    print(f"Schema applied to: {DB_FILE}")
    if new_versions:
        print(f"New migrations recorded: {', '.join(new_versions)}")
    else:
        print("Schema is up to date.")
