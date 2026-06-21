---
description: Orchestrate parallel translation agents for multiple locales using task-based workflow
argument-hint: <locale-codes...> [--max-agents N]
allowed-tools: Bash, Task, Read, Glob, TodoWrite
---

# Parallel Translation Agent Orchestration

Orchestration ONLY. This command launches, monitors, and replaces background
`saas-translator` agents that drain locales in parallel. It carries no workflow
prose and no per-locale conventions: each agent follows
`locales/AGENT_TRANSLATION_PROTOCOL.md` exactly and reads its per-locale
governance from `locales/.resolved/{LOCALE}.json`. Concurrency is owned by the CLI
(every connection opens WAL with a 30s busy timeout), so there is no WAL/lock
setup or retry handling here.

## Prerequisites

1. Unified CLI at `locales/scripts/i18n` (`tasks create/next/update/export`,
   `db init/migrate/query/export/import`).
2. SQLite task database at `locales/db/tasks.db` (table `translation_tasks`,
   schema `locales/db/schema.sql`). It is NOT in git — rebuild it from the
   committed schema + dumps:
   ```bash
   python3 locales/scripts/i18n db init      # create tasks.db from schema.sql
   python3 locales/scripts/i18n db import    # hydrate glossary/session_log/etc from db/*.sql
   ```
3. Per-locale governance at `locales/.resolved/{LOCALE}.json` (see eligibility gate).
4. Source locale JSON at `./locales/content/{locale}/*.json`.
5. **Paths to IGNORE**: `./generate/`, `./src/locales/` (compiled/legacy, not source).

## Arguments

- `<locale-codes...>`: Space-separated locale codes (e.g., `fr_CA de es pt_BR eo`)
- `--max-agents N`: Maximum concurrent agents (default: 5)
- `--stats`: Show current progress without launching agents
- `--resume`: Resume monitoring existing agents

## Eligibility gate (check per target locale)

A locale is eligible for automated drain **only if**
`locales/.resolved/{LOCALE}.json` exists with a populated `register` and a
populated `glossary` (i.e., its governance has been back-ported upstream). Check
every target first and **SKIP + warn** for any locale that lacks it:

```bash
for locale in $LOCALES; do
  f="locales/.resolved/$locale.json"
  if [ -s "$f" ]; then
    echo "ELIGIBLE: $locale"
  else
    echo "SKIP (no resolved governance): $locale — back-port locales/.resolved/$locale.json first"
  fi
done
```

Only launch agents for `ELIGIBLE` locales.

## Workflow

### 1. Initialize Locales

For each eligible locale that doesn't have tasks yet:

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

For each eligible locale with pending tasks, launch a background agent. The prompt
is short — workflow and governance live in the referenced files:

```
Task tool with:
  subagent_type: "saas-translator"
  run_in_background: true
  prompt: |
    Drain translation tasks for locale {LOCALE}. Follow
    locales/AGENT_TRANSLATION_PROTOCOL.md exactly. Per-locale governance
    (register, glossary, binding rules, declined decisions):
    locales/.resolved/{LOCALE}.json. Preserve all interpolation/markup tokens;
    brand names stay English. Loop until 0 pending; do not export or commit.
```

### 4. Monitor Progress (single poll)

**Do NOT wait passively for agent notifications, and do NOT spawn background sleep
loops.** Proactively run a single poll, read the result, then poll again when ready.

```bash
for locale in fr_CA de es pt_BR eo; do
  printf "%-6s: " "$locale"
  python3 locales/scripts/i18n tasks next $locale --stats 2>/dev/null | grep -oE "[0-9]+ pending|[0-9]+ completed" | tr '\n' ' '
  echo
done
```

#### Anti-Pattern: Background Sleep Loops

```bash
# WRONG - creates a stale notification backlog:
sleep 120 && check_status  # spawned as background task
sleep 120 && check_status  # another background task
# Results in 10+ stale notifications when they all resolve
```

#### Correct Pattern

1. Run a single poll (no sleep, no background).
2. Review results.
3. Relaunch agents for any locale with pending > 0 (same short prompt as step 3).
4. Manually trigger the next poll when ready.

### 5. Completion Criteria

A locale is complete when `--stats` shows 0 pending tasks (all rows
`status = 'completed'`).

Do NOT run export until the user explicitly requests it.

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

## Common Mistakes (Avoid These)

1. **Wrong table name**: the SQLite table is `translation_tasks`, NOT `tasks`.
2. **Wrong locale file path**: source translations live in `./locales/content/`,
   not `src/locales/` or `./generate/`.
3. **Passive waiting**: do NOT just wait for completion notifications — actively
   poll with `tasks next LOCALE --stats`.
4. **Raw database queries**: use the CLI (`tasks next LOCALE --stats`), not raw
   `sqlite3` queries.
5. **Forgetting data hydration**: the DB isn't in git — run
   `python3 locales/scripts/i18n db init && python3 locales/scripts/i18n db import`.

## Recovery

If the session compacts or disconnects:
1. Run `--stats` to see current progress.
2. Re-check the eligibility gate.
3. Run `--resume` to restart monitoring. Agents write directly to the database, so
   no work is lost.

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
1. Verify with `--stats`.
2. User can then run export: `python3 locales/scripts/i18n tasks export <locale>`.
3. Run validation: `pnpm run locales:sync`.
