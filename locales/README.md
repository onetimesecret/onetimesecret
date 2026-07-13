# Translation Service

Orchestration tooling for managing locale translations. Tracks translation tasks in SQLite, coordinates batch processing, and maintains translation quality.

## Structure

- `content/` - Version-controlled source of truth for all locales (flat keys)
- `db/` - SQLite schema and task records (ephemeral, hydrated on-demand)
- `guides/` - Translation guides and exported per-locale references
- `scripts/` - Python orchestration tooling

## Tooling (unified CLI)

All locale tooling is one command: `python3 locales/scripts/i18n <group> <cmd>` (run `python3 locales/scripts/i18n --help` to discover it). The four groups are `content` (compile/decompile/hashes/add-field), `tasks` (create/next/update/export), `db` (init/migrate/query/export/import), and `validate` (pr/variables/glossary). The pnpm aliases `locales:sync` (= `content compile --all --merged`) and `locales:hashes` (= `content hashes`) remain for the build.

## Content Format

All locales (including English) use the same format in `content/{locale}/*.json`:

```json
{
  "web.COMMON.tagline": {
    "text": "Secure links that only work once"
  },
  "web.COMMON.broadcast": {
    "text": "",
    "skip": true,
    "note": "empty source"
  }
}
```

Fields:
- `text` - The translated text for this locale
- `skip` - (optional) Mark key as intentionally skipped
- `note` - (optional) Explanation for skip or other metadata
- `context` - (optional) Translation context from English source

English in `content/en/` serves as the authoritative source. When generating translation tasks, English text is looked up from there.

## Build Integration

Locale files are synced to `generated/locales/{locale}.json` for consumption by frontend and backend:

```bash
# Runs automatically on pnpm dev/build
pnpm run locales:sync

# Or directly
python3 locales/scripts/i18n content compile --all --merged
```

The sync script merges all content files for each locale into a single nested JSON file.

## Translation Rules

1. Edit files in `content/` - the source of truth
2. Use `en/` as reference - match the structure exactly
3. Preserve keys - only translate values
4. Keep placeholders intact: `{count}`, `{email}`, `{name}`

Security messages require special handling - see `guides/SECURITY-TRANSLATION-GUIDE.md`.

## Register check (run locally)

Catch politeness-level violations (e.g. formal forms in an informal-locked
locale) before review — same engine as the `validate-register` CI gate.

```bash
# 1. derive the resolved registers at the canonical pin (writes generated/i18n/)
locales/scripts/derive-governance.sh

# 2. check one locale's content (exit 0 = clean; 1 = lists each hit)
python3 .translation-rules/lib/resolver/lint_content.py \
  --resolved generated/i18n/.resolved/<locale>.json \
  --content-root . \
  "locales/content/<locale>/*.json"
```

## Testing

```bash
pnpm test                          # Run i18n validation tests
pnpm run type-check                # Check TypeScript types
pnpm run i18n:generate-types       # Regenerate type definitions
```

## Branch-per-Locale Workflow

After exporting translations, create isolated branches for review:

```bash
# Preview what would be created (default: dry-run)
locales/scripts/branch-per-locale.sh --changed

# Actually create branches
locales/scripts/branch-per-locale.sh --changed --execute

# Specific locales only
locales/scripts/branch-per-locale.sh ar bg ca_ES --execute
```

This creates one `i18n/update-{locale}` branch per locale off develop, each containing only that locale's content changes. Branches can be reviewed independently and merged separately.

### Reviewing Branches

Run `/d:review-locale-branches` to:
1. Validate variables across all branches (automated)
2. Launch parallel code-reviewer agents by language family
3. Consolidate findings for triage

#### Review vs Retrospective

Review = raw observation. Prose, no schema, human/agent-authored, lives in BASE_REVIEW_PATH/reviews/<date>-<time>/LOCALE.md. Answers "what did we see?". Can be per locale or cross-locale (e.g. GROUP_NAME.md, with the locales listed in the content). Cross-locale groups are arbitrary but can be by language family (in linguistic terms).

Retrospective = the decision a finding drives. Schema'd frontmatter, lifecycle-tracked (pending→applied), lives in BASE_RETRO_PATH/retrospectives/. Answers "what rule changes because of it, and is it done?"


## Translation Workflow

Prep (once, after English source changes)

1. Add/edit English source — new keys as bare {"text": "..."}, no hash. · edit locales/content/en/*.json · human/dev
2. Generate hashes — writes content_hash on en; seeds missing source_hash watermarks on every translation locale. · pnpm run locales:hashes (= content hashes) · human/dev (preview with :hashes:dry-run)
3. Compile to app format (optional for translating; needed for the app/types) — merges content/ → generated/. · pnpm run locales:sync (= content compile --all --merged) · human/dev, also auto-runs on pnpm dev/build

Database (once)

- Initialize the task DB before the first session — creates locales/db/tasks.db from schema.sql. · python3 locales/scripts/i18n db init · agent/dev
- Apply later schema updates to an existing DB — idempotent; does NOT create a missing DB (use init for that). · python3 locales/scripts/i18n db migrate · agent/dev

Session loop (per locale)

4. Generate/refresh tasks — walks en, groups sibling keys by level, writes translation_tasks rows. Re-run to pick up new English. With `--missing-only` (the catch-up path the drains use) it enqueues both **missing** keys and **stale** keys — translated, but the target's `source_hash` watermark no longer matches en's `content_hash` (English changed after translation). Each row snapshots the en `content_hash` per leaf so step 8's export can stamp the watermark. · python3 locales/scripts/i18n tasks create <locale> --missing-only · agent (run via Bash inside the session) — or orchestrated by /d:translate-parallel-agents for many locales
5. Check status / claim next task — serves the next pending level as a Key/English/target table. `--stats` also prints content-truth **coverage** (current / stale / missing / skipped vs en) — the "am I current?" signal that `0 pending` can't give, since a drained queue can still hide stale keys. · python3 locales/scripts/i18n tasks next <locale> --stats then --claim · agent
6. Propose → accept — assistant proposes; on A, writes the batch back to the DB. · python3 locales/scripts/i18n tasks update TASK_ID '{"key":"...",...}' · agent
7. Record glossary decisions (as needed) — the renderings you settled on for recurring domain/brand terms while translating in step 6 (e.g. "secret" → "sekreto"); persist them so later tasks and sessions reuse the same choice. See "Glossary" note below. · python3 locales/scripts/i18n db query "INSERT INTO glossary ..." · agent
8. Export to source of truth — SQLite → content/<locale>/, plus committable tables. · python3 locales/scripts/i18n tasks export <locale> + python3 locales/scripts/i18n db export · agent
9. Commit. · git add locales/content/<locale>/ … · human-approved, assistant runs after OK

Entry points (slash commands): /d:start-translation-session or /d:translate-parallel-agents orchestrate steps 4–8 across locales with background agents; the manual path is opening a session with @locales/TRANSLATION_PROTOCOL.md and claiming tasks one at a time.

Glossary (when & how): entries originate from the terminology choices made while translating in step 6 — there is no separate list that step 7 reads. Record one whenever you fix the target rendering of a recurring domain/brand term (secret, passphrase, burn, email, …) so the next task and the next session stay consistent. Two inputs shape the choice but are not the source of new rows: the locale's translator guide (curated in translation-rules and derived on demand into `generated/i18n/guides/for-translators/<locale>.md`) holds prior agreed terms (read in step 0), and QC reviews surface good renderings after the fact (see TRANSLATION_PROTOCOL.md → "Glossary Updates from QC"), written via the same INSERT INTO glossary. Drain boundary: the parallel drain workflows (/d:translate-parallel-agents, /d:start-translation-session orchestration, and the translate-parallel-locales* workflows) do NOT let their agents write the shared glossary table directly — one-writer-per-locale keeps the DB safe, so agents translate, save, and verify only. Instead each agent **reports candidate `term → rendering` pairs in its final message**, and the orchestrator reviews and INSERTs the accepted ones after the drain (plus the standing QC path). To audit an agent-drained locale against the bound renderings it was supposed to honor, run `python3 locales/scripts/i18n validate glossary <locale>` (advisory; needs governance derived via `derive-governance.sh`).

Export (step 8 — per-locale vs once): `tasks export` takes ONE locale and writes that locale's completed rows to `content/<locale>/`; run it once per finished locale. `db export` is locale-independent — it dumps the committable tables (glossary, session_log, translation_issues) to `db/*.sql` and regenerates `checksums.sha256` — so run it once after the per-locale loop, not inside it. Export only fully drained locales (`python3 locales/scripts/i18n tasks next <locale> --stats` shows `pending: 0`); partial locales would write half-translated content. For a batch (substitute the locales you finished this session):

```bash
# Change directory to the repo root from anywhere inside it.
cd "$(git rev-parse --show-toplevel)"
for loc in de_AT es fr fr_CA ja nl; do
  python3 locales/scripts/i18n tasks export "$loc"
done
python3 locales/scripts/i18n db export    # once, not per-locale
```

Then stage the exported content dirs plus `locales/db/*.sql` for step 9.

Staleness (translated, but English changed after): `tasks create --missing-only` enqueues stale keys alongside missing ones. A key is stale when its target `source_hash` no longer equals en's current `content_hash`; an absent watermark is treated as current (it can't prove drift), so this never mass-requeues un-watermarked legacy keys. Each task snapshots the en `content_hash` per leaf at creation (`source_hashes_json`), and `tasks export` stamps that snapshot onto the target key's `source_hash` — advancing the watermark so the re-translation is marked current, and giving newly created keys a truthful watermark immediately instead of waiting for `content hashes` to seed the *current* en hash (which would mislabel a key that drifted in the interim as fresh). `tasks next <locale> --stats` shows the current/stale/missing/skipped split straight from content, so `0 pending` is no longer the only (and misleading) "done" signal.
