# Locale Key Analysis: feature-regions.json

## File Overview

**Path:** `src/locales/en/feature-regions.json`
**Structure:** `web.regions.*` (38 keys total)

This file contains locale strings related to data regions, jurisdictions, and data sovereignty features. The keys fall into several logical categories:

### Current Key Categories

| Category | Count | Description |
|----------|-------|-------------|
| Data Sovereignty Explanations | 8 | Marketing/explanatory text about data sovereignty |
| Region/Jurisdiction Labels | 10 | UI labels for regions and jurisdictions |
| Benefits/Value Propositions | 8 | "Why it matters" section with trust, privacy, compliance, performance |
| Navigation/Actions | 5 | CTA buttons and navigation elements |
| Status Indicators | 3 | Active, current, etc. |
| Dynamic Templates | 4 | Keys with placeholders `{0}`, `{1}` |

---

## Potentially Misplaced Keys

### 1. Keys That Duplicate `_common.json`

| Key | Current Location | Recommended Action |
|-----|------------------|-------------------|
| `active` | `web.regions.active` | **Remove** - Already exists at `web.COMMON.active` |
| `jurisdiction` | `web.regions.jurisdiction` | Keep - context-specific term |

**Rationale:** The `active` key is a generic status indicator that already exists in `_common.json` at `web.COMMON.active`. Using the common key promotes consistency.

### 2. Keys That Could Move to `_common.json`

| Key | Value | Reason |
|-----|-------|--------|
| `current` | "Current" | Generic UI label, reusable across features |

### 3. Keys That Overlap with TITLES in `_common.json`

The following keys have near-duplicates in `web.COMMON.TITLES`:

| feature-regions Key | _common.json TITLES Key |
|---------------------|------------------------|
| `available-regions` | `available_regions` |
| `your-region` | - (no match, keep) |
| `data-region` | `data_region` |

**Recommendation:** Consider using the TITLES keys for page/section titles and keep the regions file for descriptive content.

---

## Suggested Hierarchy Improvements

### Current Structure (flat)
```
web.regions.*
  - data-sovereignty-title
  - data-sovereignty-description
  - trust-title
  - trust-description
  - privacy-title
  - privacy-description
  ...
```

### Proposed Structure (nested)
```
web.regions
  |-- labels
  |     |-- your-region
  |     |-- your-current-region
  |     |-- available-regions
  |     |-- jurisdiction
  |     |-- data-region
  |     |-- unknown-jurisdiction
  |     |-- current
  |     |-- active (or remove - use common)
  |
  |-- sovereignty
  |     |-- title
  |     |-- description
  |     |-- separate-environments
  |     |-- no-data-transfer
  |     |-- switching-creates-new
  |
  |-- benefits
  |     |-- why-it-matters (section title)
  |     |-- trust
  |     |     |-- title
  |     |     |-- description
  |     |-- privacy
  |     |     |-- title
  |     |     |-- description
  |     |-- compliance
  |     |     |-- title
  |     |     |-- description
  |     |-- performance
  |     |     |-- title
  |     |     |-- description
  |
  |-- actions
  |     |-- explore-other-regions
  |     |-- continue-to-jurisdiction
  |     |-- contact-compliance-team
  |     |-- review-documentation
  |
  |-- templates
        |-- serving-from
        |-- jurisdiction-display
        |-- data-center-location
        |-- current-jurisdiction
```

### Benefits of Nested Structure
1. **Clarity:** Groups related keys logically
2. **Maintainability:** Easier to find and update related strings
3. **Component Mapping:** Nested structure can map 1:1 with Vue component sections

---

## Inconsistencies Found

### Naming Convention Issues

| Issue | Examples | Recommendation |
|-------|----------|----------------|
| Mixed casing in key names | `your-region` vs `your_current_region` would be inconsistent if it existed | Stick to kebab-case (current standard) |
| Truncated key names | `your-account-and-data-are-protected-under-the-la` | Use full descriptive names or abbreviate consistently |
| Template key names unclear | `jurisdiction-display_name-iscurrentjurisdiction-` | Rename to `jurisdiction-display-template` |
| Long abbreviated keys | `each-jurisdiction-maintains-separate-legal-compl` | Consider `jurisdiction-separation-explanation` |
| `data-center-location-currentjurisdiction-identif` | Truncated and unclear | Rename to `data-center-location-template` |

### Template Placeholder Issues

| Key | Current Value | Issue |
|-----|---------------|-------|
| `jurisdiction-display_name-iscurrentjurisdiction-` | `{0} {1}` | Key name is confusing; value lacks context |
| `continue-to-jurisdiction-domain` | `Continue to {0}` | Good - clear template |
| `data-center-location-currentjurisdiction-identif` | `Data center location: {0}` | Key is truncated; value is clear |

---

## New File Suggestions

### No new files recommended

The current file is appropriately scoped. With 38 keys, it does not warrant splitting. The regions feature is cohesive and all keys relate to the same domain concept.

However, if the feature grows significantly (50+ keys), consider:

1. **`feature-regions-benefits.json`** - For the "Why Data Sovereignty Matters" marketing content
2. **`feature-regions-jurisdictions.json`** - For jurisdiction-specific labels if per-region customization is needed

---

## Action Items Summary

| Priority | Action | Impact |
|----------|--------|--------|
| High | Remove `active` key, use `web.COMMON.active` | Reduces duplication |
| Medium | Rename truncated keys to be descriptive | Improves maintainability |
| Medium | Consider nested hierarchy for related keys | Better organization |
| Low | Move `current` to `_common.json` if used elsewhere | Promotes reuse |

---

## Keys Reference

### All 38 Keys (Current Structure)

```
web.regions.data-sovereignty-title
web.regions.data-sovereignty-description
web.regions.separate-environments-explanation
web.regions.no-data-transfer-policy
web.regions.switching-creates-new-account
web.regions.your-region
web.regions.your-current-region
web.regions.active
web.regions.explore-other-regions
web.regions.why-it-matters
web.regions.trust-title
web.regions.trust-description
web.regions.privacy-title
web.regions.privacy-description
web.regions.compliance-title
web.regions.compliance-description
web.regions.performance-title
web.regions.performance-description
web.regions.regions
web.regions.contact-our-compliance-team
web.regions.review-our-documentation
web.regions.your-account-and-data-are-protected-under-the-la
web.regions.this-regulatory-framework-is-determined-by-your-
web.regions.each-jurisdiction-maintains-separate-legal-compl
web.regions.to-understand-the-specific-regulations-and-prote
web.regions.current
web.regions.jurisdiction-display_name-iscurrentjurisdiction-
web.regions.available-regions
web.regions.jurisdiction
web.regions.data-center-location-currentjurisdiction-identif
web.regions.data-region
web.regions.unknown-jurisdiction
web.regions.serving-you-from-the
web.regions.continue-to-jurisdiction-domain
web.regions.current-jurisdiction
```
