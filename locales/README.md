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
