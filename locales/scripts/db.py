#!/usr/bin/env python3
"""
Database management for translation auditing and queries.

The database is ephemeral and hydrated on-demand from historical JSON files.
It exists for querying/reporting only - the source of truth is JSON.

Three-tier architecture:
- locales/translations/{locale}/*.json - Historical source of truth (flat keys)
- src/locales/{locale}/*.json - Lean app-consumable files (nested JSON)
- locales/db/tasks.db - Ephemeral, hydrated on-demand for queries

Usage:
    python db.py hydrate [--from-json] [--force]
    python db.py migrate                           # Apply schema updates
    python db.py query "SELECT ..." [--hydrate] [--json]
"""

import argparse
import json
import sqlite3
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Optional

# Path constants relative to script location
SCRIPT_DIR = Path(__file__).parent.resolve()
LOCALES_DIR = SCRIPT_DIR.parent
DB_DIR = LOCALES_DIR / "db"
SCHEMA_FILE = DB_DIR / "schema.sql"
DB_FILE = DB_DIR / "tasks.db"
TRANSLATIONS_DIR = LOCALES_DIR / "translations"


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    """Context manager for database connections.

    Abstracts connection handling for future migration to libsql.
    """
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


# Schema versions - add new entries when schema changes
SCHEMA_VERSIONS = [
    ("001", "initial_tables"),
    ("002", "level_tasks"),
    ("003", "glossary"),
    ("004", "session_log"),
]


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
        print("Use 'python db.py hydrate' to create it first.")
        return

    schema = SCHEMA_FILE.read_text(encoding="utf-8")

    with get_connection() as conn:
        # Apply schema (idempotent due to IF NOT EXISTS)
        conn.executescript(schema)

        # Check which versions are already recorded
        cursor = conn.cursor()
        cursor.execute(
            "SELECT version FROM schema_migrations"
        )
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


def hydrate_from_json(force: bool = False) -> None:
    """Hydrate database from historical JSON files.

    Creates tables from schema.sql, then walks all
    locales/translations/{locale}/*.json files to populate the database.

    Args:
        force: If True, delete existing database and recreate.
    """
    if not SCHEMA_FILE.exists():
        raise FileNotFoundError(f"Schema file not found: {SCHEMA_FILE}")

    if not TRANSLATIONS_DIR.exists():
        raise FileNotFoundError(
            f"Translations directory not found: {TRANSLATIONS_DIR}\n"
            "Run bootstrap_translations.py first to create historical JSON files."
        )

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

    schema_sql = SCHEMA_FILE.read_text()

    with get_connection() as conn:
        cursor = conn.cursor()

        # Create tables
        try:
            cursor.executescript(schema_sql)
            conn.commit()
        except sqlite3.Error as e:
            raise RuntimeError(f"SQL error during schema creation: {e}") from e

        # Walk translation directories
        inserted = 0
        locale_dirs = sorted(
            d for d in TRANSLATIONS_DIR.iterdir()
            if d.is_dir() and not d.name.startswith(".")
        )

        for locale_dir in locale_dirs:
            locale = locale_dir.name
            json_files = sorted(locale_dir.glob("*.json"))

            for json_file in json_files:
                file_name = json_file.name
                try:
                    with open(json_file, encoding="utf-8") as f:
                        data = json.load(f)
                except json.JSONDecodeError as e:
                    print(f"Warning: Invalid JSON in {json_file}: {e}",
                          file=sys.stderr)
                    continue

                for key, entry in data.items():
                    if not isinstance(entry, dict):
                        continue

                    english_text = entry.get("en", "")
                    translation = entry.get("translation")
                    skip = entry.get("skip", False)
                    note = entry.get("note")

                    # Determine status
                    if translation:
                        status = "completed"
                    elif skip:
                        status = "skipped"
                    else:
                        status = "pending"

                    try:
                        cursor.execute(
                            """
                            INSERT INTO translation_tasks
                            (batch, locale, file, key, english_text, translation,
                             status, notes)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                "hydrated",
                                locale,
                                file_name,
                                key,
                                english_text,
                                translation,
                                status,
                                note,
                            ),
                        )
                        inserted += 1
                    except sqlite3.IntegrityError:
                        # Duplicate key - skip
                        pass

            print(f"  {locale}: loaded {len(json_files)} files")

        conn.commit()
        print(f"\nCreated database: {DB_FILE}")
        print(f"Loaded {inserted} translation records from JSON files.")


def query(
    sql: str,
    params: Optional[tuple] = None,
    auto_hydrate: bool = False,
    output_json: bool = False,
) -> list[dict[str, Any]]:
    """Run a SQL query and return results.

    Args:
        sql: SQL query string.
        params: Optional tuple of query parameters.
        auto_hydrate: If True, hydrate database if it doesn't exist.
        output_json: If True, output JSON format.

    Returns:
        List of row dictionaries.
    """
    if not DB_FILE.exists():
        if auto_hydrate:
            print("Database not found, hydrating from JSON...", file=sys.stderr)
            hydrate_from_json(force=False)
        else:
            raise FileNotFoundError(
                f"Database not found: {DB_FILE}\n"
                "Run 'python db.py hydrate --from-json' or use --hydrate flag."
            )

    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            if params:
                cursor.execute(sql, params)
            else:
                cursor.execute(sql)

            # Check if this is a SELECT query
            if cursor.description is None:
                conn.commit()
                print(f"Query executed. Rows affected: {cursor.rowcount}")
                return []

            rows = cursor.fetchall()
            results = [dict(row) for row in rows]

            if output_json:
                print(json.dumps(results, indent=2, default=str))
            else:
                _print_table(results, cursor.description)

            return results

        except sqlite3.Error as e:
            raise RuntimeError(f"SQL error: {e}") from e


def _print_table(rows: list[dict], description: tuple) -> None:
    """Print results as a human-readable table."""
    if not rows:
        print("No results.")
        return

    # Get column names
    columns = [col[0] for col in description]

    # Calculate column widths
    widths = {col: len(col) for col in columns}
    for row in rows:
        for col in columns:
            val = str(row.get(col, ""))
            # Truncate long values for display
            if len(val) > 50:
                val = val[:47] + "..."
            widths[col] = max(widths[col], len(val))

    # Print header
    header = " | ".join(col.ljust(widths[col]) for col in columns)
    separator = "-+-".join("-" * widths[col] for col in columns)
    print(header)
    print(separator)

    # Print rows
    for row in rows:
        line_parts = []
        for col in columns:
            val = str(row.get(col, ""))
            if len(val) > 50:
                val = val[:47] + "..."
            line_parts.append(val.ljust(widths[col]))
        print(" | ".join(line_parts))

    print(f"\n({len(rows)} rows)")


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Database management for translation auditing.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python db.py hydrate --from-json        # Create database from JSON files
    python db.py hydrate --from-json -f     # Recreate database
    python db.py migrate                    # Apply schema updates (add new tables)
    python db.py query "SELECT * FROM translation_tasks"
    python db.py query --hydrate "SELECT * FROM translation_tasks"
    python db.py query --json "SELECT locale, status, COUNT(*) FROM translation_tasks GROUP BY locale, status"
        """,
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # hydrate subcommand
    hydrate_parser = subparsers.add_parser(
        "hydrate", help="Create database from JSON files"
    )
    hydrate_parser.add_argument(
        "--from-json", action="store_true", default=True,
        help="Hydrate from locales/translations/*.json (default, only option)"
    )
    hydrate_parser.add_argument(
        "--force", "-f", action="store_true",
        help="Delete existing database and recreate"
    )

    # migrate subcommand
    subparsers.add_parser(
        "migrate", help="Apply schema updates to existing database"
    )

    # query subcommand
    query_parser = subparsers.add_parser(
        "query", help="Run a SQL query"
    )
    query_parser.add_argument(
        "sql", help="SQL query to execute"
    )
    query_parser.add_argument(
        "--hydrate", action="store_true",
        help="Hydrate database from JSON if it doesn't exist"
    )
    query_parser.add_argument(
        "--json", "-j", action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    try:
        if args.command == "hydrate":
            hydrate_from_json(force=args.force)
        elif args.command == "migrate":
            migrate_schema()
        elif args.command == "query":
            query(
                args.sql,
                auto_hydrate=args.hydrate,
                output_json=args.json,
            )
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
