# Translation Service

Orchestration tooling for managing locale translations. Tracks translation tasks in SQLite, coordinates batch processing, and maintains translation quality.

## Structure

- `content/` - Version-controlled source of truth for all locales (flat keys)
- `db/` - SQLite schema and task records (ephemeral, hydrated on-demand)
- `guides/` - Translation guides and exported per-locale references
- `scripts/` - Python orchestration tooling

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
python locales/scripts/build/compile.py --all --merged
```

The sync script merges all content files for each locale into a single nested JSON file.

## Translation Rules

1. Edit files in `content/` - the source of truth
2. Use `en/` as reference - match the structure exactly
3. Preserve keys - only translate values
4. Keep placeholders intact: `{count}`, `{email}`, `{name}`

Security messages require special handling - see `guides/SECURITY-TRANSLATION-GUIDE.md`.

## Testing

```bash
pnpm test                          # Run i18n validation tests
pnpm run type-check                # Check TypeScript types
pnpm run i18n:generate-types       # Regenerate type definitions
```

## Translation Workflow

Prep (once, after English source changes)

1. Add/edit English source — new keys as bare {"text": "..."}, no hash. · edit locales/content/en/*.json · human/dev
2. Generate hashes — writes content_hash on en; seeds missing source_hash watermarks on every translation locale. · pnpm run locales:hashes (= add_hashes.py) · human/dev (preview with :hashes:dry-run)
3. Compile to app format (optional for translating; needed for the app/types) — merges content/ → generated/. · pnpm run locales:sync (= compile.py --all --merged) · human/dev, also auto-runs on pnpm dev/build

Session loop (per locale)

4. Generate/refresh tasks — walks en, groups sibling keys by level, writes translation_tasks rows. Re-run to pick up new English. · python locales/scripts/tasks/create.py <locale> · agent (run via Bash inside the session) — or orchestrated by /d:translate-parallel-agents for many locales
5. Check status / claim next task — serves the next pending level as a Key/English/target table. · tasks/next.py <locale> --stats then --claim · agent
6. Propose → accept — assistant proposes; on A, writes the batch back to the DB. · tasks/update.py TASK_ID '{"key":"...",...}' · agent
7. Record glossary decisions (as needed). · store.py query "INSERT INTO glossary ..." · agent
8. Export to source of truth — SQLite → content/<locale>/, plus committable tables. · migrate/export.py <locale> + store.py export · agent
9. Commit. · git add locales/content/<locale>/ … · human-approved, assistant runs after OK

Entry points (slash commands): /d:start-translation-session or /d:translate-parallel-agents orchestrate steps 4–8 across locales with background agents; the manual path is opening a session with @locales/TRANSLATION_PROTOCOL.md and claiming tasks one at a time.

Live gap (from this session): none of these steps create tasks for stale keys (translated but English changed) — create.py is target-blind, and harmonize.py would strip source_hash. That's the change we were about to make to create.py.
