"""``db`` command group.

Database management for translation auditing and queries. Ported from the
legacy ``locales/scripts/store.py``.

The connection + schema lifecycle (``init``/``migrate``) lives in
:mod:`i18n.db`; this module delegates to those and ports the remaining
query/export/import logic. Path and table constants come from
:mod:`i18n.config`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any, Optional

from ..config import COMMITTABLE_TABLES, DB_DIR, DB_FILE
from ..db import get_connection, init_database, migrate_schema


def register(subparsers) -> None:
    g = subparsers.add_parser(
        "db",
        help="Database management for translation auditing",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python store.py init                    # Create database from schema
    python store.py init --force            # Recreate database
    python store.py migrate                 # Apply schema updates
    python store.py query "SELECT * FROM glossary"
    python store.py query --json "SELECT * FROM session_log"
    python store.py export                  # Export all committable tables
    python store.py export glossary         # Export specific table
    python store.py import                  # Import all SQL files
    python store.py import glossary.sql     # Import specific file
        """,
    )
    gsub = g.add_subparsers(dest="cmd", required=True)

    # init subcommand
    init_parser = gsub.add_parser(
        "init",
        help="Create database from schema.sql",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    init_parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Delete existing database and recreate",
    )
    init_parser.set_defaults(func=_init)

    # migrate subcommand
    migrate_parser = gsub.add_parser(
        "migrate",
        help="Apply schema updates to existing database",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    migrate_parser.set_defaults(func=_migrate)

    # query subcommand
    query_parser = gsub.add_parser(
        "query",
        help="Run a SQL query",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    query_parser.add_argument("sql", help="SQL query to execute")
    query_parser.add_argument(
        "--json", "-j", action="store_true", help="Output results as JSON"
    )
    query_parser.set_defaults(func=_query)

    # export subcommand
    export_parser = gsub.add_parser(
        "export",
        help="Export committable tables to SQL files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    export_parser.add_argument(
        "table",
        nargs="?",
        choices=COMMITTABLE_TABLES,
        help=f"Table to export (default: all of {', '.join(COMMITTABLE_TABLES)})",
    )
    export_parser.set_defaults(func=_export)

    # import subcommand
    import_parser = gsub.add_parser(
        "import",
        help="Import SQL files into database",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    import_parser.add_argument(
        "file",
        nargs="?",
        help="SQL file to import (default: all committable table files)",
    )
    import_parser.add_argument(
        "--no-verify",
        action="store_true",
        help="Skip checksum verification",
    )
    import_parser.set_defaults(func=_import)


# --- handlers -------------------------------------------------------------


def _init(args) -> int:
    try:
        init_database(force=args.force)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


def _migrate(args) -> int:
    try:
        migrate_schema()
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


def _query(args) -> int:
    try:
        query(args.sql, output_json=args.json)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


def _export(args) -> int:
    try:
        export_tables(table=args.table)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


def _import(args) -> int:
    try:
        import_tables(file_path=args.file, verify=not args.no_verify)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


# --- ported logic ---------------------------------------------------------


def _load_checksums() -> dict[str, str]:
    """Load checksums from checksums.sha256 file.

    Returns:
        Dictionary mapping filename to expected SHA256 hash.
        Empty dict if checksums file doesn't exist.
    """
    checksum_file = DB_DIR / "checksums.sha256"
    checksums: dict[str, str] = {}

    if not checksum_file.exists():
        return checksums

    for line in checksum_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        # Format: "hash  filename" (two spaces, standard sha256sum format)
        parts = line.split("  ", 1)
        if len(parts) == 2:
            hash_hex, filename = parts
            checksums[filename] = hash_hex

    return checksums


def query(
    sql: str,
    params: Optional[tuple] = None,
    output_json: bool = False,
) -> list[dict[str, Any]]:
    """Run a SQL query and return results.

    Args:
        sql: SQL query string.
        params: Optional tuple of query parameters.
        output_json: If True, output JSON format.

    Returns:
        List of row dictionaries.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python store.py init' to create it."
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


def export_tables(table: Optional[str] = None) -> None:
    """Export committable tables to SQL files.

    Exports data as INSERT statements that can be committed to git.
    Files are written to locales/db/{table}.sql.

    Args:
        table: Specific table to export, or None for all committable tables.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python store.py init' to create it."
        )

    tables_to_export = [table] if table else COMMITTABLE_TABLES

    for tbl in tables_to_export:
        if tbl not in COMMITTABLE_TABLES:
            print(f"Warning: '{tbl}' is not a committable table. Skipping.")
            continue

        output_file = DB_DIR / f"{tbl}.sql"

        with get_connection() as conn:
            cursor = conn.cursor()

            # Get row count
            cursor.execute(f"SELECT COUNT(*) FROM {tbl}")  # noqa: S608
            count = cursor.fetchone()[0]

            if count == 0:
                print(f"{tbl}: empty (skipping)")
                continue

            # Get column names
            cursor.execute(f"PRAGMA table_info({tbl})")  # noqa: S608
            columns = [row[1] for row in cursor.fetchall()]

            # Build INSERT statements (ORDER BY id for stable diffs)
            cursor.execute(f"SELECT * FROM {tbl} ORDER BY id")  # noqa: S608
            rows = cursor.fetchall()

            lines = [
                f"-- Exported from {tbl} table",
                f"-- {count} rows",
                f"-- Generated: {__import__('datetime').datetime.now().isoformat()}",
                "",
                f"DELETE FROM {tbl};",
                "",
            ]

            for row in rows:
                values = []
                for val in row:
                    if val is None:
                        values.append("NULL")
                    elif isinstance(val, (int, float)):
                        values.append(str(val))
                    else:
                        # Escape single quotes
                        escaped = str(val).replace("'", "''")
                        values.append(f"'{escaped}'")

                cols_str = ", ".join(columns)
                vals_str = ", ".join(values)
                lines.append(
                    f"INSERT INTO {tbl} ({cols_str}) VALUES ({vals_str});"
                )

            output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"{tbl}: exported {count} rows to {output_file.name}")

    # Generate checksums for exported files
    _generate_checksums()


def _generate_checksums() -> None:
    """Generate checksums.sha256 for all committable table SQL files."""
    checksum_file = DB_DIR / "checksums.sha256"
    lines = []

    for tbl in COMMITTABLE_TABLES:
        sql_file = DB_DIR / f"{tbl}.sql"
        if sql_file.exists():
            content = sql_file.read_bytes()
            hash_hex = hashlib.sha256(content).hexdigest()
            lines.append(f"{hash_hex}  {tbl}.sql")

    if lines:
        checksum_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("checksums.sha256: updated")


def import_tables(file_path: Optional[str] = None, verify: bool = True) -> None:
    """Import SQL files into database.

    Imports data from SQL files in locales/db/.

    Args:
        file_path: Specific file to import, or None for all committable table files.
        verify: If True, verify checksums before importing.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"Database not found: {DB_FILE}\n"
            "Run 'python store.py init' to create it."
        )

    if file_path:
        files_to_import = [Path(file_path)]
    else:
        files_to_import = [
            DB_DIR / f"{tbl}.sql"
            for tbl in COMMITTABLE_TABLES
            if (DB_DIR / f"{tbl}.sql").exists()
        ]

    if not files_to_import:
        print("No SQL files found to import.")
        return

    # Load checksums if verification enabled
    checksums = _load_checksums() if verify else {}

    with get_connection() as conn:
        for sql_file in files_to_import:
            if not sql_file.exists():
                print(f"Warning: {sql_file} not found. Skipping.")
                continue

            content = sql_file.read_bytes()

            # Verify checksum if available
            if verify and checksums:
                expected = checksums.get(sql_file.name)
                if expected:
                    actual = hashlib.sha256(content).hexdigest()
                    if actual != expected:
                        print(
                            f"Warning: Checksum mismatch for {sql_file.name}, "
                            "skipping import",
                            file=sys.stderr,
                        )
                        continue

            sql_content = content.decode("utf-8")

            try:
                conn.executescript(sql_content)
                conn.commit()

                # Count rows in affected table
                table_name = sql_file.stem
                if table_name in COMMITTABLE_TABLES:
                    cursor = conn.cursor()
                    cursor.execute(f"SELECT COUNT(*) FROM {table_name}")  # noqa: S608
                    count = cursor.fetchone()[0]
                    print(
                        f"{sql_file.name}: imported ({count} rows in {table_name})"
                    )
                else:
                    print(f"{sql_file.name}: imported")

            except sqlite3.Error as e:
                print(f"Error importing {sql_file.name}: {e}", file=sys.stderr)


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
