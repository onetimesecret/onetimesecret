"""Tests for shared utility functions."""

import pytest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from utils import (
    KeyPathConflictError,
    load_json_file,
    save_json_file,
    set_nested_value,
    walk_keys,
)


class TestWalkKeys:
    """Tests for walk_keys function."""

    def test_walks_flat_dict(self):
        obj = {"a": "1", "b": "2"}
        result = dict(walk_keys(obj))
        assert result == {"a": "1", "b": "2"}

    def test_walks_nested_dict(self):
        obj = {"a": {"b": {"c": "value"}}}
        result = dict(walk_keys(obj))
        assert result == {"a.b.c": "value"}

    def test_skips_metadata_keys(self):
        obj = {"_meta": "skip", "key": "value"}
        result = dict(walk_keys(obj))
        assert result == {"key": "value"}

    def test_skips_non_string_values(self):
        obj = {"str": "value", "num": 123, "arr": [1, 2]}
        result = dict(walk_keys(obj))
        assert result == {"str": "value"}


class TestSetNestedValue:
    """Tests for set_nested_value function."""

    def test_sets_simple_key(self):
        obj = {}
        set_nested_value(obj, "key", "value")
        assert obj == {"key": "value"}

    def test_sets_nested_key(self):
        obj = {}
        set_nested_value(obj, "a.b.c", "value")
        assert obj == {"a": {"b": {"c": "value"}}}

    def test_preserves_existing_structure(self):
        obj = {"a": {"existing": "data"}}
        set_nested_value(obj, "a.new", "value")
        assert obj == {"a": {"existing": "data", "new": "value"}}

    def test_strict_mode_raises_on_conflict(self):
        obj = {"a": "string_value"}  # 'a' is a string, not a dict
        with pytest.raises(KeyPathConflictError) as exc_info:
            set_nested_value(obj, "a.b", "value", strict=True)
        assert "'a' exists but is not a dict" in str(exc_info.value)

    def test_non_strict_mode_overwrites(self):
        obj = {"a": "string_value"}
        set_nested_value(obj, "a.b", "value", strict=False)
        assert obj == {"a": {"b": "value"}}


class TestLoadJsonFile:
    """Tests for load_json_file function."""

    def test_loads_valid_json(self, tmp_path):
        file = tmp_path / "test.json"
        file.write_text('{"key": "value"}')
        result = load_json_file(file)
        assert result == {"key": "value"}

    def test_returns_empty_for_missing_file(self, tmp_path):
        result = load_json_file(tmp_path / "nonexistent.json")
        assert result == {}

    def test_returns_empty_for_invalid_json(self, tmp_path, capsys):
        file = tmp_path / "invalid.json"
        file.write_text("not json")
        result = load_json_file(file)
        assert result == {}
        captured = capsys.readouterr()
        assert "Invalid JSON" in captured.err


class TestSaveJsonFile:
    """Tests for save_json_file function."""

    def test_saves_json_with_formatting(self, tmp_path):
        file = tmp_path / "out.json"
        save_json_file(file, {"key": "value"})
        content = file.read_text()
        assert content == '{\n  "key": "value"\n}\n'

    def test_creates_parent_directories(self, tmp_path):
        file = tmp_path / "nested" / "dir" / "out.json"
        save_json_file(file, {"key": "value"})
        assert file.exists()

    def test_preserves_unicode(self, tmp_path):
        file = tmp_path / "unicode.json"
        save_json_file(file, {"emoji": "🎉", "chinese": "中文"})
        content = file.read_text(encoding="utf-8")
        assert "🎉" in content
        assert "中文" in content
