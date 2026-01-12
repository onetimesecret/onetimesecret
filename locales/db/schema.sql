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
