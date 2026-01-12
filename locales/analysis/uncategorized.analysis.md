# Uncategorized Locale File Analysis

**File:** `/src/locales/en/uncategorized.json`
**Keys analyzed:** 4
**Status:** All keys are duplicates - this file can be safely emptied

## File Overview

This file contains keys that were never properly categorized during initial locale setup. It has a flat structure with no hierarchy:

```json
{
  "continue": "Continue",
  "back": "Back",
  "received": "RECEIVED",
  "stats": "Stats"
}
```

## Key-by-Key Analysis

### 1. `continue`
- **Current value:** `"Continue"`
- **Already exists in:** `_common.json` at `web.COMMON.continue` and `web.COMMON.word_continue`
- **Recommendation:** DELETE - duplicate of existing key

### 2. `back`
- **Current value:** `"Back"`
- **Already exists in:** `_common.json` at `web.COMMON.back`
- **Recommendation:** DELETE - duplicate of existing key

### 3. `received`
- **Current value:** `"RECEIVED"` (uppercase)
- **Already exists in:**
  - `_common.json` at `web.COMMON.received` (title case: "Received")
  - `_common.json` at `web.COMMON.word_received` (lowercase: "received")
  - `_common.json` at `web.STATUS.received` ("Received")
- **Recommendation:** DELETE - if uppercase variant is needed, it should be handled via CSS text-transform or a dedicated status display key in `_common.json`

### 4. `stats`
- **Current value:** `"Stats"`
- **Not found in other files**
- **Possible destinations:**
  - `_common.json` at `web.LABELS.stats` - if used as a general label
  - `dashboard.json` at `web.dashboard.stats` - if specific to dashboard
  - `colonel.json` - if used in admin statistics views
- **Recommendation:** MOVE to `_common.json` at `web.LABELS.stats`

## Summary of Recommendations

| Key | Action | Destination |
|-----|--------|-------------|
| `continue` | DELETE | Already in `_common.json` |
| `back` | DELETE | Already in `_common.json` |
| `received` | DELETE | Already in `_common.json` |
| `stats` | MOVE | `_common.json` -> `web.LABELS.stats` |

## Suggested Changes

### 1. Add to `_common.json`

```json
{
  "web": {
    "LABELS": {
      "stats": "Stats"
    }
  }
}
```

### 2. Empty `uncategorized.json`

After moving `stats`, this file should become:

```json
{}
```

## Code Migration Required

Before deleting/moving these keys, search the codebase for usages:

```bash
# Find all usages of these flat keys
grep -r "\"continue\"" --include="*.vue" --include="*.ts" src/
grep -r "\"back\"" --include="*.vue" --include="*.ts" src/
grep -r "\"received\"" --include="*.vue" --include="*.ts" src/
grep -r "\"stats\"" --include="*.vue" --include="*.ts" src/
```

Any components using the flat keys (e.g., `$t('continue')`) should be updated to use the proper hierarchical keys (e.g., `$t('web.COMMON.continue')`).

## Hierarchy Improvements

No hierarchy improvements needed for this file since all keys should be migrated elsewhere. The file should ideally remain empty or be removed entirely once all keys are properly categorized.

## New File Suggestions

None needed. All 4 keys belong in existing files.
