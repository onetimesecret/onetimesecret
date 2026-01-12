"""Pytest fixtures for translation service tests."""

import json
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


# ============================================================================
# Locale fixtures for generate_tasks.py tests
# ============================================================================

@pytest.fixture
def sample_en_locale(tmp_path: Path) -> Path:
    """Create a temp directory with sample English JSON files.

    Structure:
        en/
            auth.json - nested structure with login/signup keys
            dashboard.json - flat structure
    """
    en_dir = tmp_path / "en"
    en_dir.mkdir()

    # auth.json - nested structure
    auth_data = {
        "web": {
            "login": {
                "button": "Sign In",
                "title": "Welcome Back",
                "_context": "Login page metadata (should be skipped)",
            },
            "signup": {
                "button": "Create Account",
                "title": "Join Us",
            },
        },
    }
    (en_dir / "auth.json").write_text(json.dumps(auth_data, indent=2))

    # dashboard.json - simpler structure
    dashboard_data = {
        "web": {
            "dashboard": {
                "title": "Dashboard",
                "welcome": "Welcome to your dashboard",
            },
        },
    }
    (en_dir / "dashboard.json").write_text(json.dumps(dashboard_data, indent=2))

    return en_dir


@pytest.fixture
def sample_target_locale(tmp_path: Path) -> Path:
    """Create a temp directory with partial translations.

    Structure:
        eo/
            auth.json - partial translation (missing signup.title, empty signup.button)
            # dashboard.json is missing entirely
    """
    eo_dir = tmp_path / "eo"
    eo_dir.mkdir()

    # auth.json - partial translation
    auth_data = {
        "web": {
            "login": {
                "button": "Ensaluti",
                "title": "Bonvenon",
            },
            "signup": {
                "button": "",  # Empty translation
                # "title" is missing entirely
            },
        },
    }
    (eo_dir / "auth.json").write_text(json.dumps(auth_data, indent=2))

    # Note: dashboard.json is intentionally missing

    return eo_dir


@pytest.fixture
def mock_src_locales(tmp_path: Path) -> Path:
    """Create a complete mock src/locales structure for testing.

    Returns the base locales directory (tmp_path) which contains en/ and eo/.
    """
    # Create en/ directory with files
    en_dir = tmp_path / "en"
    en_dir.mkdir()

    auth_data = {
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
    (en_dir / "auth.json").write_text(json.dumps(auth_data, indent=2))

    settings_data = {
        "web": {
            "settings": {
                "title": "Settings",
                "save": "Save Changes",
            },
        },
    }
    (en_dir / "settings.json").write_text(json.dumps(settings_data, indent=2))

    # Create eo/ directory with partial files
    eo_dir = tmp_path / "eo"
    eo_dir.mkdir()

    eo_auth_data = {
        "web": {
            "login": {
                "button": "Ensaluti",
                # "title" is missing
            },
            # "signup" section is missing entirely
        },
    }
    (eo_dir / "auth.json").write_text(json.dumps(eo_auth_data, indent=2))
    # settings.json is missing entirely

    return tmp_path
