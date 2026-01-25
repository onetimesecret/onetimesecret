# Feature-Secrets Locale File Analysis

**File**: `/Users/d/Projects/opensource/onetime/onetimesecret/src/locales/en/feature-secrets.json`
**Date**: 2025-12-27

## File Overview

The file contains 3 top-level categories under `web`:

| Category | Key Count | Purpose |
|----------|-----------|---------|
| `secrets` | 47 keys | Secret creation, viewing, and general UI |
| `private` | 34 keys | Private/metadata view for secret owners |
| `shared` | 8 keys | Shared/recipient view of secrets |

## Current Key Structure Analysis

### 1. `web.secrets` (Lines 3-51)

Mixed concerns in this namespace:

| Sub-category | Keys | Examples |
|--------------|------|----------|
| **Form/Input** | 8 | `enterPassphrase`, `passphraseMinimumLength`, `selectDuration` |
| **Actions** | 4 | `create-a-secret`, `view-secret-message`, `hide-secret-message` |
| **Status/Display** | 10 | `content-hidden`, `secret-confirmation`, `permanently-deleted` |
| **Onboarding/FAQ** | 6 | `what-is-this`, `is-it-secure`, `what-happens-next` |
| **Timestamps** | 3 | `viewed-on-record-received`, `deleted-on-record-burned`, `expiresIn` |
| **Clipboard** | 1 | `secret-content-copied-to-clipboard` |
| **Misc UI** | 15 | Various labels and messages |

### 2. `web.private` (Lines 52-87)

Owner/metadata view with mixed concerns:

| Sub-category | Keys | Examples |
|--------------|------|----------|
| **Status messages** | 7 | `burned`, `viewed`, `destroyed`, `created_success` |
| **FAQ content** | 8 | `whats-the-burn-feature`, `how-does-secret-expiration-work` |
| **Security features** | 5 | `one-time-access`, `passphrase-protection`, `core-security-features` |
| **Actions** | 3 | `view_receipt`, `send-feedback` |
| **UI labels** | 11 | `pretext`, `requires_passphrase`, `expires-in-record-natural_expiration` |

### 3. `web.shared` (Lines 88-99)

Recipient experience - relatively clean:

| Sub-category | Keys | Examples |
|--------------|------|----------|
| **Messages** | 8 | `requires_passphrase`, `your_secret_message`, `reply_with_secret` |

---

## Potentially Misplaced Keys

### Keys That Should Move to `_common.json`

| Current Key | Reason | Suggested Location |
|-------------|--------|-------------------|
| `web.private.send-feedback` | Generic action, not secret-specific | `web.LABELS.send_feedback` |
| `web.private.have-more-questions-visit-our` | Generic help text | `web.COMMON.have_more_questions` |
| `web.secrets.you-can-safely-close-this-tab` | Generic UI instruction | `web.COMMON.you_can_close_window` |

### Keys That Should Move to `feature-feedback.json`

| Current Key | Reason |
|-------------|--------|
| `web.private.send-feedback` | Belongs with feedback feature |

### Keys That Should Move to `dashboard.json`

| Current Key | Reason |
|-------------|--------|
| `web.secrets.theyll-appear-here-once-youve-shared-them` | Dashboard empty state message |
| `web.secrets.recent-secrets-count` | Dashboard metric label |

### Duplicate/Overlapping Keys

| Key in feature-secrets.json | Duplicate/Similar in _common.json |
|-----------------------------|-----------------------------------|
| `web.secrets.secret-link` | `web.LABELS.secret_link` |
| `web.private.burned` | `web.STATUS.burned` |
| `web.private.viewed` | `web.STATUS.viewed` |
| `web.private.destroyed` | `web.STATUS.destroyed` |
| `web.shared.secret_was_truncated` | `web.COMMON.secret_was_truncated` |

---

## Suggested Hierarchy Improvements

### 1. Restructure `web.secrets` into sub-namespaces

```json
{
  "web": {
    "secrets": {
      "form": {
        "enterPassphrase": "...",
        "passphraseMinimumLength": "...",
        "passphraseComplexityRequired": "...",
        "selectDuration": "...",
        "privacyOptions": "...",
        "enterSecretContent": "...",
        "charCount": "..."
      },
      "actions": {
        "create": "...",
        "view": "...",
        "hide": "...",
        "copyToClipboard": "..."
      },
      "status": {
        "hidden": "...",
        "deleted": "...",
        "viewed": "...",
        "expired": "...",
        "notAvailable": "..."
      },
      "timestamps": {
        "expiresIn": "...",
        "viewedOn": "...",
        "deletedOn": "..."
      }
    }
  }
}
```

### 2. Extract FAQ Content to Dedicated Namespace

Create `web.secrets.faq` or move to a new `feature-secrets-help.json`:

```json
{
  "web": {
    "secrets": {
      "faq": {
        "whatIsThis": {
          "question": "What is this?",
          "answer": "..."
        },
        "isItSecure": {
          "question": "Is it secure?",
          "answer": "..."
        },
        "burnFeature": {
          "question": "What's the burn feature?",
          "answer": "..."
        },
        "expiration": {
          "question": "How does secret expiration work?",
          "answer": "..."
        },
        "lostLink": {
          "question": "Lost your secret link?",
          "answer": "..."
        },
        "oneTimeView": {
          "question": "Why can I only see the secret value once?",
          "answer": "..."
        }
      }
    }
  }
}
```

### 3. Consolidate Status Keys

Move status-related keys from `web.private` to use `web.STATUS` in `_common.json`:

- Remove `web.private.burned`, `viewed`, `destroyed`
- Use existing `web.STATUS.burned`, `web.STATUS.viewed`, `web.STATUS.destroyed`

### 4. Rename Kebab-case Keys to CamelCase

For consistency, convert kebab-case keys to camelCase:

| Current (kebab-case) | Suggested (camelCase) |
|---------------------|----------------------|
| `create-a-secret` | `createSecret` |
| `hide-secret-message` | `hideSecretMessage` |
| `view-secret-message` | `viewSecretMessage` |
| `content-hidden` | `contentHidden` |
| `secret-access-form` | `secretAccessForm` |

---

## New File Suggestions

### 1. `feature-secrets-faq.json`

Extract all FAQ/help content from `feature-secrets.json`:

**Keys to move:**
- `web.private.whats-the-burn-feature`
- `web.private.the-burn-feature-lets-you-permanently-delete-a-s...`
- `web.private.how-does-secret-expiration-work`
- `web.private.your-secret-will-remain-available-for-record-nat...`
- `web.private.lost-your-secret-link`
- `web.private.for-security-reasons-we-cant-recover-lost-secret...`
- `web.private.why-can-i-only-see-the-secret-value-once`
- `web.private.we-display-the-value-for-you-so-that-you-can-ver...`
- `web.private.what-happens-when-i-burn-a-secret`
- `web.private.burning-a-secret-permanently-deletes-it-before-a...`
- `web.secrets.what-is-this`
- `web.secrets.is-it-secure`
- `web.secrets.what-happens-next`

**Rationale:** FAQ content is often maintained separately, may require different translation review, and has distinct formatting needs (Q&A pairs).

### 2. `feature-secrets-security.json` (Optional)

If security messaging grows, consider extracting:

**Candidate keys:**
- `web.private.core-security-features`
- `web.private.one-time-access`
- `web.private.each-secret-can-only-be-viewed-once-after-viewin...`
- `web.private.passphrase-protection`
- `web.private.and-never-stored-in-its-original-form-this-appro...`
- `web.secrets.secure-encrypted-storage`
- `web.secrets.auto-expire-after-viewing`

---

## Key Naming Issues

### Truncated/Unclear Key Names

These keys use sentence fragments that make them hard to identify:

| Current Key | Issue | Suggested Name |
|-------------|-------|----------------|
| `theyll-appear-here-once-youve-shared-them` | Full sentence as key | `emptyStateMessage` |
| `the-burn-feature-lets-you-permanently-delete-a-s` | Truncated | `burnFeatureDescription` |
| `your-secret-will-remain-available-for-record-nat` | Truncated | `expirationExplanation` |
| `for-security-reasons-we-cant-recover-lost-secret` | Truncated | `lostLinkExplanation` |
| `we-display-the-value-for-you-so-that-you-can-ver` | Truncated | `oneTimeViewExplanation` |
| `burning-a-secret-permanently-deletes-it-before-a` | Truncated | `burnActionExplanation` |
| `and-never-stored-in-its-original-form-this-appro` | Truncated, fragment | `passphraseSecurityNote` |
| `each-secret-can-only-be-viewed-once-after-viewin` | Truncated | `oneTimeAccessDescription` |
| `when-ready-click-the-view-secret-button-at-the-t` | Truncated | `viewSecretInstruction` |
| `onetime-secret-is-a-secure-way-to-share-sensitiv` | Truncated | `serviceDescription` |
| `yes-after-viewing-the-secret-is-permanently-dele` | Truncated | `securityConfirmation` |
| `before-you-open-it-heres-what-you-should-know` | Full sentence | `preRevealNotice` |

### Placeholder Format Inconsistency

| Key | Current Format | Suggested Format |
|-----|---------------|------------------|
| `expiresIn` | `{duration}` | Consistent |
| `passphraseMinimumLength` | `{length}` | Consistent |
| `deleted-on-record-burned` | `{0}` | `{date}` or `{timestamp}` |
| `viewed-on-record-received` | `{0}` | `{date}` or `{timestamp}` |
| `expires-in-record-natural_expiration` | `{0}` | `{duration}` |
| `formattedcharcount-formattedmaxlength-chars` | `{0} / {1}` | `{current} / {max}` |

---

## Summary of Recommendations

### Priority 1 - Remove Duplicates
1. Remove keys that duplicate `_common.json` entries
2. Update component references to use common keys

### Priority 2 - Key Renaming
1. Convert truncated sentence keys to semantic names
2. Standardize on camelCase naming
3. Use descriptive placeholder names

### Priority 3 - Hierarchy Restructuring
1. Add sub-namespaces to `web.secrets` (form, actions, status, timestamps)
2. Consider `web.secrets.faq` for FAQ content

### Priority 4 - New Files (If Warranted)
1. `feature-secrets-faq.json` - If FAQ content grows or needs separate maintenance
2. Keep security messaging in-file unless it grows significantly

---

## Implementation Notes

When reorganizing:
1. Update all `$t()` calls in Vue components
2. Run `pnpm run type-check` to catch missing keys
3. Test i18n fallbacks for any moved keys
4. Update other locale files (non-English) with same structure changes
