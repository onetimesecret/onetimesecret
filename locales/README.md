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
python locales/scripts/sync_to_src.py --all --merged
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
