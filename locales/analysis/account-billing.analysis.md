# Locale Key Analysis: account-billing.json

## File Overview

**Path:** `src/locales/en/account-billing.json`
**Root namespace:** `web.billing`
**Total top-level categories:** 12

### Current Key Categories

| Category | Key Path | Description |
|----------|----------|-------------|
| `upgrade` | `web.billing.upgrade.*` | Upgrade prompts and feature gate messages |
| `overview` | `web.billing.overview.*` | Billing dashboard overview, organization selector, quick actions |
| `plans` | `web.billing.plans.*` | Plan selection, pricing options |
| `invoices` | `web.billing.invoices.*` | Invoice history and status |
| `notices` | `web.billing.notices.*` | Organization-managed billing notices |
| `limits` | `web.billing.limits.*` | Team/member limit messages |
| `subscription` | `web.billing.subscription.*` | Subscription status labels |
| `portal` | `web.billing.portal.*` | External billing portal integration |
| (flat keys) | `web.billing.*` | Marketing copy, promotional content, misc strings |

---

## Potentially Misplaced Keys

### 1. Organization-Related Keys

**Current Location:** `web.billing.overview.organization_selector`, `web.billing.overview.no_organizations_*`, `web.billing.notices.org_managed`

**Recommendation:** These keys relate to organization context selection and should either:
- Remain here if tightly coupled to billing workflows
- Move to `feature-organizations.json` if they're reused elsewhere

**Affected Keys:**
```
web.billing.overview.organization_selector
web.billing.overview.no_organizations_title
web.billing.overview.no_organizations_description
web.billing.notices.org_managed
web.billing.notices.view_org_billing
```

**Verdict:** Keep in billing - they describe billing-specific organization context.

---

### 2. Feature Entitlements

**Current Location:** `web.billing.overview.entitlements.*`

**Issue:** These describe plan features/capabilities. They could belong in:
- A dedicated `feature-entitlements.json` or `plans.json` file
- The `_common.json` file under `FEATURES` namespace

**Affected Keys:**
```
web.billing.overview.entitlements.create_secrets
web.billing.overview.entitlements.basic_sharing
web.billing.overview.entitlements.custom_domains
web.billing.overview.entitlements.api_access
web.billing.overview.entitlements.priority_support
web.billing.overview.entitlements.audit_logs
```

**Recommendation:** Move to `_common.json` under `web.FEATURES.entitlements.*` for reuse across pricing pages, plan comparison components, and upgrade modals.

---

### 3. Marketing/Promotional Copy (Flat Keys)

**Current Location:** Lines 102-125, directly under `web.billing`

**Issue:** These are promotional/marketing strings mixed with UI labels:
```
web.billing.start-today
web.billing.start-today-with-identity-plus
web.billing.per-month
web.billing.full-api-access
web.billing.privacy-first-design
web.billing.identity-plus
web.billing.click-this-lightning-bolt-to-upgrade-for-custom-domains
web.billing.maybe-later
web.billing.upgrade-account
web.billing.upgrade-to-identity-plus
web.billing.upgrade-for-teams
web.billing.benefits-of
web.billing.t-benefits-of-identity-plus
web.billing.upgrade-to
web.billing.upgrade-for-yourdomain
web.billing.includes-all-features-and-unlimited-sharing-capa
web.billing.includes-all-data-locality-options
web.billing.get-started
web.billing.frequency-value-annually-annual-monthly-subscrip
web.billing.elevate-your-secure-sharing-with-custom-domains-
web.billing.payment-frequency
web.billing.secure-your-brand-and-build-customer-trust-with-
web.billing.secure-links-stronger-connections
web.billing.identity-tier-not-found-in-product-tiers
```

**Issues Identified:**
1. Inconsistent key naming (kebab-case vs descriptive sentences)
2. Truncated key names (e.g., `includes-all-features-and-unlimited-sharing-capa`)
3. Marketing copy mixed with error messages (`identity-tier-not-found-in-product-tiers`)
4. No logical grouping

**Recommendation:** Reorganize into nested categories:
- `web.billing.marketing.*` - Promotional headlines and taglines
- `web.billing.cta.*` - Call-to-action buttons
- `web.billing.errors.*` - Error messages (move `identity-tier-not-found...`)

---

## Suggested Hierarchy Improvements

### Current Structure (Problematic Flat Keys)
```json
{
  "web": {
    "billing": {
      "start-today": "...",
      "per-month": "...",
      "upgrade-account": "..."
    }
  }
}
```

### Proposed Structure
```json
{
  "web": {
    "billing": {
      "marketing": {
        "tagline": "Secure Links, Stronger Connections",
        "value_prop": "Elevate your secure sharing with custom domains...",
        "brand_trust": "Secure your brand and build customer trust...",
        "all_plans_include": "All plans include privacy features...",
        "data_locality": "All plans include choice of data locality: {0} regions"
      },
      "cta": {
        "start_today": "Start today",
        "start_with_identity_plus": "Start today with Identity Plus",
        "get_started": "Get started",
        "upgrade_account": "Upgrade account",
        "upgrade_to_identity_plus": "Upgrade to Identity Plus",
        "upgrade_for_teams": "Upgrade for Teams",
        "upgrade_for_custom_domain": "Upgrade for secrets.yourdomain.com",
        "maybe_later": "Maybe Later"
      },
      "pricing": {
        "per_month": "per month",
        "payment_frequency": "Payment frequency",
        "subscription_type": "{0} subscription"
      },
      "features": {
        "full_api_access": "Full API access",
        "privacy_first_design": "Privacy-first design"
      },
      "identity_plus": {
        "name": "Identity Plus",
        "benefits_title": "{0}: Identity Plus",
        "upgrade_hint": "Click this lightning bolt to upgrade for custom domains"
      },
      "errors": {
        "tier_not_found": "Identity tier not found in product tiers"
      }
    }
  }
}
```

---

## Key Naming Inconsistencies

| Current Key | Issue | Suggested Rename |
|-------------|-------|------------------|
| `includes-all-features-and-unlimited-sharing-capa` | Truncated | `all_plans_include` |
| `t-benefits-of-identity-plus` | Unclear prefix `t-` | `identity_plus.benefits_title` |
| `frequency-value-annually-annual-monthly-subscrip` | Truncated/confusing | `pricing.subscription_type` |
| `click-this-lightning-bolt-to-upgrade-for-custom-domains` | Too verbose | `identity_plus.upgrade_hint` |
| `secure-your-brand-and-build-customer-trust-with-` | Truncated | `marketing.brand_trust` |
| `elevate-your-secure-sharing-with-custom-domains-` | Truncated | `marketing.value_prop` |

---

## New File Suggestions

### Option A: Create `feature-plans.json`

If plan/pricing content grows, consider extracting:
- `web.billing.plans.*`
- `web.billing.marketing.*` (promotional content)
- `web.billing.cta.*` (upgrade CTAs)

This would align with the existing `feature-*` naming pattern.

### Option B: Create `pricing.json`

A dedicated file for all pricing-page content:
- Plan comparisons
- Feature lists by tier
- Marketing copy
- Pricing labels

---

## Overlap with Existing Files

### `account.json`
Contains `web.account.subscription_title` and `web.account.manage_subscription` which could conflict with `web.billing.subscription.*`. Consider consolidating subscription-related keys in one location.

### `feature-organizations.json`
The organization selector and billing notices referencing organizations could be shared. Evaluate whether to use shared keys from `feature-organizations.json`.

### `_common.json`
- `web.COMMON.monthly` / `web.COMMON.yearly` duplicates `web.billing.plans.monthly` / `web.billing.plans.yearly`
- `web.FEATURES.*` could house the entitlements

---

## Summary of Recommendations

1. **Group flat marketing keys** into `web.billing.marketing.*`, `web.billing.cta.*`, `web.billing.pricing.*`
2. **Move entitlements** to `_common.json` under `web.FEATURES.entitlements.*`
3. **Fix truncated key names** with descriptive, semantic names
4. **Standardize naming** to snake_case (matching existing nested keys)
5. **Extract error message** (`identity-tier-not-found...`) to `web.billing.errors.*`
6. **Consider deduplication** with `_common.json` for `monthly`/`yearly` labels
7. **Document plan tier names** (`identity-plus`, `single-team`, `multi-team`) in a consistent location

---

## Priority Actions

| Priority | Action | Impact |
|----------|--------|--------|
| High | Reorganize flat keys into nested structure | Maintainability, consistency |
| High | Fix truncated key names | Developer clarity |
| Medium | Move entitlements to shared location | Reusability |
| Medium | Dedupe with `_common.json` | DRY principle |
| Low | Consider `feature-plans.json` extraction | Only if content grows |
