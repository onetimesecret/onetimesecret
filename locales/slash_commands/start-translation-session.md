---
description: Start a parallel translation session with background agents for multiple locales
argument-hint: <locale-codes...> [--focus LOCALE]
allowed-tools: Bash, Task, Read, Glob, TodoWrite, KillShell
---

# Start Translation Session

Orchestrates parallel background agents to translate locales using the task-based workflow. Each agent completes tasks independently (one writer per locale), with the main session monitoring progress and replacing agents as they complete.

## Environment & Concurrency

- **No `.env.sh`** — the project uses direnv (`.envrc`). Run `python3 locales/scripts/i18n tasks ...`
  directly from the repo root; the scripts need no sourcing.
- **Unified CLI** — all locale tooling is one entry point: `python3 locales/scripts/i18n <group> <cmd>`
  (groups: `tasks` create/next/update/export, `db` init/migrate/query/export/import). The old
  per-script paths (`locales/scripts/tasks/*.py`, `store.py`, `migrate/export.py`) are gone.
- **One writer per locale, claim-free** — `tasks next {LOCALE}` (next *pending*) → `tasks update {ID}`
  (completed) advances with zero orphans, so `--claim` is unnecessary. If you use it with
  multiple writers on a locale, reset stranded `in_progress` rows at start
  (`tasks update {ID} --status pending`).
- **Enable WAL once before launching** — all locales share one `tasks.db`
  (`journal_mode=delete`, `busy_timeout=0` by default):
  `sqlite3 locales/db/tasks.db "PRAGMA journal_mode=WAL"`. Agents retry on `database is locked`.
- **`--validate` is advisory** — warns on key mismatches but still saves; agents must read the
  warnings and re-submit with the exact source key set. Audit completed rows after draining.

## Quick Start

```bash
# Check what needs translating
python3 locales/scripts/i18n tasks next --help

# See stats for a locale
python3 locales/scripts/i18n tasks next fr_CA --stats
```

## Session Workflow

### 1. Create Tasks (if needed)

For each locale that needs tasks generated:

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

For each locale, launch a `saas-translator` agent with `run_in_background: true`:

```
Task tool:
  description: "Translate {LOCALE}"
  subagent_type: "saas-translator"
  run_in_background: true
  prompt: |
    Continue {LANGUAGE} ({LOCALE}) translation for OneTimeSecret.

    **Workflow (run from repo root; no `source .env.sh` — direnv handles env):**
    1. Next task: `python3 locales/scripts/i18n tasks next {LOCALE} --json`
       (one writer per locale, so `--claim` is unnecessary; stop when no pending task)
    2. Translate all keys using conventions below
    3. Write the {"key": "translation"} object (EXACT source key set) to a temp file
       with the Write tool, then save with `--file` (apostrophe/quote-safe; avoids
       HEREDOC and shell-quoting breakage in fr/es/it):
       ```bash
       python3 locales/scripts/i18n tasks update TASK_ID --file /tmp/trans_{LOCALE}.json --validate
       ```
    4. READ the output: `--validate` only WARNS, it still saves a bad write. On
       "Warning: Missing/Extra keys", rebuild with the exact source keys and re-run.
       On "database is locked", wait ~2s and retry.
    5. Repeat until no more tasks or context limit (aim for 15+ tasks per session)

    **{LOCALE} Conventions:**
    {CONVENTIONS_FOR_LOCALE}

    **Critical Rules:**
    - Preserve ALL variables/markup exactly: `{var}`, `{{var}}`, `%{var}`, `%s`, `<tag>`
    - The saved key set must match the source keys exactly (none added/dropped)
    - Keep brand name "Onetime Secret" unchanged
    - Do NOT export translations - only complete tasks

    Complete as many tasks as possible.
```

### 4. Start Watch Process

Launch a background bash to monitor progress:

```bash
while true; do
  echo "=== $(date +%H:%M:%S) ==="
  python3 locales/scripts/i18n db query "SELECT locale, status, COUNT(*) as count FROM translation_tasks GROUP BY locale, status ORDER BY locale, status"
  sleep 10
done
```

Note the shell_id from the response for later cleanup.

### 5. Handle Agent Completions

When an agent completes (via `<task-notification>`):

1. **If locale has pending tasks**: Launch replacement agent for same locale
2. **If locale is complete**: Mark todo as completed, check if new locale should start
3. **Maintain max 5 agents** running at once

### 6. Monitor Progress

Check watch output periodically:

```bash
tail -20 /private/tmp/claude/.../tasks/SHELL_ID.output
```

Or run stats manually:

```bash
python3 locales/scripts/i18n tasks next LOCALE --stats
```

### 7. Session Complete

When all locales show 0 pending:

1. Kill watch process: `KillShell with shell_id: "SHELL_ID"`
2. Clear todo list
3. Report final status

**Do NOT export** - that's a separate step for the user to run when ready.

## Locale Conventions Reference

| Locale | Key Conventions |
|--------|-----------------|
| **fr_CA** | courriel, mot de passe, phrase secrete; infinitif for buttons; non-breaking space before `: ; ! ?` |
| **de** | informal "du"; secret→Nachricht, passphrase→Passphrase, burn→loschen; compound nouns |
| **es** | informal "tu"; secreto, contrasena, frase de contrasena; `?` `!` inverted punctuation |
| **pt_BR** | informal "voce"; mensagem confidencial, frase secreta; Painel, Configuracoes |
| **eo** | sekreto, sekreta frazo, pasvorto, forbruligi, retposto; diacritics (ĉĝĵŝŭ) |
| **fr_FR** | Similar to fr_CA but use "e-mail" not "courriel"; vous form for formal contexts |
| **it** | informal "tu"; segreto, password, frase segreta; Pannello, Impostazioni |
| **nl** | informal "je"; geheim, wachtwoord, wachtwoordzin; compound nouns |
| **ja** | polite form; シークレット, パスワード, パスフレーズ; no spaces between words |
| **zh** | Simplified; 密码, 密语, 秘密; no spaces |
| **ko** | polite form; 비밀, 비밀번호, 암호문구 |
| **ru** | informal "ты"; секрет, пароль, кодовая фраза |

## Agent Replacement Template

When agent completes and locale has remaining tasks:

```
Task tool:
  description: "Continue {LOCALE} translation"
  subagent_type: "saas-translator"
  run_in_background: true
  prompt: |
    Continue {LANGUAGE} ({LOCALE}) translation session. ~{COMPLETED}/{TOTAL} tasks done.

    **Workflow:**
    1. Run: `python3 locales/scripts/i18n tasks next {LOCALE} --json`
    2. Translate using established conventions
    3. Write {"key": "translation"} (exact source keys) to a temp file, then:
       `python3 locales/scripts/i18n tasks update TASK_ID --file /tmp/trans_{LOCALE}.json --validate`
       (`--validate` only warns; re-run on key-mismatch warnings. Retry on "database is locked".)
    4. Repeat until no tasks or context limit

    **{LOCALE} Conventions:**
    {CONVENTIONS}

    Complete as many tasks as possible.
```

## Recovery After /compact

1. Run stats to see current state:
   ```bash
   for locale in fr_CA de es pt_BR eo; do
     echo "=== $locale ===" && python3 locales/scripts/i18n tasks next $locale --stats
   done
   ```

2. Rebuild todo list from current state

3. Launch agents for locales with pending tasks

4. Restart watch process

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

User should run export manually when ready:

```bash
python3 locales/scripts/i18n tasks export LOCALE
```

Then sync to src:

```bash
pnpm run locales:sync
```
