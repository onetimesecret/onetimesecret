-- Legacy per-key task table (used by hydrate_from_json for historical data)
CREATE TABLE IF NOT EXISTS translation_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch TEXT NOT NULL,              -- '2026-01-11' groups related work
    locale TEXT NOT NULL,
    file TEXT NOT NULL,               -- 'auth.json'
    key TEXT NOT NULL,                -- 'web.auth.security.rate_limited'
    english_text TEXT NOT NULL,
    translation TEXT,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'completed', 'skipped', 'error')),
    notes TEXT,                       -- translator notes, errors
    created_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    UNIQUE(locale, file, key)
);

CREATE INDEX IF NOT EXISTS idx_locale_status ON translation_tasks(locale, status);
CREATE INDEX IF NOT EXISTS idx_batch ON translation_tasks(batch);

-- Level-based task table (groups sibling keys by parent path)
-- A "level" is a parent path, e.g., web.COMMON.buttons groups submit, cancel, etc.
CREATE TABLE IF NOT EXISTS level_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file TEXT NOT NULL,               -- 'auth.json'
    level_path TEXT NOT NULL,         -- 'web.COMMON.buttons' (parent path)
    locale TEXT NOT NULL,             -- 'eo', 'de', etc.
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK(status IN ('pending', 'in_progress', 'completed', 'skipped')),
    keys_json TEXT NOT NULL,          -- JSON: {"submit": "Submit", "cancel": "Cancel"}
    translations_json TEXT,           -- JSON: {"submit": "Sendi", "cancel": "Nuligi"} or NULL
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(file, level_path, locale)
);

CREATE INDEX IF NOT EXISTS idx_level_locale_status ON level_tasks(locale, status);
CREATE INDEX IF NOT EXISTS idx_level_file ON level_tasks(file);
