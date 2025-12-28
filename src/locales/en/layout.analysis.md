# Layout.json Key Structure Analysis

## File Overview

The `layout.json` file contains 98 lines with keys organized under `web.*` namespace. The file currently contains **6 distinct categories** of keys:

| Category | Path | Key Count | Purpose |
|----------|------|-----------|---------|
| footer | `web.footer.*` | 20 | Footer links and labels |
| navigation | `web.navigation.*` | 3 | Navigation labels |
| site | `web.site.*` | 1 | Site metadata |
| meta | `web.meta.*` | 4 | Translation feedback notices |
| help | `web.help.*` | 11 | FAQ content for secret viewing |
| layout | `web.layout.*` | 38 | General layout/UI strings |

---

## Potentially Misplaced Keys

### 1. Translation/i18n Related Keys (Move to `feature-translations.json`)

These keys relate to the translation feature feedback, not core layout:

| Current Path | Recommended Path |
|--------------|------------------|
| `web.meta.were-making-onetime-secret-available-in-multiple` | `web.translations.feedback.making-available-multiple-languages` |
| `web.meta.translations-are-new-spotted-an-error` | `web.translations.feedback.spotted-an-error` |
| `web.meta.we-recently-added-translations` | `web.translations.feedback.recently-added` |
| `web.meta.privacy-and-security-should-be-accessible` | `web.translations.feedback.accessibility-notice` |

**Rationale**: The `feature-translations.json` file already exists and contains translation-related content. These meta notices about translation quality belong there.

---

### 2. Secret Viewing FAQ Keys (Move to `feature-secrets.json`)

The entire `web.help.secret_view_faq` section should move to `feature-secrets.json`:

| Current Path | Recommended Path |
|--------------|------------------|
| `web.help.learn_more` | `web.secrets.help.learn_more` |
| `web.help.secret_view_faq.*` | `web.secrets.faq.*` |
| `web.help.secret_view_faq.what_am_i_looking_at.*` | `web.secrets.faq.what_am_i_looking_at.*` |
| `web.help.secret_view_faq.can_i_view_again.*` | `web.secrets.faq.can_i_view_again.*` |
| `web.help.secret_view_faq.how_to_copy.*` | `web.secrets.faq.how_to_copy.*` |
| `web.help.secret_view_faq.is_my_viewing_tracked.*` | `web.secrets.faq.is_my_viewing_tracked.*` |
| `web.help.secret_view_faq.one_time_warning` | `web.secrets.faq.one_time_warning` |

**Rationale**: This FAQ is specific to the secret viewing experience. The `feature-secrets.json` file already has sections like `web.secrets.*`, `web.private.*`, and `web.shared.*` for secret-related content.

---

### 3. Icon Library Keys (Consider new file or `_common.json`)

These keys are about icon attribution, not layout:

| Current Path | Recommendation |
|--------------|----------------|
| `web.layout.icon-library` | Move to `_common.json` under `web.COMMON.icons.*` |
| `web.layout.google-material` | Move to `_common.json` under `web.COMMON.icons.*` |
| `web.layout.material-design-icons` | Move to `_common.json` under `web.COMMON.icons.*` |
| `web.layout.heroicons` | Move to `_common.json` under `web.COMMON.icons.*` |
| `web.layout.carbon` | Move to `_common.json` under `web.COMMON.icons.*` |
| `web.layout.font-awesome-6` | Move to `_common.json` under `web.COMMON.icons.*` |

**Rationale**: Icon library names are reference data, not layout strings. They could go in `_common.json` as common reference data.

---

### 4. Legal/Policy Links (Already duplicated in footer)

These keys in `web.layout.*` duplicate concepts in `web.footer.*`:

| Current Path | Already Exists At |
|--------------|-------------------|
| `web.layout.view-privacy-policy` | `web.footer.read-our-privacy-policy` |
| `web.layout.view-terms-of-service` | `web.footer.view-our-terms-and-conditions` |
| `web.layout.terms-of-service` | `web.footer.terms` |
| `web.layout.privacy-policy` | `web.footer.privacy` |

**Recommendation**: Consolidate into footer section or create a `web.legal.*` namespace in a dedicated file.

---

## Suggested Hierarchy Improvements

### A. Restructure `web.layout.*` into subcategories

Current structure is flat with 38 keys. Suggested reorganization:

```json
{
  "web": {
    "layout": {
      "navigation": {
        "dashboard": "Dashboard Navigation",
        "mobile": "Mobile Navigation",
        "main": "Main Navigation",
        "footer": "Footer navigation",
        "mobile-item-count": "{count} items"
      },
      "accessibility": {
        "go-back-to-previous-page": "Go back to previous page",
        "site-footer": "Site footer",
        "company-logo": "Company logo",
        "brand-logo": "Brand logo"
      },
      "actions": {
        "toggle-dark-mode": "Toggle dark mode",
        "provide-feedback": "Provide feedback",
        "return-home": "Return home",
        "return-to-home-page": "Return to home page",
        "return-to-home": "Return to Home",
        "view-source-on-github": "View source on GitHub"
      },
      "settings": {
        "loading-content": "Loading settings content...",
        "sections": "Settings sections",
        "close": "Close settings",
        "customize-preferences": "Customize your app preferences and settings"
      },
      "localization": {
        "current-language": "Change language. Current language is {0}",
        "language-changed": "Language changed to {0}",
        "switch-mode": "Switch to {0} mode",
        "mode-enabled": "{0} mode enabled"
      },
      "version": {
        "website-version": "Website Version: v{0}",
        "release-notes": "Release Notes"
      }
    }
  }
}
```

### B. Move `web.navigation.*` into `web.layout.navigation.*`

The `web.navigation` section has only 3 keys and fits naturally within layout:

```json
{
  "web": {
    "layout": {
      "navigation": {
        "billing": "Billing",
        "billingOverview": "Overview",
        "organizations": "Organizations"
      }
    }
  }
}
```

### C. Merge `web.site.*` into `web.layout.version.*`

The single key `web.site.website-version` should merge with version-related keys in layout.

---

## New File Suggestions

### 1. `legal.json` (Recommended)

Consolidate all legal/policy-related content:

```json
{
  "web": {
    "legal": {
      "terms": {
        "title": "Terms of Service",
        "view": "View Terms of Service",
        "description": "View our Terms and Conditions"
      },
      "privacy": {
        "title": "Privacy Policy",
        "view": "View Privacy Policy",
        "description": "Read our Privacy Policy"
      },
      "security": {
        "title": "Security",
        "description": "Learn about our security measures"
      }
    }
  }
}
```

**Sources**: Pull from `layout.json` and `footer` section of same file.

---

## Summary of Recommended Actions

| Priority | Action | Files Affected |
|----------|--------|----------------|
| High | Move `web.meta.*` translation notices to `feature-translations.json` | layout.json, feature-translations.json |
| High | Move `web.help.secret_view_faq.*` to `feature-secrets.json` | layout.json, feature-secrets.json |
| Medium | Restructure flat `web.layout.*` into subcategories | layout.json |
| Medium | Merge `web.navigation.*` into `web.layout.navigation.*` | layout.json |
| Medium | Merge `web.site.*` into `web.layout.*` | layout.json |
| Low | Move icon library keys to `_common.json` | layout.json, _common.json |
| Low | Consider `legal.json` for consolidated legal content | New file |

---

## Notes on Key Naming Conventions

Observed inconsistencies in the current file:

1. **Kebab-case vs camelCase**: Mix of `billingOverview` and `go-back-to-previous-page`
2. **Verbose keys**: Some keys repeat information (e.g., `settings-sections` and `settings-sections-0`)
3. **Template variables**: Inconsistent use of `{0}` vs named variables like `{count}`

**Recommendation**: Standardize on kebab-case for keys and named template variables for clarity.
