-- Sample translation tasks for testing
INSERT INTO translation_tasks (batch, locale, file, key, english_text, status)
VALUES
    ('2026-01-11', 'de', 'auth.json', 'web.login.button', 'Sign In', 'pending'),
    ('2026-01-11', 'de', 'auth.json', 'web.login.title', 'Welcome Back', 'pending'),
    ('2026-01-11', 'es', 'auth.json', 'web.login.button', 'Sign In', 'completed');

-- Task with translation completed
INSERT INTO translation_tasks (batch, locale, file, key, english_text, translation, status, completed_at)
VALUES
    ('2026-01-11', 'fr', 'auth.json', 'web.login.button', 'Sign In', 'Se connecter', 'completed', datetime('now'));

-- Task with error status
INSERT INTO translation_tasks (batch, locale, file, key, english_text, status, notes)
VALUES
    ('2026-01-11', 'ja', 'auth.json', 'web.login.button', 'Sign In', 'error', 'API rate limit exceeded');
