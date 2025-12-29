# Analysis: feature-incoming.json

## File Overview

The `feature-incoming.json` file contains 34 keys under a single `incoming` namespace. This file handles the "Send a Secret" feature, which allows users to send secure messages to predefined recipients (typically support teams).

### Key Categories Present

1. **Page Meta** (2 keys): `page_title`, `page_description`
2. **Loading/Error States** (4 keys): `loading_config`, `config_error_title`, `feature_disabled_title`, `feature_disabled_description`
3. **Form Labels** (5 keys): `memo_label`, `recipient_label`, `secret_content_label`, and related
4. **Form Placeholders** (3 keys): `memo_placeholder`, `recipient_placeholder`, `secret_content_placeholder`
5. **Form Hints/Help** (4 keys): `memo_hint`, `recipient_hint`, `secret_content_hint`, `recipient_aria_label`
6. **Validation/Feedback** (1 key): `no_recipients_available`
7. **Button States** (6 keys): `submit_button`, `submit_secret`, `submitting_button`, `submitting`, `reset_button`, `reset_form`
8. **Success Flow** (7 keys): `success_title`, `success_description`, `reference_id`, `success_info_title`, `success_info_description`, `create_another`, `end_of_experience_suggestion`
9. **Marketing/Taglines** (2 keys): `tagline1`, `tagline2`

---

## Potentially Misplaced Keys

### Keys That Duplicate `_common.json` Patterns

| Key | Current Location | Recommended Destination | Rationale |
|-----|------------------|------------------------|-----------|
| `loading_config` | `incoming` | `_common.json` (`web.COMMON.loading`) | Already have `loading` and `loading_ellipses` in common |
| `submitting` | `incoming` | `_common.json` (`web.COMMON.submitting`) | Already exists in common: `submitting` |

### Keys That Follow Different Patterns

| Key | Issue | Recommendation |
|-----|-------|----------------|
| `submit_button` / `submit_secret` | Duplicates - both mean "Send Secret" | Consolidate to single key |
| `submitting_button` / `submitting` | Duplicates - both mean "Sending..." | Consolidate to single key |
| `reset_button` / `reset_form` | Duplicates - both mean "Clear Form" | Consolidate to single key |

---

## Suggested Hierarchy Improvements

### Current Structure (Flat)
```json
{
  "incoming": {
    "page_title": "...",
    "memo_label": "...",
    "memo_placeholder": "...",
    "submit_button": "...",
    "success_title": "..."
  }
}
```

### Recommended Structure (Nested)
```json
{
  "incoming": {
    "page": {
      "title": "Send a Secret",
      "description": "Share sensitive information securely with our support team"
    },
    "states": {
      "loading": "Loading...",
      "submitting": "Sending...",
      "error": {
        "config_failed": "Failed to load configuration",
        "feature_disabled": {
          "title": "Feature Not Available",
          "description": "This feature is currently disabled. Please contact support for assistance."
        }
      }
    },
    "form": {
      "memo": {
        "label": "Memo",
        "placeholder": "Brief description (e.g., Password reset request)",
        "hint": "Help us route your message to the right person"
      },
      "recipient": {
        "label": "Send to",
        "placeholder": "Select a recipient",
        "hint": "Choose who will receive this secure message",
        "aria_label": "Select a recipient for this secret",
        "no_recipients": "No recipients are available"
      },
      "secret": {
        "label": "Secret Information",
        "placeholder": "Paste sensitive information here (passwords, keys, etc.)",
        "hint": "This information will be encrypted and only viewable once"
      }
    },
    "actions": {
      "submit": "Send Secret",
      "reset": "Clear Form",
      "create_another": "Send Another Secret"
    },
    "success": {
      "title": "Sent Successfully",
      "description": "Your secure message has been delivered.",
      "reference_id": "Reference ID",
      "info": {
        "title": "What happens next?",
        "description": "The recipient will be able to view this secret only once. After they view it, the secret will be permanently deleted."
      },
      "receipt_suggestion": "Save your <a href='{receiptUrl}'>receipt</a> for your records."
    },
    "taglines": {
      "primary": "Share sensitive information securely",
      "secondary": "Keep passwords and private data out of email and chat logs"
    }
  }
}
```

---

## New File Suggestions

No new files are warranted. The `feature-incoming.json` file is appropriately scoped to a single, cohesive feature. The key count (34) is reasonable for a feature-specific locale file.

---

## Specific Recommendations

### 1. Remove Duplicate Keys

The following pairs should be consolidated (keep one, remove the other):

- `submit_button` and `submit_secret` (keep `submit`)
- `submitting_button` and `submitting` (keep `submitting`)
- `reset_button` and `reset_form` (keep `reset`)

### 2. Align with Common Patterns

The file uses `snake_case` consistently, which matches `feature-secrets.json` but differs from `_common.json` which uses `camelCase` in some sections (e.g., `privacyOptions`). Consider standardizing.

### 3. Consider Moving Taglines

The taglines (`tagline1`, `tagline2`) could potentially move to `homepage.json` if they're displayed on the homepage, or remain here if they're specific to the incoming feature page.

### 4. ARIA Labels

The `recipient_aria_label` key follows good accessibility practice. Consider adding similar ARIA labels for other form fields:
- `memo_aria_label`
- `secret_content_aria_label`

---

## Consistency Check with Other Files

| Aspect | feature-incoming.json | Other feature-*.json | Status |
|--------|----------------------|---------------------|--------|
| Root namespace | `incoming` | `domains`, `feedback`, etc. | Consistent |
| Nesting depth | 1 level | 1-2 levels | OK |
| Key naming | snake_case | Mixed | Needs review |
| Duplicate removal | Has duplicates | Varies | Needs cleanup |

---

## Priority Actions

1. **High**: Remove duplicate button text keys (6 keys to consolidate to 3)
2. **Medium**: Add hierarchical grouping for form fields
3. **Low**: Add missing ARIA labels for accessibility
4. **Low**: Consider moving taglines if used elsewhere
