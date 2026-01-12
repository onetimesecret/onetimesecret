"""Pytest fixtures for translation service tests."""

import sqlite3
from pathlib import Path

import pytest

# Paths relative to the locales directory
LOCALES_DIR = Path(__file__).parent.parent
SCHEMA_PATH = LOCALES_DIR / "db" / "schema.sql"
FIXTURES_DIR = Path(__file__).parent / "fixtures"
SAMPLE_TASKS_PATH = FIXTURES_DIR / "sample_tasks.sql"


@pytest.fixture
def tmp_db_path(tmp_path: Path) -> Path:
    """Temporary path for a test database file."""
    return tmp_path / "test_translations.db"


@pytest.fixture
def schema_sql() -> str:
    """Read the actual schema.sql content."""
    return SCHEMA_PATH.read_text()


@pytest.fixture
def sample_tasks_sql() -> str:
    """Read the sample tasks SQL fixture."""
    return SAMPLE_TASKS_PATH.read_text()


@pytest.fixture
def hydrated_db(tmp_db_path: Path, schema_sql: str) -> Path:
    """Pre-hydrated database with schema applied, ready for query tests."""
    conn = sqlite3.connect(tmp_db_path)
    try:
        conn.executescript(schema_sql)
        conn.commit()
    finally:
        conn.close()
    return tmp_db_path


@pytest.fixture
def hydrated_db_with_data(hydrated_db: Path, sample_tasks_sql: str) -> Path:
    """Database with schema and sample translation tasks loaded."""
    conn = sqlite3.connect(hydrated_db)
    try:
        conn.executescript(sample_tasks_sql)
        conn.commit()
    finally:
        conn.close()
    return hydrated_db


@pytest.fixture
def db_connection(hydrated_db: Path):
    """SQLite connection to a hydrated database."""
    conn = sqlite3.connect(hydrated_db)
    conn.row_factory = sqlite3.Row
    yield conn
    conn.close()


@pytest.fixture
def db_connection_with_data(hydrated_db_with_data: Path):
    """SQLite connection to a database with sample data."""
    conn = sqlite3.connect(hydrated_db_with_data)
    conn.row_factory = sqlite3.Row
    yield conn
    conn.close()
