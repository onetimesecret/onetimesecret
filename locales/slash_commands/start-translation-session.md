---
description: Start a parallel translation session with background agents for multiple locales
argument-hint: <locale-codes...> [--focus LOCALE]
allowed-tools: Bash, Task, Read, Glob, TodoWrite
---

# Start Translation Session

Orchestration ONLY. This command launches, monitors, and replaces background
translator agents. It does **not** carry workflow steps or per-locale conventions:
each agent follows `locales/AGENT_TRANSLATION_PROTOCOL.md` exactly, and reads its
per-locale governance from `locales/.resolved/{LOCALE}.json`. Concurrency is owned
by the CLI (every connection opens WAL with a 30s busy timeout), so there is no
WAL/lock setup or retry handling here.

One writer per locale: each agent drains its locale's task queue independently;
the main session tracks progress with TodoWrite and replaces agents as they finish.

## Eligibility gate (check per target locale)

A locale is eligible for automated drain **only if**
`locales/.resolved/{LOCALE}.json` exists with a populated `register` and a
populated `glossary` (i.e., its governance has been back-ported upstream). For
every requested locale, verify this first and **SKIP + warn** for any locale that
lacks it:

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

## Quick Start

```bash
# See stats for a locale
python3 locales/scripts/i18n tasks next fr_CA --stats
```

## Session Workflow

### 1. Create Tasks (if needed)

For each eligible locale that needs tasks generated:

```bash
python3 locales/scripts/i18n tasks create LOCALE
```

### 2. Track Agents with TodoWrite

Create one todo per locale being worked on:

```
TodoWrite with todos:
  - {content: "fr_CA: Canadian French", status: "in_progress", activeForm: "Agent translating fr_CA"}
  - {content: "de: German", status: "in_progress", activeForm: "Agent translating de"}
  ...
```

### 3. Launch Background Agents

For each eligible locale, launch a `saas-translator` agent with
`run_in_background: true`. The prompt is short — all workflow and governance lives
in the referenced files:

```
Task tool:
  description: "Translate {LOCALE}"
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

Poll on demand — never spawn background sleep loops. Run a single poll, read it,
then poll again when ready:

```bash
for locale in $ELIGIBLE_LOCALES; do
  printf "%-6s: " "$locale"
  python3 locales/scripts/i18n tasks next $locale --stats
done
```

### 5. Handle Agent Completions

When an agent completes (via `<task-notification>`):

1. **If locale has pending tasks**: launch a replacement agent for that locale
   using the same short prompt as step 3.
2. **If locale is complete**: mark its todo completed; start a queued locale if one
   is waiting.
3. **Maintain max 5 agents** running at once.

### 6. Session Complete

When all locales show 0 pending:

1. Clear the todo list.
2. Report final per-locale status.

**Do NOT export** — that's a separate step the user runs when ready.

## Recovery After /compact

1. Run stats to see current state:
   ```bash
   for locale in fr_CA de es pt_BR eo; do
     echo "=== $locale ===" && python3 locales/scripts/i18n tasks next $locale --stats
   done
   ```

2. Rebuild the todo list from current state.

3. Re-check the eligibility gate, then launch agents for eligible locales with
   pending tasks (same short prompt as step 3).

## Example Session Status

```
┌────────┬───────────┬─────────┬────────┐
│ Locale │ Completed │ Pending │ % Done │
├────────┼───────────┼─────────┼────────┤
│ fr_CA  │ 130       │ 14      │ 90%    │
│ de     │ 122       │ 22      │ 85%    │
│ eo     │ 111       │ 33      │ 77%    │
│ pt_BR  │ 107       │ 38      │ 74%    │
│ es     │ 105       │ 40      │ 72%    │
└────────┴───────────┴─────────┴────────┘
```

## Next Steps After Completion

User runs export manually when ready:

```bash
python3 locales/scripts/i18n tasks export LOCALE
pnpm run locales:sync
```
