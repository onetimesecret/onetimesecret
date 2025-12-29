# Homepage Locale Key Analysis

**File:** `/Users/d/Projects/opensource/onetime/onetimesecret/src/locales/en/homepage.json`
**Date:** 2025-12-27

## File Overview

The `homepage.json` file contains keys under `web.homepage` namespace with the following categories of content:

### Current Key Categories

| Category | Example Keys | Count |
|----------|-------------|-------|
| Main taglines | `tagline1`, `tagline2`, `tagline-signed`, `tagline-sealed`, `tagline-delivered` | 5 |
| CTA/Marketing | `cta_title`, `cta_subtitle`, `cta_feature1-3`, `explore_premium_plans` | 7 |
| Password generation | `password_generation_title`, `password_generation_description` | 2 |
| Auth-only mode | `authonly.tagline1`, `authonly.tagline2` | 2 |
| Disabled mode | `disabled.tagline1`, `disabled.tagline2` | 2 |
| Brand references | `onetime-secret`, `onetime-secret-literal`, `one-time-secret-literal`, `onetime-secret-homepage` | 4 |
| Welcome/onboarding | `welcome-to-onetime-secret`, `welcome-to-the-global-broadcast` | 2 |
| Feature descriptions | `secure-links`, `send-sensitive-information...`, `meets-and-exceeds-compliance-standards` | 5 |
| Misc navigation | `log-in-to-onetime-secret`, `about-onetime-secret`, `signup-individual-and-business-plans` | 4 |

---

## Potentially Misplaced Keys

### 1. Keys That Belong in `_common.json`

These are brand names and generic terms used throughout the application:

| Key | Recommended Destination | Rationale |
|-----|------------------------|-----------|
| `onetime-secret` | `web.COMMON.brand.name` | Brand name used site-wide |
| `onetime-secret-literal` | `web.COMMON.brand.name_literal` | Duplicate; consolidate with above |
| `one-time-secret-literal` | `web.COMMON.brand.name_hyphenated` | Alternate spelling; consider single source |
| `onetime-secret-homepage` | `web.COMMON.brand.homepage_title` | Used in page titles |

### 2. Keys That Belong in `layout.json`

Navigation and link labels should be in layout:

| Key | Recommended Destination | Rationale |
|-----|------------------------|-----------|
| `visit-onetime-secret-home` | `web.layout.visit-onetime-secret-homepage` | Already exists similar key in layout.json |
| `log-in-to-onetime-secret` | `web.navigation.log-in` | Navigation action |
| `about-onetime-secret` | `web.navigation.about` | Navigation link |
| `about-onetime-secret-0` | Remove (duplicate) | Exact duplicate of `about-onetime-secret` |

### 3. Keys That Belong in `auth.json`

Account/authentication related:

| Key | Recommended Destination | Rationale |
|-----|------------------------|-----------|
| `signup-individual-and-business-plans` | `web.signup.plans_cta` | Signup-related content |
| `sign_up_free` | `web.signup.button_free` | Signup button text |
| `need_free_account` | `web.signup.free_account_prompt` | Signup prompt |

### 4. Keys That May Warrant New File: `feature-marketing.json`

CTA and promotional content could be separated:

| Key | Suggested New Location |
|-----|----------------------|
| `cta_title` | `web.marketing.cta.title` |
| `cta_subtitle` | `web.marketing.cta.subtitle` |
| `cta_feature1` | `web.marketing.cta.features.custom_domains` |
| `cta_feature2` | `web.marketing.cta.features.unlimited_sharing` |
| `cta_feature3` | `web.marketing.cta.features.customer_trust` |
| `explore_premium_plans` | `web.marketing.cta.explore_premium` |
| `meets-and-exceeds-compliance-standards` | `web.marketing.compliance.badge` |
| `secure-your-brand-build-customer-trust-etc` | `web.marketing.custom_domains.description` |
| `now-with-custom-domains` | `web.marketing.custom_domains.badge` |

---

## Suggested Hierarchy Improvements

### Current Flat Structure Issues

The current structure is largely flat with inconsistent naming conventions:
- Mix of `snake_case` (`cta_title`) and `kebab-case` (`secure-links`)
- Some keys are full sentences as identifiers (`a-trusted-way-to-share-sensitive-information-etc`)
- Duplicate concepts (`onetime-secret`, `onetime-secret-literal`, `one-time-secret-literal`)

### Proposed Hierarchical Structure

```json
{
  "web": {
    "homepage": {
      "hero": {
        "tagline": {
          "primary": "Paste a password, secret message or private link below.",
          "secondary": "Keep sensitive info out of your email and chat logs.",
          "signed": "Signed",
          "sealed": "Sealed",
          "delivered": "Delivered"
        },
        "hint": "* A secret link only works once and then disappears forever.",
        "protip": "Your message will self-destruct after being viewed..."
      },
      "form": {
        "more_text": {
          "prefix": "Sign up for a",
          "link": "free account",
          "suffix": "and be able to send the secret by email."
        },
        "link_preview": "Link Preview"
      },
      "password_generator": {
        "title": "Password Generator",
        "description": "Click \"Generate Password\" to create a secure random password..."
      },
      "modes": {
        "authonly": {
          "tagline1": "If you have an account, please log in to continue.",
          "tagline2": "Secure messaging service is for internal use only."
        },
        "disabled": {
          "tagline1": "User interface and login capabilities are not available.",
          "tagline2": "This service is setup for internal use only."
        },
        "private_instance": {
          "message": "This is a private instance. Only authorized team members can..."
        }
      },
      "onboarding": {
        "welcome": "Welcome to Onetime Secret.",
        "intro": "Onetime Secret helps us share sensitive information securely...",
        "security_notice": "Information shared through this service can only be accessed once..."
      }
    }
  }
}
```

---

## Duplicate Keys to Consolidate

| Keys | Recommended Single Key |
|------|----------------------|
| `about-onetime-secret-0`, `about-onetime-secret` | Keep one: `about-onetime-secret` |
| `create-a-secure-link`, `send-sensitive-information-that-can-only-be-viewed-once` | Consider consolidating if used for same purpose |

---

## New File Suggestions

### 1. `feature-marketing.json` (Recommended)

Group promotional and CTA content:
- All `cta_*` keys
- Compliance badges
- Feature highlights used in marketing sections
- Upsell messaging

### 2. `brand.json` (Optional)

If brand references are used across many files:
- `onetime-secret` variants
- Logo alt texts
- Brand-related link text

---

## Naming Convention Recommendations

1. **Standardize on kebab-case** for all keys (aligns with existing majority in layout.json)
2. **Remove sentence-length key names** - use short descriptive keys with full text as values
3. **Use nested objects** for related concepts (e.g., `modes.authonly` vs flat `authonly`)
4. **Prefix duplicates** - if same text needed in multiple contexts, use semantic prefixes

---

## Summary of Recommended Actions

| Priority | Action | Impact |
|----------|--------|--------|
| High | Move brand names to `_common.json` | Prevents duplication across files |
| High | Remove duplicate `about-onetime-secret-0` | Reduces maintenance burden |
| Medium | Move navigation labels to `layout.json` | Better organization |
| Medium | Create `feature-marketing.json` for CTA content | Clearer separation of concerns |
| Low | Restructure remaining keys into hierarchy | Improved maintainability |
| Low | Standardize naming convention | Consistency across locale files |
