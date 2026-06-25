---
description: Author and run a Workflow that drains pending i18n translation tasks across locales, then stop (no export)
argument-hint: <locale-codes...> | (empty = auto-detect every locales/content/* with pending>0)
allowed-tools: Workflow, Bash, Read, Write, Edit, Glob
disallowed-tools: Bash(git commit:*), Bash(git push:*), Bash(pnpm run locales:sync:*)
---

# Drain i18n translation tasks via Workflow

This is an **ultracode** command: it deliberately opts into multi-agent
orchestration. Author a single self-contained `Workflow` script that drains the
pending `translation_tasks` queue for the targeted locales, then **stops**. The
per-task cycle, audit, and all per-locale governance live in files the agents read
at runtime — this command is orchestration only. Export, `pnpm sync`, and the
glossary pass are separate human steps — do not run them.

Each translating/auditing agent follows `locales/AGENT_TRANSLATION_PROTOCOL.md`
exactly and reads its per-locale governance from
`generated/i18n/.resolved/{LOCALE}.json` (derived on demand — see Phase 0).
Concurrency is owned by the CLI (every
connection opens WAL with a 30s busy timeout), so there is no WAL/lock setup or
retry handling here.

## Entry point (the only one)

```
python3 locales/scripts/i18n <group> <cmd>        # --help lists: content tasks db validate
```

The older `locales/scripts/tasks/*.py`, `store.py`, and `migrate` paths were
**consolidated into this CLI**. Ignore them, and ignore any stale slash commands
that still reference them.

## Phase 0 — scout the work-list inline (before authoring the Workflow)

Discover, do not assume. Run these yourself in the main loop first:

1. **Does the DB exist?** `tasks.db` is gitignored and may be absent in this
   worktree. If absent, inspect `locales/db/tasks.db.backup-from-main.txt`
   (a 12MB *renamed DB snapshot*, not text) and decide:
   - restore it (`cp` to `locales/db/tasks.db`, then sanity-check with
     `tasks next <loc> --stats`), **or**
   - rebuild: `i18n db init` then `i18n db import` (loads committed
     glossary/session_log).
2. **Candidate targets.** If `$ARGUMENTS` is non-empty, use those locale codes
   verbatim; otherwise enumerate `locales/content/*` dirs as candidates. (Do NOT
   filter on `pending` yet — a fresh or just-imported DB has no task rows, so an
   eligible untranslated locale would read `pending == 0` and be dropped before
   its queue is ever built.)
3. **Derive governance, then check eligibility.** Governance is derived on demand
   (no-vendor) into the gitignored `generated/i18n/` cache — run it first:
   ```bash
   locales/scripts/derive-governance.sh   # writes generated/i18n/.resolved/<loc>.json at the canonical pin
   ```
   A locale is eligible for automated drain **only if**
   `generated/i18n/.resolved/<loc>.json` exists with a populated `register` and a
   populated `glossary` (it is governed upstream at the pin). For each candidate,
   check this and **SKIP + warn** for any locale that lacks it:
   ```bash
   jq -e '((.register // {}) | length > 0) and ((.glossary // {}) | length > 0)' "generated/i18n/.resolved/$loc.json" >/dev/null 2>&1 || echo "SKIP (not governed at pin): $loc"
   ```
4. **Refresh each eligible target's queue, THEN filter on pending.** Build the
   queue before checking pending. Use `--missing-only` so an existing locale
   enqueues only keys still untranslated in `content/<loc>` and never requeues
   already-translated, reviewed strings:
   ```bash
   i18n tasks create <loc> --missing-only      # per eligible target
   i18n tasks next <loc> --stats               # keep targets now showing pending > 0
   ```
   `tasks create` is still target-blind about *stale* keys (already translated but
   `en` changed since), so `0 pending` means "no untranslated keys," **not** "fully
   current" — note that, don't work around it here.

Record the scouted (and eligible) target list + per-locale pending counts; pass
them into the Workflow as `args`.

## Phase 1 — author and run the Workflow

Use the `Workflow` tool. Shape:

- `agentType: "saas-translator"` for every translating/auditing agent.
- **`pipeline()` over the eligible target locales**, one independent chain per
  locale — no barrier. Each chain is a **loop-until-dry** drain.
- A second pipeline stage **audits** each drained locale and fixes in place.

The agents own the per-task cycle, the temp-file/`--validate` handling, the audit,
and all governance — those are defined in `locales/AGENT_TRANSLATION_PROTOCOL.md`
and `generated/i18n/.resolved/<loc>.json`. Keep the per-locale agent prompt short and
point it at those files; do not re-derive the cycle here.

The glossary pass (step 7 of the manual protocol) is **NOT** part of this drain.
Leave it.

### Workflow skeleton (adapt — fill TARGETS from Phase 0)

```js
export const meta = {
  name: 'drain-i18n-translations',
  description: 'Drain pending translation_tasks per locale, then audit and fix in place',
  phases: [{ title: 'Drain' }, { title: 'Audit' }],
}

const TARGETS = args.targets   // e.g. ["fr_CA","de","es"] — scouted + eligible inline

const results = await pipeline(
  TARGETS,
  loc => agent(
    `Drain translation tasks for locale "${loc}". ` +
    `Follow locales/AGENT_TRANSLATION_PROTOCOL.md exactly. ` +
    `Per-locale governance (register, glossary, binding rules, declined decisions): ` +
    `generated/i18n/.resolved/${loc}.json. ` +
    `Preserve all interpolation/markup tokens; brand names stay English. ` +
    `Loop until 0 pending; do not export or commit. Return final pending/completed counts.`,
    { label: `drain:${loc}`, phase: 'Drain', agentType: 'saas-translator' }
  ),
  (_drained, loc) => agent(
    `Audit completed translation rows for locale "${loc}" per ` +
    `locales/AGENT_TRANSLATION_PROTOCOL.md (key-set match vs source, token preservation, ` +
    `untranslated-English leakage), using governance in generated/i18n/.resolved/${loc}.json. ` +
    `Fix any problems in place. Do NOT export or commit. ` +
    `Return: rows audited, rows fixed, and final \`tasks next ${loc} --stats\` pending count.`,
    { label: `audit:${loc}`, phase: 'Audit', agentType: 'saas-translator' }
  )
)

return { results }
```

## Done

DONE = every targeted (eligible) locale shows `pending:0` via
`python3 locales/scripts/i18n tasks next <loc> --stats`. Verify this in the main
loop after the Workflow returns, then report final per-locale counts (and list any
locales skipped for missing resolved governance).

Do **not** export, do **not** `pnpm sync`, do **not** commit.

---

Targets: $ARGUMENTS — if empty, auto-detect every `locales/content/*` directory whose `tasks next <loc> --stats` reports `pending > 0`.
