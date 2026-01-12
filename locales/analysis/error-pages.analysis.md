# Locale Key Analysis: error-pages.json

## File Overview

**Path:** `src/locales/en/error-pages.json`
**Structure:** `web.errors.*` (flat key hierarchy)
**Total Keys:** 19

### Current Key Categories

The file contains error-related strings that can be grouped into these functional categories:

| Category | Count | Description |
|----------|-------|-------------|
| 404 Error Page | 4 | Page not found messaging |
| Secret Unavailable | 4 | Expired/viewed secret explanations |
| General Errors | 3 | Unexpected error states |
| Dismissal Actions | 4 | Warning/notification dismiss buttons |
| Data Format Errors | 1 | Data loading issues |
| Guidance/Instructions | 3 | What to do next |

---

## Potentially Misplaced Keys

### 1. Dismissal Action Keys

These are generic UI actions that belong in `_common.json` under `web.LABELS`:

| Key | Current Location | Recommended Destination |
|-----|------------------|------------------------|
| `warning-dismissed` | `error-pages.json` | `_common.json` -> `web.LABELS.warning_dismissed` |
| `dismiss-truncation-warning` | `error-pages.json` | `_common.json` -> `web.LABELS.dismiss_truncation_warning` |
| `dismiss-warning` | `error-pages.json` | `_common.json` -> `web.LABELS.dismiss_warning` |
| `dismiss-notification` | `error-pages.json` | `_common.json` -> `web.LABELS.dismiss_notification` |

**Rationale:** `_common.json` already has `web.LABELS.dismiss` ("Dismiss"). These are variations that should be co-located for consistency and reusability across components.

### 2. Secret-Specific Error Content

These explain why secrets are unavailable and belong with secret-related content:

| Key | Current Location | Recommended Destination |
|-----|------------------|------------------------|
| `why-is-this-secret-unavailable` | `error-pages.json` | `feature-secrets.json` -> `web.secrets.errors.why_unavailable` |
| `secrets-are-designed-to-be-viewed-only-once` | `error-pages.json` | `feature-secrets.json` -> `web.secrets.errors.viewed_once_explanation` |
| `information-shared-through-our-service-can-only-` | `error-pages.json` | `feature-secrets.json` -> `web.secrets.errors.one_time_access_explanation` |

**Rationale:** `feature-secrets.json` already contains secret-specific messaging in `web.secrets` and `web.private` namespaces. These error explanations are domain-specific to the secret viewing flow.

### 3. Navigation/CTA Keys

| Key | Current Location | Recommended Destination |
|-----|------------------|------------------------|
| `go-share-a-secret` | `error-pages.json` | `_common.json` -> `web.COMMON.go_share_secret` or `web.LABELS.go_share_secret` |

**Rationale:** This is a call-to-action that may be reused across multiple error states and landing pages. `_common.json` already has `share_a_secret`.

---

## Suggested Hierarchy Improvements

### Current Structure (Flat)

```
web.errors.why-is-this-secret-unavailable
web.errors.404-page-not-found
web.errors.dismiss-warning
web.errors.were-sorry-but-an-unexpected-error-occurred-whil
```

### Proposed Structure (Categorized)

```json
{
  "web": {
    "errors": {
      "pages": {
        "404": {
          "title": "404 - Page Not Found",
          "message": "The page you're looking for doesn't exist or has been moved.",
          "alt_message": "Oops! The page you are looking for doesn't exist or has been moved."
        },
        "500": {
          "title": "Something went wrong",
          "message": "We're sorry, but an unexpected error occurred..."
        }
      },
      "data": {
        "format_issues": "Unable to load data due to data format issues..."
      },
      "guidance": {
        "contact_sender": "Contact the person who sent you this link...",
        "follow_up": "If you're unsure what to do next, please follow up..."
      }
    }
  }
}
```

### Key Naming Issues

Several keys use truncated or auto-generated names that reduce readability:

| Current Key | Suggested Improvement |
|-------------|----------------------|
| `404-page-not-found-0` | Remove duplicate (keep `404-page-not-found`) |
| `were-sorry-but-an-unexpected-error-occurred-whil` | `unexpected_error_message` |
| `oops-the-page-you-are-looking-for-doesnt-exist-o` | `page_not_found_message` |
| `information-shared-through-our-service-can-only-` | `one_time_access_explanation` |
| `the-page-youre-looking-for-doesnt-exist-or-has-b` | `page_moved_message` |
| `if-youre-unsure-what-to-do-next-please-follow-up` | `follow_up_guidance` |
| `contact-the-person-who-sent-you-this-link` | `contact_sender_guidance` |
| `t-web-common-oops-something-went-wrong` | `oops_something_went_wrong` |
| `t-web-common-oops-404` | `oops_404` |
| `unable-to-load-data-due-to-data-format-issues-pl` | `data_format_error` |

---

## Duplicate/Redundant Keys

| Keys | Issue |
|------|-------|
| `404-page-not-found-0` and `404-page-not-found` | Identical content, different keys |
| `oops-the-page-you-are-looking-for-doesnt-exist-o` and `the-page-youre-looking-for-doesnt-exist-or-has-b` | Near-duplicate 404 messages |

**Recommendation:** Consolidate to single keys with clear naming.

---

## New File Suggestions

### Option A: Keep Consolidated (Recommended)

Keep error content in `error-pages.json` but with improved hierarchy. Error pages are a distinct UI concern that warrants its own file.

### Option B: Merge into `_common.json`

If the project prefers minimal files, the HTTP error pages section could move to `_common.json` under:
```
web.ERRORS.http.404.*
web.ERRORS.http.500.*
```

However, this would make `_common.json` even larger (already 346 lines).

---

## Summary of Recommended Actions

1. **Move 4 dismissal keys** to `_common.json` under `web.LABELS`
2. **Move 3 secret-specific error keys** to `feature-secrets.json` under `web.secrets.errors`
3. **Move 1 CTA key** (`go-share-a-secret`) to `_common.json`
4. **Remove 1 duplicate key** (`404-page-not-found-0`)
5. **Rename truncated keys** to semantic names
6. **Restructure remaining keys** into `pages.404`, `pages.500`, `data`, `guidance` sub-categories

### Keys to Remain in error-pages.json (After Cleanup)

- 404 page title and messages
- 500/unexpected error messages
- Data format error message
- User guidance for error recovery
- Secret unavailable explanation (if not moved to feature-secrets.json)

### Final Key Count Estimate

After reorganization:
- `error-pages.json`: ~8-10 keys (HTTP error pages only)
- Keys moved to `_common.json`: 5
- Keys moved to `feature-secrets.json`: 3
- Keys removed (duplicates): 1-2
