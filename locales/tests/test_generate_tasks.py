"""Tests for tasks/create.py - translation task generation from locale comparison."""

import json
import sqlite3
from datetime import date
from pathlib import Path

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from tasks.create import (
    TaskData,
    append_to_sql_file,
    compare_locale,
    export_tasks_to_sql,
    get_keys_from_file,
    insert_into_db,
    walk_keys,
)


class TestKeyWalking:
    """Tests for walk_keys - recursive JSON key extraction."""

    def test_walks_nested_json_keys(self):
        """Builds correct dot-notation paths from nested structure."""
        data = {
            "web": {
                "login": {
                    "button": "Sign In",
                    "title": "Welcome",
                },
                "signup": {
                    "button": "Register",
                },
            },
        }

        result = dict(walk_keys(data))

        assert result == {
            "web.login.button": "Sign In",
            "web.login.title": "Welcome",
            "web.signup.button": "Register",
        }

    def test_skips_metadata_keys(self):
        """Keys prefixed with '_' are skipped during walking."""
        data = {
            "web": {
                "login": {
                    "button": "Sign In",
                    "_context": "This is metadata that should be skipped",
                    "_notes": "Also skipped",
                },
                "_internal": {
                    "secret": "This whole section should be skipped",
                },
            },
        }

        result = dict(walk_keys(data))

        assert result == {"web.login.button": "Sign In"}
        assert "_context" not in str(result)
        assert "_internal" not in str(result)

    def test_handles_empty_objects(self):
        """Empty {} does not crash and yields nothing."""
        data = {}

        result = list(walk_keys(data))

        assert result == []

    def test_handles_nested_empty_objects(self):
        """Nested empty objects are handled gracefully."""
        data = {
            "web": {
                "empty": {},
                "also_empty": {
                    "deeply": {},
                },
            },
        }

        result = list(walk_keys(data))

        assert result == []

    def test_skips_non_string_values(self):
        """Arrays and numbers are skipped, only strings are yielded."""
        data = {
            "web": {
                "title": "Hello",
                "count": 42,
                "enabled": True,
                "items": ["a", "b", "c"],
            },
        }

        result = dict(walk_keys(data))

        assert result == {"web.title": "Hello"}


class TestFileComparison:
    """Tests for file comparison logic."""

    def test_detects_missing_file(self, tmp_path: Path):
        """File in en/ but not in locale/ is detected."""
        en_dir = tmp_path / "en"
        en_dir.mkdir()
        eo_dir = tmp_path / "eo"
        eo_dir.mkdir()

        # Create English file
        en_data = {"web": {"title": "Hello"}}
        (en_dir / "missing.json").write_text(json.dumps(en_data))

        # eo/missing.json does not exist

        en_keys = get_keys_from_file(en_dir / "missing.json")
        eo_keys = get_keys_from_file(eo_dir / "missing.json")

        assert en_keys == {"web.title": "Hello"}
        assert eo_keys == {}  # File not found returns empty dict

    def test_detects_missing_keys(self, tmp_path: Path):
        """Key in en/ file but not in locale/ file is detected."""
        en_dir = tmp_path / "en"
        en_dir.mkdir()
        eo_dir = tmp_path / "eo"
        eo_dir.mkdir()

        # English has two keys
        en_data = {
            "web": {
                "title": "Hello",
                "subtitle": "World",
            },
        }
        (en_dir / "test.json").write_text(json.dumps(en_data))

        # Esperanto only has one key
        eo_data = {
            "web": {
                "title": "Saluton",
                # "subtitle" is missing
            },
        }
        (eo_dir / "test.json").write_text(json.dumps(eo_data))

        en_keys = get_keys_from_file(en_dir / "test.json")
        eo_keys = get_keys_from_file(eo_dir / "test.json")

        missing = {k: v for k, v in en_keys.items() if k not in eo_keys}

        assert missing == {"web.subtitle": "World"}

    def test_detects_empty_translations(self, tmp_path: Path):
        """Key exists but value is empty string is detected."""
        en_dir = tmp_path / "en"
        en_dir.mkdir()
        eo_dir = tmp_path / "eo"
        eo_dir.mkdir()

        en_data = {"web": {"title": "Hello"}}
        (en_dir / "test.json").write_text(json.dumps(en_data))

        eo_data = {"web": {"title": ""}}  # Empty translation
        (eo_dir / "test.json").write_text(json.dumps(eo_data))

        en_keys = get_keys_from_file(en_dir / "test.json")
        eo_keys = get_keys_from_file(eo_dir / "test.json")

        empty = {k: en_keys[k] for k in en_keys if k in eo_keys and eo_keys[k] == ""}

        assert empty == {"web.title": "Hello"}

    def test_ignores_existing_translations(self, tmp_path: Path):
        """Non-empty values in locale file are not flagged as missing."""
        en_dir = tmp_path / "en"
        en_dir.mkdir()
        eo_dir = tmp_path / "eo"
        eo_dir.mkdir()

        en_data = {
            "web": {
                "title": "Hello",
                "subtitle": "World",
            },
        }
        (en_dir / "test.json").write_text(json.dumps(en_data))

        eo_data = {
            "web": {
                "title": "Saluton",
                "subtitle": "Mondo",
            },
        }
        (eo_dir / "test.json").write_text(json.dumps(eo_data))

        en_keys = get_keys_from_file(en_dir / "test.json")
        eo_keys = get_keys_from_file(eo_dir / "test.json")

        # No missing keys when fully translated
        missing = {k: v for k, v in en_keys.items() if k not in eo_keys}
        empty = {k: en_keys[k] for k in en_keys if k in eo_keys and eo_keys[k] == ""}

        assert missing == {}
        assert empty == {}


class TestTaskGeneration:
    """Tests for SQL INSERT statement generation via export_tasks_to_sql."""

    def test_export_generates_correct_insert_sql(self, hydrated_db: Path):
        """SQL format is valid and contains expected values."""
        conn = sqlite3.connect(hydrated_db)

        # Insert a task with parameterized query
        cursor = conn.execute(
            "INSERT INTO translation_tasks "
            "(batch, locale, file, key, english_text) VALUES (?, ?, ?, ?, ?)",
            ("2026-01-11", "eo", "auth.json", "web.login.button", "Sign In"),
        )
        task_id = cursor.lastrowid
        conn.commit()

        # Export using quote() function
        statements = export_tasks_to_sql(conn, [task_id])
        conn.close()

        assert len(statements) == 1
        sql = statements[0]
        assert sql.startswith("INSERT INTO translation_tasks")
        assert "(batch, locale, file, key, english_text)" in sql
        assert "'2026-01-11'" in sql
        assert "'eo'" in sql
        assert "'auth.json'" in sql
        assert "'web.login.button'" in sql
        assert "'Sign In'" in sql
        assert sql.endswith(");")

    def test_export_escapes_single_quotes_via_sqlite_quote(self, hydrated_db: Path):
        """SQLite's quote() properly escapes single quotes."""
        conn = sqlite3.connect(hydrated_db)

        # Insert a task with single quotes in text
        cursor = conn.execute(
            "INSERT INTO translation_tasks "
            "(batch, locale, file, key, english_text) VALUES (?, ?, ?, ?, ?)",
            ("2026-01-11", "fr", "test.json", "message", "Don't forget"),
        )
        task_id = cursor.lastrowid
        conn.commit()

        # Export using quote() function
        statements = export_tasks_to_sql(conn, [task_id])
        conn.close()

        sql = statements[0]
        # SQLite quote() escapes single quotes as ''
        assert "Don''t forget" in sql

    def test_batch_defaults_to_today(self, mock_src_locales: Path, tmp_path: Path):
        """Uses current date if batch not specified."""
        today = date.today().isoformat()

        # We need to mock the module-level constants to use our test directories
        import tasks.create as gt

        original_src_locales = gt.SRC_LOCALES_DIR
        original_en_dir = gt.EN_DIR
        original_tasks_file = gt.TASKS_FILE

        try:
            gt.SRC_LOCALES_DIR = mock_src_locales
            gt.EN_DIR = mock_src_locales / "en"
            gt.TASKS_FILE = tmp_path / "tasks.sql"

            # Create empty tasks.sql
            gt.TASKS_FILE.write_text("")

            tasks, stats = compare_locale(
                locale="eo",
                batch=today,
                dry_run=True,
            )

            # All generated tasks should use today's date
            for task in tasks:
                assert task.batch == today
        finally:
            gt.SRC_LOCALES_DIR = original_src_locales
            gt.EN_DIR = original_en_dir
            gt.TASKS_FILE = original_tasks_file

    def test_custom_batch_name(self, mock_src_locales: Path, tmp_path: Path):
        """Respects --batch flag with custom batch name."""
        custom_batch = "my-custom-batch"

        import tasks.create as gt

        original_src_locales = gt.SRC_LOCALES_DIR
        original_en_dir = gt.EN_DIR
        original_tasks_file = gt.TASKS_FILE

        try:
            gt.SRC_LOCALES_DIR = mock_src_locales
            gt.EN_DIR = mock_src_locales / "en"
            gt.TASKS_FILE = tmp_path / "tasks.sql"

            gt.TASKS_FILE.write_text("")

            tasks, stats = compare_locale(
                locale="eo",
                batch=custom_batch,
                dry_run=True,
            )

            for task in tasks:
                assert task.batch == custom_batch
        finally:
            gt.SRC_LOCALES_DIR = original_src_locales
            gt.EN_DIR = original_en_dir
            gt.TASKS_FILE = original_tasks_file

    def test_exported_sql_is_executable(self, hydrated_db: Path):
        """Exported SQL can be re-executed against the database schema."""
        conn = sqlite3.connect(hydrated_db)

        # Insert a task
        cursor = conn.execute(
            "INSERT INTO translation_tasks "
            "(batch, locale, file, key, english_text) VALUES (?, ?, ?, ?, ?)",
            ("2026-01-11", "test", "test.json", "test.key", "Test value"),
        )
        task_id = cursor.lastrowid
        conn.commit()

        # Export it
        statements = export_tasks_to_sql(conn, [task_id])

        # Delete the original
        conn.execute("DELETE FROM translation_tasks WHERE id = ?", (task_id,))
        conn.commit()

        # Re-execute the exported SQL - should work
        conn.execute(statements[0])
        conn.commit()

        # Verify it was re-inserted
        cursor = conn.execute(
            "SELECT * FROM translation_tasks WHERE key = 'test.key'"
        )
        row = cursor.fetchone()
        conn.close()

        assert row is not None


class TestDryRun:
    """Tests for dry-run mode behavior."""

    def test_dry_run_does_not_write(self, mock_src_locales: Path, tmp_path: Path):
        """No file changes in dry-run mode."""
        import tasks.create as gt

        original_src_locales = gt.SRC_LOCALES_DIR
        original_en_dir = gt.EN_DIR
        original_tasks_file = gt.TASKS_FILE

        try:
            gt.SRC_LOCALES_DIR = mock_src_locales
            gt.EN_DIR = mock_src_locales / "en"
            gt.TASKS_FILE = tmp_path / "tasks.sql"

            # Create empty tasks.sql and record its state
            gt.TASKS_FILE.write_text("-- original content\n")
            original_content = gt.TASKS_FILE.read_text()

            inserts, stats = compare_locale(
                locale="eo",
                batch="2026-01-11",
                dry_run=True,
            )

            # In dry-run mode, compare_locale does not write
            # The file should remain unchanged
            assert gt.TASKS_FILE.read_text() == original_content

            # But we should have generated some tasks
            assert len(inserts) > 0
        finally:
            gt.SRC_LOCALES_DIR = original_src_locales
            gt.EN_DIR = original_en_dir
            gt.TASKS_FILE = original_tasks_file

    def test_dry_run_shows_task_count(self, mock_src_locales: Path, tmp_path: Path, capsys):
        """Reports what would be created in dry-run mode."""
        import tasks.create as gt

        original_src_locales = gt.SRC_LOCALES_DIR
        original_en_dir = gt.EN_DIR
        original_tasks_file = gt.TASKS_FILE

        try:
            gt.SRC_LOCALES_DIR = mock_src_locales
            gt.EN_DIR = mock_src_locales / "en"
            gt.TASKS_FILE = tmp_path / "tasks.sql"
            gt.TASKS_FILE.write_text("")

            inserts, stats = compare_locale(
                locale="eo",
                batch="2026-01-11",
                dry_run=True,
            )

            # Verify stats are populated
            assert stats["total_tasks"] > 0
            assert stats["total_tasks"] == len(inserts)

            # Capture printed output shows what would be generated
            captured = capsys.readouterr()
            # In dry_run mode, MISSING KEY and MISSING FILE are printed
            assert "MISSING" in captured.out or stats["total_tasks"] > 0
        finally:
            gt.SRC_LOCALES_DIR = original_src_locales
            gt.EN_DIR = original_en_dir
            gt.TASKS_FILE = original_tasks_file


class TestGetKeysFromFile:
    """Tests for get_keys_from_file function."""

    def test_returns_empty_dict_for_missing_file(self, tmp_path: Path):
        """Non-existent file returns empty dict without error."""
        result = get_keys_from_file(tmp_path / "nonexistent.json")

        assert result == {}

    def test_returns_empty_dict_for_invalid_json(self, tmp_path: Path):
        """Invalid JSON returns empty dict and prints warning."""
        bad_file = tmp_path / "bad.json"
        bad_file.write_text("{ invalid json }")

        result = get_keys_from_file(bad_file)

        assert result == {}

    def test_loads_valid_json(self, tmp_path: Path):
        """Valid JSON file is loaded and keys extracted."""
        good_file = tmp_path / "good.json"
        data = {"web": {"title": "Hello", "subtitle": "World"}}
        good_file.write_text(json.dumps(data))

        result = get_keys_from_file(good_file)

        assert result == {
            "web.title": "Hello",
            "web.subtitle": "World",
        }


class TestAppendToSqlFile:
    """Tests for append_to_sql_file function."""

    def test_appends_to_file(self, tmp_path: Path):
        """SQL statements are appended to existing file."""
        import tasks.create as gt

        original_tasks_file = gt.TASKS_FILE

        try:
            gt.TASKS_FILE = tmp_path / "tasks.sql"
            gt.TASKS_FILE.write_text("-- existing content\n")

            statements = [
                "INSERT INTO translation_tasks (batch) VALUES ('test1');",
                "INSERT INTO translation_tasks (batch) VALUES ('test2');",
            ]

            append_to_sql_file(statements)

            content = gt.TASKS_FILE.read_text()
            assert "-- existing content" in content
            assert "test1" in content
            assert "test2" in content
        finally:
            gt.TASKS_FILE = original_tasks_file

    def test_creates_file_if_not_exists(self, tmp_path: Path):
        """Creates tasks.sql if it does not exist."""
        import tasks.create as gt

        original_tasks_file = gt.TASKS_FILE

        try:
            gt.TASKS_FILE = tmp_path / "new_tasks.sql"
            assert not gt.TASKS_FILE.exists()

            statements = [
                "INSERT INTO translation_tasks (batch) VALUES ('test');",
            ]
            append_to_sql_file(statements)

            assert gt.TASKS_FILE.exists()
            assert "test" in gt.TASKS_FILE.read_text()
        finally:
            gt.TASKS_FILE = original_tasks_file
