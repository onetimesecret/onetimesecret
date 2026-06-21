---
description: Author and run a Workflow that drains pending i18n translation tasks across locales, then stop (no export)
argument-hint: <locale-codes...> | (empty = auto-detect every locales/content/* with pending>0)
allowed-tools: Workflow, Bash, Read, Write, Edit, Glob
disallowed-tools: Bash(git commit:*), Bash(git push:*), Bash(pnpm run locales:sync:*)
---

# Drain i18n translation tasks via Workflow

This is an **ultracode** command: it deliberately opts into multi-agent
orchestration. Author a single self-contained `Workflow` script that drains the
pending `translation_tasks` queue for the targeted locales, audits the completed
rows, fixes problems in place, and then **stops**. Export, `pnpm sync`, and the
glossary pass are separate human steps — do not run them.

## Entry point (the only one)

```
python3 locales/scripts/i18n <group> <cmd>        # --help lists: content tasks db validate
```

The older `locales/scripts/tasks/*.py`, `store.py`, and `migrate` paths were
**consolidated into this CLI**. Ignore them, and ignore the two stale slash
commands that still reference them.

## Phase 0 — scout the work-list inline (before authoring the Workflow)

Discover, do not assume. Run these yourself in the main loop first:

1. **Does the DB exist?** `tasks.db` is gitignored and may be absent in this
   worktree. If absent, inspect `locales/db/tasks.db.backup-from-main.txt`
   (a 12MB *renamed DB snapshot*, not text) and decide:
   - restore it (`cp` to `locales/db/tasks.db`, then sanity-check with
     `tasks next <loc> --stats`), **or**
   - rebuild: `i18n db init` then `i18n db import` (loads committed
     glossary/session_log).
2. **Targets.** If `$ARGUMENTS` is non-empty, use those locale codes verbatim.
   Otherwise auto-detect: enumerate `locales/content/*` dirs and keep those whose
   `i18n tasks next <loc> --stats` reports `pending > 0`.
3. **Build the queue per target.** `i18n tasks create <loc>` (re)builds
   `translation_tasks` from `en`. It is **target-blind**: it will not enqueue
   *stale* keys (already translated, but `en` changed since), so `0 pending`
   means "no untranslated keys," **not** "fully current." Note that limitation;
   do not try to work around it here.
4. **Enable WAL once, before fan-out.** All locales share one `tasks.db`
   (`journal_mode=delete`, `busy_timeout=0` by default), so concurrent writers
   collide:
   ```bash
   sqlite3 locales/db/tasks.db "PRAGMA journal_mode=WAL"
   ```

Record the scouted target list + per-locale pending counts; pass them into the
Workflow as `args`.

## Phase 1 — author and run the Workflow

Use the `Workflow` tool. Shape:

- `agentType: "saas-translator"` for every translating/auditing agent.
- **`pipeline()` over the target locales**, one independent chain per locale — no
  barrier. Each chain is a **loop-until-dry**: `next --json` → translate → write
  → `update --validate`, repeated until `--stats` shows `pending == 0`.
- A second pipeline stage **audits** each drained locale and fixes in place.

### Per-task cycle (inside each locale's agent — one writer per locale, claim-free)

`next <loc> --json` → translate every value → write the `{"key":"translation"}`
object (the **EXACT source key set**) to a **per-locale temp file** →
`tasks update <ID> --file /tmp/trans_<loc>.json --validate`. Then loop.

- **Temp file is mandatory.** Apostrophes/quotes (fr/es/it) break shell quoting
  and HEREDOCs. Per-locale paths (`/tmp/trans_<loc>.json`) so concurrent agents
  never clobber each other.
- **One writer per locale ⇒ skip `--claim`.** `tasks next` returns only *pending*
  rows, so a single writer advances with zero orphans.
- **`--validate` is ADVISORY.** It warns on missing/extra keys but still saves and
  exits 0. **Read the `Warning:` lines** and re-submit with the exact source key
  set. A completed row's keys must match the source exactly.
- **Preserve every var/markup token verbatim and in count:** `{var}`, `{{var}}`,
  `%{var}`, `%s`, `<tag>`.
- **Conventions:** `locales/guides/for-translators/<loc>.md`. Regional variants
  fall back to the base guide (e.g. `de_AT` → `de.md`). Brand names stay English
  (Onetime Secret, Identity Plus, Starlight, …).
- **On `database is locked`:** wait ~2s and retry (up to 3×).

### Audit stage (after a locale drains)

Because `--validate` does not gate writes, audit the completed rows per locale
for: (a) key-set match vs source, (b) variable/markup token preservation, and
(c) untranslated-English leakage. Fix in place via `tasks update --file`.

The glossary pass (step 7 of the manual protocol) is **NOT** part of this drain.
Leave it.

### Workflow skeleton (adapt — fill TARGETS from Phase 0)

```js
export const meta = {
  name: 'drain-i18n-translations',
  description: 'Drain pending translation_tasks per locale, then audit and fix in place',
  phases: [{ title: 'Drain' }, { title: 'Audit' }],
}

const TARGETS = args.targets   // e.g. ["fr_CA","de","es"] — scouted inline

const results = await pipeline(
  TARGETS,
  loc => agent(
    `Drain ALL pending translation tasks for locale "${loc}" in this repo.\n` +
    `Loop until \`python3 locales/scripts/i18n tasks next ${loc} --stats\` shows pending:0.\n` +
    `Each round: tasks next ${loc} --json -> translate -> Write the {"key":"value"} object\n` +
    `(EXACT source key set) to /tmp/trans_${loc}.json -> tasks update <ID> --file /tmp/trans_${loc}.json --validate.\n` +
    `--validate only WARNS; read Warning lines and resubmit with the exact key set.\n` +
    `Preserve {var} {{var}} %{var} %s <tag> verbatim and in count. Brand names stay English.\n` +
    `Guide: locales/guides/for-translators/${loc}.md (regional variants fall back to base, e.g. de_AT -> de.md).\n` +
    `On "database is locked" wait ~2s and retry. Return final pending/completed counts.`,
    { label: `drain:${loc}`, phase: 'Drain', agentType: 'saas-translator' }
  ),
  (_drained, loc) => agent(
    `Audit completed translation rows for locale "${loc}": key-set match vs source,\n` +
    `var/markup token preservation ({var} {{var}} %{var} %s <tag>), and untranslated-English leakage.\n` +
    `Fix any problems in place via tasks update --file /tmp/trans_${loc}.json. Do NOT export or commit.\n` +
    `Return: rows audited, rows fixed, and final \`tasks next ${loc} --stats\` pending count.`,
    { label: `audit:${loc}`, phase: 'Audit', agentType: 'saas-translator' }
  )
)

return { results }
```

## Done

DONE = every targeted locale shows `pending:0` via
`python3 locales/scripts/i18n tasks next <loc> --stats`. Verify this in the main
loop after the Workflow returns, then report final per-locale counts.

Do **not** export, do **not** `pnpm sync`, do **not** commit.

---

Targets: $ARGUMENTS — if empty, auto-detect every `locales/content/*` directory whose `tasks next <loc> --stats` reports `pending > 0`.
