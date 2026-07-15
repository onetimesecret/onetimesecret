# Translation Service

Locale translations tracked as SQLite tasks, translated by agents, exported back to version-controlled content. All tooling is one CLI: `python3 locales/scripts/i18n <group> <cmd>` (`--help` at any level; groups: `content`, `tasks`, `db`, `validate`).

## Layout

- `content/` — source of truth, all locales, flat keys (`content/en/` is the authoritative source text)
- `db/` — SQLite task DB (ephemeral working state; hydrated on demand, real only after export)
- `guides/` — static shared guides (security, UX); per-locale guides are derived into gitignored `generated/i18n/` by `scripts/derive-governance.sh`, never committed here
- `scripts/` — orchestration tooling
- `generated/locales/` — build output the app consumes (never edit; `pnpm run locales:sync`)

## The workflow

Run from the repo root. This is the one repeatable path for updating all locales after English changes:

```bash
# 1. Hash the English source (new/edited en keys have no content_hash yet)
pnpm run locales:hashes           # dry-run: shows what would change
pnpm run locales:hashes:apply     # writes hashes + seeds watermarks

# 2. Ensure the task DB exists and is on the current schema
python3 locales/scripts/i18n db init      # no-op if DB exists
python3 locales/scripts/i18n db migrate

# 3. Drain all locales with parallel agents (creates tasks --missing-only,
#    translates, verifies; agents report glossary candidates, they don't write them)
/i18n:translate-parallel-agents        # installed from locales/slash_commands/

# 4. Export every fully drained locale, then the shared tables once
locales/scripts/export-all.sh                              # preview (dry-run)
locales/scripts/export-all.sh --execute                   # export drained locales + db export
# Skips any locale with pending > 0; run per-locale manually if you need finer control:
#   python3 locales/scripts/i18n tasks export <locale>
#   python3 locales/scripts/i18n db export

# 5. Commit content + db tables, then split into review branches
git add locales/content/ locales/db/*.sql
locales/scripts/branch-per-locale.sh --changed --execute   # one i18n/update-{locale} branch each
locales/scripts/review-locale-branches.sh validate         # deterministic checks; full agent review: locales/slash_commands/review-locale-branches.md
```

Two rules that bite:

- **`0 pending` ≠ current.** A drained queue can hide stale keys (English changed after translation). Trust the `--stats` coverage line (current/stale/missing/skipped), not the queue.
- **Never hand-author hashes.** New en keys are bare `{"text": "..."}`; `locales:hashes:apply` does the rest.

## Content format

Every locale uses the same flat format in `content/{locale}/*.json`:

```json
{
  "web.COMMON.tagline": { "text": "Secure links that only work once" },
  "web.COMMON.broadcast": { "text": "", "skip": true, "note": "empty source" }
}
```

Preserve keys, translate only `text`, keep placeholders (`{count}`, `{email}`) intact.

## Full documentation

- [TRANSLATION_PROTOCOL.md](TRANSLATION_PROTOCOL.md) — session workflow in detail: task model, staleness & watermarks, glossary, export rules, QC protocol, branch review
- [AGENT_TRANSLATION_PROTOCOL.md](AGENT_TRANSLATION_PROTOCOL.md) — rules the parallel drain agents follow (governance derivation, per-task cycle, glossary boundary, register check)
- [BATCH_OPERATIONS.md](BATCH_OPERATIONS.md) — rebasing, PR feedback, and merging the per-locale branches
- `guides/SECURITY-TRANSLATION-GUIDE.md` — required handling for security-sensitive messages
