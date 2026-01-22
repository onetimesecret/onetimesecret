-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,         -- e.g., '001', '002'
    name TEXT NOT NULL,               -- Human-readable name
    applied_at TEXT DEFAULT (datetime('now'))
);

-- Translation tasks table (groups sibling keys by parent path)
-- A "level" is a parent path, e.g., web.COMMON.buttons groups submit, cancel, etc.
-- This consolidates the former level_tasks table as the primary workflow table.
CREATE TABLE IF NOT EXISTS translation_tasks (
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

CREATE INDEX IF NOT EXISTS idx_tasks_locale_status ON translation_tasks(locale, status);
CREATE INDEX IF NOT EXISTS idx_tasks_file ON translation_tasks(file);

-- Glossary table: translation decisions and terminology for each locale
-- Captures choices made during translation sessions for consistency
CREATE TABLE IF NOT EXISTS glossary (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    locale TEXT NOT NULL,             -- 'eo', 'de', etc.
    term TEXT NOT NULL,               -- Term or concept from source language
    translation TEXT NOT NULL,        -- Chosen translation
    context TEXT,                     -- When to use this translation
    alternatives TEXT,                -- Other options considered (JSON array or comma-separated)
    notes TEXT,                       -- Reasoning, style notes
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(locale, term)
);

CREATE INDEX IF NOT EXISTS idx_glossary_locale ON glossary(locale);

-- Session log: record of translation sessions with verbatim feedback
-- Notes should be preserved exactly as written, not summarized or modified
CREATE TABLE IF NOT EXISTS session_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,               -- ISO date: '2026-01-12'
    locale TEXT NOT NULL,             -- 'eo', 'de', etc.
    started_at TEXT NOT NULL,         -- ISO timestamp from script for duration calc
    ended_at TEXT,                    -- ISO timestamp when session ends
    task_count INTEGER DEFAULT 0,     -- Number of tasks completed this session
    notes TEXT,                       -- Verbatim feedback, not summarized
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_session_locale ON session_log(locale);
CREATE INDEX IF NOT EXISTS idx_session_date ON session_log(date);
