---
description: Orchestrate parallel translation agents for multiple locales using task-based workflow
argument-hint: <locale-codes...> [--max-agents N]
allowed-tools: Bash, Task, Read, Glob, TodoWrite
---

# Parallel Translation Agent Orchestration

Manages multiple background agents translating locales simultaneously using a task-based workflow with SQLite tracking.

## Prerequisites

This command requires:
1. A repo with `locales/TRANSLATION_PROTOCOL.md` (task-based workflow)
2. SQLite task database at `locales/db/tasks.db`
   - Tables: `translation_tasks`, `sessions`
   - Schema: `locales/db/schema.sql`
   - Durable tables committed as SQL dumps: `locales/db/{glossary,session_log,schema_migrations}.sql` (hydrate with `db import`)
3. Unified CLI at `locales/scripts/i18n` (`tasks create/next/update/export`, `db init/migrate/query/export/import`)
4. Locale guides at `locales/guides/for-translators/{locale}.md`
5. Locale JSON files at `./locales/content/{locale}/*.json`
6. **Paths to IGNORE**: `./generate/`, `./src/locales/` (compiled/legacy, not source)

## Database Initialization

`tasks.db` is NOT in git. Build it from the committed schema + dumps:

```bash
python3 locales/scripts/i18n db init      # create tasks.db from schema.sql
python3 locales/scripts/i18n db import    # hydrate glossary/session_log/etc from db/*.sql
```

The committable tables (`glossary`, `session_log`, `translation_issues`) live in `locales/db/*.sql`.

## Arguments

- `<locale-codes...>`: Space-separated locale codes (e.g., `fr_CA de es pt_BR eo`)
- `--max-agents N`: Maximum concurrent agents (default: 5)
- `--stats`: Show current progress without launching agents
- `--resume`: Resume monitoring existing agents

## Workflow

### 1. Initialize Locales

For each locale that doesn't have tasks yet:

```bash
python3 locales/scripts/i18n tasks create LOCALE
```

### 2. Check Current Status

```bash
for locale in fr_CA de es pt_BR eo; do
  echo "=== $locale ==="
  python3 locales/scripts/i18n tasks next $locale --stats
done
```

### 3. Launch Background Agents

For each locale with pending tasks, launch a background agent:

```
Task tool with:
  subagent_type: "saas-translator"
  run_in_background: true
  prompt: |
    Translate OneTimeSecret to {LOCALE}. Work from the repo root; run scripts
    directly (no `source .env.sh` — the project uses direnv).
    Locale guide: locales/guides/for-translators/{LOCALE}.md
    (Regional variants without their own guide fall back to the base, e.g.
    de_AT -> de.md.)

    Loop, ~50 tasks/round:
    1. `python3 locales/scripts/i18n tasks next {LOCALE} --json`  (stop if no pending task)
    2. Translate each value; preserve every variable/tag verbatim ({var}, {{var}},
       %{var}, %s, <tag>) with the same set and count.
    3. Write the {"key": "translation"} object (EXACT source key set) to a temp file
       with the Write tool, then:
       `python3 locales/scripts/i18n tasks update {ID} --file /tmp/trans_{LOCALE}.json --validate`
    4. READ the output: `--validate` only WARNS, it still saves a bad write. If you see
       "Warning: Missing/Extra keys", rebuild with the exact source keys and re-run.
    5. On "database is locked", wait ~2s and retry (up to 3x).
    Report completed-this-round and remaining (`tasks next {LOCALE} --stats`).
```

The `saas-translator` agent knows variable-preservation rules, but the task-DB cycle,
the `--file` temp-file write (apostrophe-safe), and the `--validate`-is-advisory caveat
must be in the prompt — see "Agent Execution Notes" below.

### 4. Monitor Progress (CRITICAL)

**Do NOT wait passively for agent notifications.** Proactively poll using the existing scripts.

#### Single Poll (Recommended)
```bash
for locale in fr_CA de es pt_BR eo; do
  printf "%-6s: " "$locale"
  python3 locales/scripts/i18n tasks next $locale --stats 2>/dev/null | grep -oE "[0-9]+ pending|[0-9]+ completed" | tr '\n' ' '
  echo
done
```

Run this manually, check result, then run again. Do NOT spawn background sleeps.

#### Anti-Pattern: Background Sleep Loops
```bash
# WRONG - creates stale notification backlog:
sleep 120 && check_status  # spawned as background task
sleep 120 && check_status  # another background task
# Results in 10+ stale notifications when they all resolve
```

#### Correct Pattern
1. Run single poll (no sleep, no background)
2. Review results
3. Relaunch agents if needed
4. Manually trigger next poll when ready

**Avoid**: Raw SQLite queries, background sleep loops, passive waiting

### 5. Completion Criteria

A locale is complete when:
- `--stats` shows 0 pending tasks
- All tasks status = 'completed' in database

Do NOT run export until user explicitly requests it.

## Locale-Specific Conventions

See `locales/guides/for-translators/{locale}.md` for each locale's terminology, formality, and style rules.

Available guides: `ls locales/guides/for-translators/`

## Usage Examples

```bash
# Start fresh with 3 locales, max 5 agents
/d:translate-parallel-agents fr_CA de es --max-agents 5

# Check progress only
/d:translate-parallel-agents --stats

# Resume monitoring after /compact
/d:translate-parallel-agents --resume

# Add more locales to existing run
/d:translate-parallel-agents pt_BR eo --max-agents 5
```

## Agent Execution Notes (hard-won)

- **Environment**: no `.env.sh` (the project uses direnv/`.envrc`). The task scripts need
  no sourcing — run `python3 locales/scripts/i18n tasks ...` directly from the repo root.
- **One writer per locale, claim-free**: with a single agent per locale, `tasks next {LOCALE}`
  (next *pending*) → `tasks update {ID}` (completed) advances with zero orphans; skip `--claim`.
  If you ever run multiple writers on one locale and use `--claim`, reset stranded
  `in_progress` rows at start (`tasks update {ID} --status pending`); `tasks next` only returns
  *pending* tasks, so an abandoned claim is otherwise invisible.
- **Write via temp file, not inline JSON**: apostrophes/quotes (fr/es/it) break shell
  quoting and HEREDOCs. Write the object to a file and use
  `tasks update {ID} --file /tmp/trans_{LOCALE}.json --validate`.
- **`--validate` is advisory**: it warns on missing/extra keys but still saves and exits 0.
  Agents must read the warnings and re-submit with the exact source key set.
- **SQLite concurrency**: all locales share one `tasks.db` (`journal_mode=delete`,
  `busy_timeout=0` by default). Enable WAL once before launching so readers never block the
  writer: `sqlite3 locales/db/tasks.db "PRAGMA journal_mode=WAL"`. On `database is locked`,
  wait ~2s and retry.
- **Verify after draining**: because `--validate` doesn't gate writes, audit completed rows
  per locale for key-set mismatch, variable/markup preservation, and untranslated-English
  leakage; fix with `tasks update --file`.

## Common Mistakes (Avoid These)

1. **Wrong table name**: The SQLite table is `translation_tasks`, NOT `tasks`
   ```sql
   -- WRONG: SELECT * FROM tasks
   -- RIGHT: SELECT * FROM translation_tasks
   ```

2. **Wrong locale file path**: Source translations live in `./locales/content/`
   ```bash
   # WRONG: ls src/locales/ or ls ./generate/
   # RIGHT: ls ./locales/content/
   ```

3. **Passive waiting**: Do NOT just wait for agent completion notifications. Actively poll:
   ```bash
   # Use this, not raw sqlite3 queries:
   python3 locales/scripts/i18n tasks next LOCALE --stats
   ```

4. **Raw database queries**: The task scripts already exist - use them:
   ```bash
   # WRONG: sqlite3 locales/db/tasks.db "SELECT COUNT(*) FROM translation_tasks..."
   # RIGHT: python3 locales/scripts/i18n tasks next LOCALE --stats
   ```

5. **Forgetting data hydration**: The DB isn't in git - schema alone gives an empty DB. Run `python3 locales/scripts/i18n db init && python3 locales/scripts/i18n db import`.

## Recovery

If session compacts or disconnects:
1. Run `--stats` to see current progress
2. Run `--resume` to restart monitoring
3. Agents write directly to database, so no work is lost

#### Context Window Full
When approaching context limits, use `/compact` with continuation instructions:

```
/compact with instructions to continue monitoring translation agents for fr_CA, de, es.
Poll with: python3 locales/scripts/i18n tasks next LOCALE --stats
Relaunch agents for any locale with pending > 0.
```

Then simply: `Please continue`

This preserves the orchestration state across compaction.

## Completion

When all locales show 0 pending:
1. Verify with `--stats`
2. User can then run export: `python3 locales/scripts/i18n tasks export <locale>`
3. Run validation: `pnpm run locales:sync`
