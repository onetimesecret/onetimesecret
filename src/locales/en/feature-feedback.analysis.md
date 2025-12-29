# Locale Analysis: feature-feedback.json

## File Overview

**Path:** `src/locales/en/feature-feedback.json`
**Namespace:** `web.feedback`
**Total Keys:** 14

### Key Categories

| Category | Count | Keys |
|----------|-------|------|
| UI Labels | 4 | `your-feedback`, `share-your-feedback`, `enter-your-feedback`, `help-us-improve` |
| Modal Controls | 2 | `close-feedback-modal`, `open-feedback-form` |
| Personal/Branding | 2 | `delano-mandelbaum`, `delano` |
| Marketing Copy | 4 | `all-feedback-welcome`, `thanks-for-helping-onetime-secret-improve-it-mea`, `weve-built-this-tool-to-help-you-share-sensitive`, `hey-there-thanks-for-stopping-by-our-feedback-pa` |
| Headers | 1 | `a-note-from-delano-founder-of-onetime-secret` |
| Placeholder | 1 | `help-content-goes-here` |

---

## Potentially Misplaced Keys

| Key | Current Location | Recommended Destination | Rationale |
|-----|-----------------|------------------------|-----------|
| `delano-mandelbaum` | `feature-feedback.json` | `_common.json` or new `about.json` | Personal names are not feedback-specific; could be reused on About page, footer credits, etc. |
| `delano` | `feature-feedback.json` | `_common.json` or new `about.json` | Same as above |
| `help-content-goes-here` | `feature-feedback.json` | Remove or move to `layout.json` | Appears to be placeholder/dev content; if kept, belongs in general layout |

---

## Suggested Hierarchy Improvements

### 1. Group by Function

The current flat structure mixes UI controls, content, and labels. Consider:

```json
{
  "web": {
    "feedback": {
      "labels": {
        "your-feedback": "Your feedback",
        "share-your-feedback": "Share your feedback",
        "enter-your-feedback": "Enter your feedback",
        "help-us-improve": "Help us improve"
      },
      "modal": {
        "close": "Close feedback modal",
        "open": "Open feedback form"
      },
      "content": {
        "welcome": "All feedback welcome!",
        "thanks": "Thanks for helping Onetime Secret improve...",
        "intro": "We've built this tool to help you...",
        "greeting": "Hey there, thanks for stopping by..."
      },
      "founder-note": {
        "heading": "A note from Delano, founder of Onetime Secret"
      }
    }
  }
}
```

### 2. Improve Key Naming

| Current Key | Issue | Suggested Key |
|-------------|-------|---------------|
| `thanks-for-helping-onetime-secret-improve-it-mea` | Truncated, unclear | `thank-you-message` |
| `weve-built-this-tool-to-help-you-share-sensitive` | Truncated | `mission-statement` |
| `hey-there-thanks-for-stopping-by-our-feedback-pa` | Truncated | `welcome-message` |
| `a-note-from-delano-founder-of-onetime-secret` | Overly long | `founder-note-heading` |

### 3. Accessibility Improvements

Modal control keys should follow ARIA patterns:

```json
{
  "modal": {
    "aria-close": "Close feedback modal",
    "aria-open": "Open feedback form",
    "title": "Your feedback"
  }
}
```

---

## New File Suggestions

### Consider: `about.json` or `company.json`

If founder-related content grows, extract to dedicated file:

```json
{
  "web": {
    "about": {
      "founder": {
        "name": "Delano Mandelbaum",
        "short-name": "Delano",
        "note-heading": "A note from Delano, founder of Onetime Secret"
      }
    }
  }
}
```

**Recommendation:** Not urgent given current size. Monitor for growth.

---

## Summary

The file is relatively well-scoped to feedback functionality. Main improvements:

1. **Remove/relocate placeholder key** (`help-content-goes-here`)
2. **Consider moving founder names** to shared location if used elsewhere
3. **Improve truncated key names** for clarity
4. **Optional:** Add hierarchy grouping if file grows

**Priority:** Low - File is small and focused. Address key naming in next refactor cycle.
