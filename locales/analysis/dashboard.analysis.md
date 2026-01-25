# Dashboard Locale Key Analysis

**File**: `/Users/d/Projects/opensource/onetime/onetimesecret/src/locales/en/dashboard.json`
**Date**: 2025-12-27

## File Overview

The `dashboard.json` file contains a small set of keys (6 total) under `web.dashboard.*`. These keys fall into two categories:

| Category | Keys | Count |
|----------|------|-------|
| Status Labels | `title_received`, `title_not_received` | 2 |
| Empty State | `title_no_recent_secrets`, `get-started-by-creating-your-first-secret` | 2 |
| Error Handling | `fetch_error_title`, `fetch_error_description` | 2 |

## Potentially Misplaced Keys

### 1. Status Labels (Recommend: `_common.json`)

| Key | Current Location | Recommended Location | Rationale |
|-----|------------------|---------------------|-----------|
| `title_received` | `web.dashboard` | `web.STATUS` in `_common.json` | Status labels like "Received" are already defined in `_common.json` under `web.STATUS.received`. This creates duplication. |
| `title_not_received` | `web.dashboard` | `web.STATUS` in `_common.json` | Same as above; `_common.json` already has `web.COMMON.not-received`. |

**Evidence of duplication**:
- `_common.json` line 37: `"received": "Received"`
- `_common.json` line 130: `"not-received": "NOT RECEIVED"`
- `_common.json` line 223: `"received": "Received"` (under STATUS)

### 2. Error Messages (Recommend: `error-pages.json`)

| Key | Current Location | Recommended Location | Rationale |
|-----|------------------|---------------------|-----------|
| `fetch_error_title` | `web.dashboard` | `web.errors` in `error-pages.json` | All error-related strings should be centralized in `error-pages.json` for consistency. |
| `fetch_error_description` | `web.dashboard` | `web.errors` in `error-pages.json` | Same as above. Error handling patterns should be consistent across the app. |

### 3. Empty State Strings (Recommend: Keep or Move to Feature)

| Key | Current Location | Recommended Location | Rationale |
|-----|------------------|---------------------|-----------|
| `title_no_recent_secrets` | `web.dashboard` | `web.LABELS` in `_common.json` | Could be generalized as it relates to the "Recent Secrets" feature which has labels in `_common.json` (line 206). |
| `get-started-by-creating-your-first-secret` | `web.dashboard` | `feature-secrets.json` or keep | This is onboarding copy; could stay if dashboard has more unique content. |

## Hierarchy Improvements

### Current Structure
```json
{
  "web": {
    "dashboard": {
      "title_received": "Received",
      "title_not_received": "Not Received",
      "title_no_recent_secrets": "No recent secrets",
      "get-started-by-creating-your-first-secret": "Get started...",
      "fetch_error_title": "Unable to load data",
      "fetch_error_description": "There was a problem..."
    }
  }
}
```

### Recommended Structure

**Option A: Consolidate into existing files (eliminate dashboard.json)**

Move keys to their appropriate homes:

1. **`_common.json`** additions:
```json
{
  "web": {
    "STATUS": {
      "title_received": "Received",
      "title_not_received": "Not Received"
    },
    "LABELS": {
      "no_recent_secrets": "No recent secrets"
    }
  }
}
```

2. **`error-pages.json`** additions:
```json
{
  "web": {
    "errors": {
      "fetch_error_title": "Unable to load data",
      "fetch_error_description": "There was a problem loading your data. Please try again."
    }
  }
}
```

3. **`feature-secrets.json`** additions:
```json
{
  "web": {
    "secrets": {
      "get_started_first_secret": "Get started by creating your first secret."
    }
  }
}
```

**Option B: Keep dashboard.json but restructure**

If the dashboard will grow with more unique content:

```json
{
  "web": {
    "dashboard": {
      "status": {
        "received": "Received",
        "not_received": "Not Received"
      },
      "empty_state": {
        "title": "No recent secrets",
        "description": "Get started by creating your first secret."
      },
      "errors": {
        "fetch_title": "Unable to load data",
        "fetch_description": "There was a problem loading your data. Please try again."
      }
    }
  }
}
```

## Key Naming Inconsistencies

| Issue | Examples | Recommendation |
|-------|----------|----------------|
| Mixed case conventions | `title_received` vs `title_no_recent_secrets` | Use consistent snake_case throughout |
| Verbose kebab-case | `get-started-by-creating-your-first-secret` | Use shorter, semantic keys like `empty_state_cta` |
| Title prefix redundancy | `title_received`, `title_not_received`, `title_no_recent_secrets` | Drop `title_` prefix if not serving a purpose |

## Recommendations Summary

1. **Eliminate `dashboard.json`** - The file is too small to justify its own file. All 6 keys have better homes in existing files.

2. **Migration Plan**:
   - Status labels -> `_common.json` under `web.STATUS`
   - Error messages -> `error-pages.json` under `web.errors`
   - Empty state -> `feature-secrets.json` under `web.secrets` (it relates to the secrets feature)

3. **No new files needed** - The existing file structure is comprehensive enough.

4. **If keeping dashboard.json**, it should only contain:
   - Dashboard-specific UI chrome
   - Dashboard-specific empty states
   - Dashboard-specific navigation

   Generic statuses and errors belong in common/shared files.

## Cross-Reference Notes

Related keys that already exist elsewhere:
- `_common.json:206` - `"title_recent_secrets": "Recent Secrets"`
- `_common.json:210` - `"caption_recent_secrets": "Secrets links created in this session"`
- `_common.json:297` - `"dashboard": "Dashboard"` (under TITLES)
- `_common.json:298` - `"recent": "Recent Secrets"` (under TITLES)
