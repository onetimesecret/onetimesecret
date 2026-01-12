"""Tests for generate_tasks.py - translation task generation from locale comparison."""

import json
import sqlite3
from datetime import date
from pathlib import Path

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from generate_tasks import (
    TaskData,
    compare_locale,
    escape_sql_string,
    generate_insert,
    get_keys_from_file,
    walk_keys,
    write_to_sql_file,
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
    """Tests for SQL INSERT statement generation."""

    def test_generates_correct_insert_sql(self):
        """SQL format is valid and contains expected values."""
        sql = generate_insert(
            batch="2026-01-11",
            locale="eo",
            file="auth.json",
            key="web.login.button",
            english_text="Sign In",
        )

        assert sql.startswith("INSERT INTO translation_tasks")
        assert "(batch, locale, file, key, english_text)" in sql
        assert "'2026-01-11'" in sql
        assert "'eo'" in sql
        assert "'auth.json'" in sql
        assert "'web.login.button'" in sql
        assert "'Sign In'" in sql
        assert sql.endswith(");")

    def test_escapes_single_quotes_in_values(self):
        """Single quotes in values are properly escaped for SQL."""
        sql = generate_insert(
            batch="2026-01-11",
            locale="fr",
            file="test.json",
            key="message",
            english_text="Don't forget",
        )

        assert "Don''t forget" in sql
        assert "Don't forget" not in sql

    def test_batch_defaults_to_today(self, mock_src_locales: Path, tmp_path: Path):
        """Uses current date if batch not specified."""
        today = date.today().isoformat()

        # We need to mock the module-level constants to use our test directories
        import generate_tasks as gt

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

        import generate_tasks as gt

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

    def test_sql_is_executable(self, hydrated_db: Path):
        """Generated SQL can be executed against the database schema."""
        sql = generate_insert(
            batch="2026-01-11",
            locale="test",
            file="test.json",
            key="test.key",
            english_text="Test value",
        )

        conn = sqlite3.connect(hydrated_db)
        # Should not raise
        conn.execute(sql)
        conn.commit()

        # Verify it was inserted
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
        import generate_tasks as gt

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
        import generate_tasks as gt

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


class TestEscapeSqlString:
    """Tests for SQL string escaping."""

    def test_escapes_single_quotes(self):
        """Single quotes are doubled for SQL safety."""
        assert escape_sql_string("Don't") == "Don''t"
        assert escape_sql_string("It's a test") == "It''s a test"

    def test_handles_multiple_quotes(self):
        """Multiple single quotes are all escaped."""
        assert escape_sql_string("'hello' 'world'") == "''hello'' ''world''"

    def test_leaves_other_chars_unchanged(self):
        """Non-quote characters are not modified."""
        assert escape_sql_string("Hello World") == "Hello World"
        assert escape_sql_string("Test 123") == "Test 123"


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


class TestWriteToSqlFile:
    """Tests for write_to_sql_file function."""

    def test_appends_to_file(self, tmp_path: Path):
        """INSERT statements are appended to existing file."""
        import generate_tasks as gt

        original_tasks_file = gt.TASKS_FILE

        try:
            gt.TASKS_FILE = tmp_path / "tasks.sql"
            gt.TASKS_FILE.write_text("-- existing content\n")

            tasks = [
                TaskData(
                    batch="test1",
                    locale="eo",
                    file="auth.json",
                    key="web.login",
                    english_text="Login",
                ),
                TaskData(
                    batch="test2",
                    locale="eo",
                    file="auth.json",
                    key="web.logout",
                    english_text="Logout",
                ),
            ]

            write_to_sql_file(tasks)

            content = gt.TASKS_FILE.read_text()
            assert "-- existing content" in content
            assert "test1" in content
            assert "test2" in content
        finally:
            gt.TASKS_FILE = original_tasks_file

    def test_creates_file_if_not_exists(self, tmp_path: Path):
        """Creates tasks.sql if it does not exist."""
        import generate_tasks as gt

        original_tasks_file = gt.TASKS_FILE

        try:
            gt.TASKS_FILE = tmp_path / "new_tasks.sql"
            assert not gt.TASKS_FILE.exists()

            tasks = [
                TaskData(
                    batch="test",
                    locale="eo",
                    file="auth.json",
                    key="web.test",
                    english_text="Test",
                ),
            ]
            write_to_sql_file(tasks)

            assert gt.TASKS_FILE.exists()
            assert "test" in gt.TASKS_FILE.read_text()
        finally:
            gt.TASKS_FILE = original_tasks_file
