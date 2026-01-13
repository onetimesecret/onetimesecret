# Translation Session Protocol

Branch: `feature/2319-workflow-historical`
Issue: #2319

## Architecture

- **Task = one JSON level** - all keys under `web.COMMON.buttons.*` form one task
- **SQLite is working state** - translations live in `locales/db/tasks.db` until synced
- **Historical JSON is source of truth** - `locales/translations/{locale}/*.json`
- **src/locales is app-consumable** - synced from historical, nested JSON format

## Session Workflow

### 1. Check status
```bash
python locales/scripts/get_next_task.py eo --stats
```

### 2. Claim next task
```bash
python locales/scripts/get_next_task.py eo --claim
```
Outputs formatted table with Key, English, Esperanto columns.

### 3. Review proposed translations
Assistant proposes translations. Respond with:
- **A** - Accept (runs update_task.py)
- **S** - Skip (marks skipped, moves to next)
- **R** - Revisit (marks pending, moves to next)
- **Q** - Quit session

### 4. On accept, update task
```bash
python locales/scripts/update_task.py TASK_ID '{"key": "translation", ...}'
```

### 5. Record glossary decisions
```bash
python locales/scripts/db.py query "INSERT INTO glossary (locale, term, translation, notes) VALUES ('eo', 'secret', 'sekreto', 'core concept')"
```

### 6. End session - export and sync
```bash
python locales/scripts/export_to_historical.py eo
python locales/scripts/sync_to_src.py eo
```

### 7. Commit
```bash
git add locales/translations/eo/ src/locales/eo/
git commit -m "[#2319] Add eo translations from session"
```

## Task Output Format

Title: `**Task 8** · _common.json · web.TITLES · 44 keys`

Table columns:
- Key (28 chars, right-aligned)
- English (60 chars, wrapped)
- Esperanto (60 chars, wrapped)

Sorted by English text length.

## Translation Notes Guidelines

- Include English source text with every proposal
- Compare to similar translations in other languages when relevant
- Note connotations (e.g., "secret" = personal vs confidential)
- Preserve `{placeholders}` exactly

## Key Files

```
locales/scripts/
  get_next_task.py    # --claim, --filter, --stats, --id
  update_task.py      # TASK_ID '{"key": "val"}'
  export_to_historical.py  # SQLite -> historical JSON
  sync_to_src.py      # historical JSON -> src/locales
  generate_tasks.py   # --levels to regenerate tasks
  db.py               # migrate, hydrate, query

locales/db/
  schema.sql          # table definitions
  tasks.db            # SQLite database (not in git)

locales/translations/{locale}/  # historical JSON (source of truth)
src/locales/{locale}/           # app-consumable JSON
```

## Database Tables

- `level_tasks` - translation tasks grouped by JSON level
- `glossary` - terminology decisions per locale
- `session_log` - session records with verbatim notes
- `schema_migrations` - applied schema versions

## Esperanto Status

Run `python locales/scripts/get_next_task.py eo --stats` to check current progress.
