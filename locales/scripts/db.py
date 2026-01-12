#!/usr/bin/env python3
"""
Database management for translation tasks.

Usage:
    python db.py hydrate [--force]
    python db.py dump
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
DB_DIR = SCRIPT_DIR.parent / "db"
SCHEMA_FILE = DB_DIR / "schema.sql"
TASKS_FILE = DB_DIR / "tasks.sql"
DB_FILE = DB_DIR / "tasks.db"


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


def hydrate(force: bool = False) -> None:
    """Load schema.sql and tasks.sql into tasks.db.

    Args:
        force: If True, delete existing database and recreate.
               If False, skip if database already exists.
    """
    if not SCHEMA_FILE.exists():
        raise FileNotFoundError(f"Schema file not found: {SCHEMA_FILE}")

    if not TASKS_FILE.exists():
        raise FileNotFoundError(f"Tasks file not found: {TASKS_FILE}")

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
    tasks_sql = TASKS_FILE.read_text()

    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.executescript(schema_sql)
            cursor.executescript(tasks_sql)
            conn.commit()
            print(f"Created database: {DB_FILE}")
            # Report row count
            cursor.execute("SELECT COUNT(*) FROM translation_tasks")
            count = cursor.fetchone()[0]
            print(f"Loaded {count} translation tasks.")
        except sqlite3.Error as e:
            raise RuntimeError(f"SQL error during hydrate: {e}") from e


def dump() -> None:
    """Export database state back to tasks.sql.

    Generates INSERT statements for all rows in translation_tasks.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(f"Database not found: {DB_FILE}")

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT batch, locale, file, key, english_text, translation,
                   status, notes, created_at, completed_at
            FROM translation_tasks
            ORDER BY id
        """)
        rows = cursor.fetchall()

    lines = [
        "-- Translation tasks",
        "-- Append INSERT statements below. This file is git-tracked.",
        "-- Format: INSERT INTO translation_tasks "
        "(batch, locale, file, key, english_text) VALUES (...);",
        "",
    ]

    for row in rows:
        # Build INSERT with all non-null fields
        columns = []
        values = []

        field_names = [
            "batch", "locale", "file", "key", "english_text",
            "translation", "status", "notes", "created_at", "completed_at"
        ]

        for field in field_names:
            value = row[field]
            if value is not None:
                columns.append(field)
                # Escape single quotes in SQL
                escaped = str(value).replace("'", "''")
                values.append(f"'{escaped}'")

        if columns:
            cols_str = ", ".join(columns)
            vals_str = ", ".join(values)
            lines.append(
                f"INSERT INTO translation_tasks ({cols_str}) VALUES ({vals_str});"
            )

    TASKS_FILE.write_text("\n".join(lines) + "\n")
    print(f"Dumped {len(rows)} rows to {TASKS_FILE}")


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
            print("Database not found, hydrating...", file=sys.stderr)
            hydrate(force=False)
        else:
            raise FileNotFoundError(
                f"Database not found: {DB_FILE}\n"
                "Run 'python db.py hydrate' or use --hydrate flag."
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
        description="Database management for translation tasks.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python db.py hydrate              # Create database from SQL files
    python db.py hydrate --force      # Recreate database
    python db.py dump                 # Export to tasks.sql
    python db.py query "SELECT * FROM translation_tasks"
    python db.py query --hydrate "SELECT * FROM translation_tasks"
    python db.py query --json "SELECT * FROM translation_tasks WHERE status='pending'"
        """,
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # hydrate subcommand
    hydrate_parser = subparsers.add_parser(
        "hydrate", help="Load schema.sql and tasks.sql into tasks.db"
    )
    hydrate_parser.add_argument(
        "--force", "-f", action="store_true",
        help="Delete existing database and recreate"
    )

    # dump subcommand
    subparsers.add_parser(
        "dump", help="Export database state to tasks.sql"
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
        help="Hydrate database if it doesn't exist"
    )
    query_parser.add_argument(
        "--json", "-j", action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    try:
        if args.command == "hydrate":
            hydrate(force=args.force)
        elif args.command == "dump":
            dump()
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
