"""Tests for db.py database operations."""

import sqlite3
from pathlib import Path

import pytest


class TestHydrate:
    """Tests for database hydration (schema creation)."""

    def test_creates_database_file(self, tmp_db_path: Path, schema_sql: str):
        """Hydrating creates the database file if it doesn't exist."""
        assert not tmp_db_path.exists()

        conn = sqlite3.connect(tmp_db_path)
        conn.executescript(schema_sql)
        conn.close()

        assert tmp_db_path.exists()

    def test_executes_schema_creates_table(self, tmp_db_path: Path, schema_sql: str):
        """Schema execution creates the translation_tasks table."""
        conn = sqlite3.connect(tmp_db_path)
        conn.executescript(schema_sql)

        cursor = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='translation_tasks'"
        )
        result = cursor.fetchone()
        conn.close()

        assert result is not None
        assert result[0] == "translation_tasks"

    def test_schema_is_idempotent(self, tmp_db_path: Path, schema_sql: str):
        """Running schema multiple times does not raise errors."""
        conn = sqlite3.connect(tmp_db_path)

        # Execute schema twice - should not raise
        conn.executescript(schema_sql)
        conn.executescript(schema_sql)

        conn.close()

    def test_creates_indexes(self, tmp_db_path: Path, schema_sql: str):
        """Schema creates the expected indexes."""
        conn = sqlite3.connect(tmp_db_path)
        conn.executescript(schema_sql)

        cursor = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'"
        )
        indexes = {row[0] for row in cursor.fetchall()}
        conn.close()

        assert "idx_locale_status" in indexes
        assert "idx_batch" in indexes

    def test_error_on_invalid_sql(self, tmp_db_path: Path):
        """Invalid SQL raises an appropriate error."""
        conn = sqlite3.connect(tmp_db_path)

        with pytest.raises(sqlite3.OperationalError):
            conn.executescript("CREATE TABLE incomplete (")

        conn.close()


class TestDump:
    """Tests for database dump operations."""

    def test_dump_produces_valid_sql(self, hydrated_db_with_data: Path):
        """Dumping a database produces valid SQL that can be re-executed."""
        conn = sqlite3.connect(hydrated_db_with_data)

        # Get the dump
        dump_lines = list(conn.iterdump())
        dump_sql = "\n".join(dump_lines)
        conn.close()

        # Verify it's valid SQL by executing on a new database
        new_conn = sqlite3.connect(":memory:")
        new_conn.executescript(dump_sql)

        cursor = new_conn.execute("SELECT COUNT(*) FROM translation_tasks")
        count = cursor.fetchone()[0]
        new_conn.close()

        assert count > 0

    def test_roundtrip_preserves_data(self, hydrated_db_with_data: Path):
        """Dump and restore preserves all data."""
        conn = sqlite3.connect(hydrated_db_with_data)
        conn.row_factory = sqlite3.Row

        # Get original data
        original_rows = conn.execute(
            "SELECT * FROM translation_tasks ORDER BY id"
        ).fetchall()
        original_data = [dict(row) for row in original_rows]

        # Dump
        dump_sql = "\n".join(conn.iterdump())
        conn.close()

        # Restore to new database
        new_conn = sqlite3.connect(":memory:")
        new_conn.row_factory = sqlite3.Row
        new_conn.executescript(dump_sql)

        # Get restored data
        restored_rows = new_conn.execute(
            "SELECT * FROM translation_tasks ORDER BY id"
        ).fetchall()
        restored_data = [dict(row) for row in restored_rows]
        new_conn.close()

        assert original_data == restored_data


class TestQuery:
    """Tests for database query operations."""

    def test_select_returns_rows(self, db_connection_with_data):
        """SELECT query returns expected rows."""
        cursor = db_connection_with_data.execute(
            "SELECT * FROM translation_tasks WHERE status = ?",
            ("pending",)
        )
        rows = cursor.fetchall()

        assert len(rows) == 2
        assert all(row["status"] == "pending" for row in rows)

    def test_parameterized_query(self, db_connection_with_data):
        """Parameterized queries work correctly."""
        cursor = db_connection_with_data.execute(
            "SELECT * FROM translation_tasks WHERE locale = ? AND file = ?",
            ("de", "auth.json")
        )
        rows = cursor.fetchall()

        assert len(rows) == 2
        assert all(row["locale"] == "de" for row in rows)

    def test_empty_result_set(self, db_connection_with_data):
        """Query with no matches returns empty result."""
        cursor = db_connection_with_data.execute(
            "SELECT * FROM translation_tasks WHERE locale = ?",
            ("nonexistent",)
        )
        rows = cursor.fetchall()

        assert rows == []

    def test_aggregate_query(self, db_connection_with_data):
        """Aggregate queries work correctly."""
        cursor = db_connection_with_data.execute(
            "SELECT status, COUNT(*) as count FROM translation_tasks GROUP BY status"
        )
        rows = cursor.fetchall()
        results = {row["status"]: row["count"] for row in rows}

        assert results["pending"] == 2
        assert results["completed"] == 2
        assert results["error"] == 1


class TestSchema:
    """Tests for schema constraints and defaults."""

    def test_unique_constraint_on_locale_file_key(self, db_connection):
        """UNIQUE constraint prevents duplicate locale/file/key combinations."""
        db_connection.execute(
            """INSERT INTO translation_tasks (batch, locale, file, key, english_text)
               VALUES ('2026-01-11', 'de', 'auth.json', 'unique.key', 'Test')"""
        )

        with pytest.raises(sqlite3.IntegrityError):
            db_connection.execute(
                """INSERT INTO translation_tasks (batch, locale, file, key, english_text)
                   VALUES ('2026-01-11', 'de', 'auth.json', 'unique.key', 'Duplicate')"""
            )

    def test_default_status_is_pending(self, db_connection):
        """Status defaults to 'pending' when not specified."""
        db_connection.execute(
            """INSERT INTO translation_tasks (batch, locale, file, key, english_text)
               VALUES ('2026-01-11', 'de', 'test.json', 'test.key', 'Test')"""
        )

        cursor = db_connection.execute(
            "SELECT status FROM translation_tasks WHERE key = 'test.key'"
        )
        row = cursor.fetchone()

        assert row["status"] == "pending"

    def test_created_at_has_default(self, db_connection):
        """created_at is automatically set on insert."""
        db_connection.execute(
            """INSERT INTO translation_tasks (batch, locale, file, key, english_text)
               VALUES ('2026-01-11', 'de', 'test.json', 'test.key2', 'Test')"""
        )

        cursor = db_connection.execute(
            "SELECT created_at FROM translation_tasks WHERE key = 'test.key2'"
        )
        row = cursor.fetchone()

        assert row["created_at"] is not None

    def test_required_columns_not_null(self, db_connection):
        """Required columns cannot be NULL."""
        required_columns = ["batch", "locale", "file", "key", "english_text"]

        for column in required_columns:
            columns = [c for c in required_columns if c != column]
            values = ["'val'" for _ in columns]

            sql = f"""INSERT INTO translation_tasks ({', '.join(columns)})
                      VALUES ({', '.join(values)})"""

            with pytest.raises(sqlite3.IntegrityError):
                db_connection.execute(sql)

            # Rollback to allow next iteration
            db_connection.rollback()

    def test_optional_columns_can_be_null(self, db_connection):
        """Optional columns accept NULL values."""
        db_connection.execute(
            """INSERT INTO translation_tasks
               (batch, locale, file, key, english_text, translation, notes, completed_at)
               VALUES ('2026-01-11', 'de', 'test.json', 'nullable.test', 'Test', NULL, NULL, NULL)"""
        )

        cursor = db_connection.execute(
            "SELECT translation, notes, completed_at FROM translation_tasks WHERE key = 'nullable.test'"
        )
        row = cursor.fetchone()

        assert row["translation"] is None
        assert row["notes"] is None
        assert row["completed_at"] is None

    def test_autoincrement_id(self, db_connection):
        """ID column auto-increments."""
        db_connection.execute(
            """INSERT INTO translation_tasks (batch, locale, file, key, english_text)
               VALUES ('2026-01-11', 'de', 'test.json', 'first.key', 'First')"""
        )
        db_connection.execute(
            """INSERT INTO translation_tasks (batch, locale, file, key, english_text)
               VALUES ('2026-01-11', 'de', 'test.json', 'second.key', 'Second')"""
        )

        cursor = db_connection.execute(
            "SELECT id FROM translation_tasks WHERE key IN ('first.key', 'second.key') ORDER BY id"
        )
        rows = cursor.fetchall()

        assert rows[1]["id"] == rows[0]["id"] + 1
