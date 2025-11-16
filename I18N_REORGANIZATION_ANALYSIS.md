# i18n Structure Analysis & Reorganization Recommendations

## Executive Summary

This document analyzes the current i18n (internationalization) structure of Onetime Secret and provides recommendations for reorganizing locale files to:
1. Clearly delineate between **account users** (creators) and **recipients** (viewers)
2. Reduce translation costs by identifying which keys are essential vs. optional
3. Improve maintainability and scalability of translations

---

## Current State Analysis

### Locale File Statistics

- **Total locale files**: 30 languages
- **Total translation keys**: ~850+ keys
- **Namespaced keys (web.*)**: ~320 keys across 23 namespaces
- **Flat keys**: 427 keys (no namespace prefix)

### Current Namespace Structure (web.*)

| Namespace | Key Count | Purpose |
|-----------|-----------|---------|
| `web.COMMON` | 81 | Universal UI elements, buttons, labels |
| `web.LABELS` | 43 | Generic form labels and field names |
| `web.private` | 34 | Metadata/receipt viewing (for secret creators) |
| `web.STATUS` | 29 | Status messages and notifications |
| `web.homepage` | 20 | Homepage marketing and CTAs |
| `web.footer` | 20 | Footer links and information |
| `web.account` | 14 | Account management settings |
| `web.incoming` | 11 | Support secret functionality |
| `web.shared` | 10 | Shared between creators and recipients |
| `web.secrets` | 6 | Secret form inputs |
| `web.login` | 5 | Sign-in functionality |
| `web.dashboard` | 4 | Dashboard-specific labels |
| `web.signup` | 2 | Registration functionality |
| `web.domains` | 2 | Custom domain management |
| Others | ~50 | Colonel (admin), feedback, help, meta, etc. |

### Issues with Current Structure

1. **Mixed Organization**: 427 flat keys + 320 namespaced keys creates inconsistency
2. **No User-Type Segmentation**: Keys used only by recipients are mixed with creator-only keys
3. **Translation Burden**: All 850+ keys must be translated for each language, even though recipients see <20% of them
4. **Unclear Dependencies**: Hard to determine which keys are critical for core recipient experience
5. **Namespace Confusion**: `web.private` is for creators (metadata), not recipients; `web.shared` is unclear

---

## Component Usage Analysis

### 1. RECIPIENT-ONLY Components (Core User Experience)

**Purpose**: Anonymous users who receive a secret link and view/burn secrets without authentication

#### Views
- `src/views/secrets/canonical/ShowSecret.vue` (6 keys)
- `src/views/secrets/branded/ShowSecret.vue` (similar to canonical)
- `src/views/secrets/ShowMetadata.vue` (6 keys)
- `src/views/secrets/BurnSecret.vue` (14 keys)
- `src/views/secrets/UnknownMetadata.vue` (4 keys)

#### Components
- `src/components/secrets/canonical/SecretConfirmationForm.vue` (7 keys)
- `src/components/secrets/canonical/SecretDisplayCase.vue` (14 keys)
- `src/components/secrets/branded/SecretConfirmationForm.vue` (10 keys)
- `src/components/secrets/branded/SecretDisplayCase.vue` (10 keys)
- `src/components/secrets/SecretRecipientHelpContent.vue` (7 keys)
- `src/components/secrets/SecretDisplayHelpContent.vue` (11 keys)
- `src/components/secrets/UnknownSecretHelpContent.vue` (7 keys)
- `src/components/layout/SecretFooterAttribution.vue` (9 keys)
- `src/components/layout/QuietFooter.vue` (5 keys)

#### Key i18n Keys Used by Recipients

**From analysis, recipients use approximately 50-60 unique keys:**

```
Core Recipient Keys (web.* namespace):
- web.COMMON.burn_this_secret
- web.COMMON.burn_this_secret_aria
- web.COMMON.burn_this_secret_confirm_hint
- web.COMMON.enter_passphrase_here
- web.COMMON.loading
- web.COMMON.need_help
- web.COMMON.secret
- web.COMMON.sent_to
- web.COMMON.warning
- web.COMMON.word_cancel
- web.COMMON.word_confirm
- web.LABELS.actions
- web.LABELS.encrypted
- web.LABELS.timeline
- web.private.only_see_once
- web.shared.viewed_own_secret
- web.shared.you_created_this_secret

Flat keys used by recipients:
- back
- back-to-details
- create-a-secret
- information-no-longer-available
- information-shared-through-this-service-can-only
- not-found
- permanently-deleted
- return-to-home
- that-information-is-no-longer-available
- you-can-safely-close-this-tab
```

### 2. CREATOR-ONLY Components (Account Users)

**Purpose**: Authenticated users who create secrets, manage domains, configure settings

#### Views
- `src/views/dashboard/DashboardIndex.vue`
- `src/views/dashboard/DashboardRecent.vue` (8 keys)
- `src/views/dashboard/DashboardDomains.vue` (2 keys)
- `src/views/dashboard/DashboardDomainAdd.vue` (1 key)
- `src/views/dashboard/DashboardDomainVerify.vue` (11 keys)
- `src/views/dashboard/DashboardDomainBrand.vue`
- `src/views/account/AccountIndex.vue` (6 keys)

#### Components
- `src/components/secrets/SecretMetadataTable.vue` (24 keys - most used!)
- `src/components/DomainsTable.vue` (10 keys)
- `src/components/VerifyDomainDetails.vue` (20 keys)
- `src/components/account/AccountBillingSection.vue` (11 keys)
- `src/components/account/AccountChangePasswordForm.vue` (9 keys)
- `src/components/account/AccountDeleteButtonWithModalForm.vue` (12 keys)
- `src/components/account/APIKeyCard.vue` (1 key)
- `src/components/dashboard/DashboardTabNav.vue` (1 key)
- `src/components/dashboard/BrowserPreviewFrame.vue` (8 keys)

#### Estimated Creator-Only Keys: 200-250 keys

These include:
- All `web.dashboard.*` (4 keys)
- All `web.account.*` (14 keys)
- All `web.domains.*` (2 keys)
- Most of `web.private.*` (34 keys - metadata viewing)
- Domain verification flat keys (~30 keys)
- Dashboard-specific flat keys (~50 keys)
- Customization/branding keys (~40 keys)

### 3. SHARED Components (Both User Types)

#### Secret Form
- `src/components/secrets/form/SecretForm.vue` (14 keys)
  - Used in: Homepage, Dashboard, Branded homepage
  - Keys: `web.secrets.*`, `web.homepage.*` (password generation)

#### Authentication
- `src/views/auth/Signin.vue` (4 keys)
- `src/views/auth/Signup.vue` (2 keys)
- `src/components/auth/SignInForm.vue` (6 keys)
- `src/components/auth/SignUpForm.vue` (8 keys)

#### Public Pages
- `src/views/Homepage.vue` (minimal - mostly SecretForm)
- `src/views/BrandedHomepage.vue` (3 keys)
- `src/views/Feedback.vue` (6 keys)

#### Estimated Shared Keys: 100-150 keys

These include:
- All `web.COMMON.*` (81 keys) - used everywhere
- All `web.LABELS.*` (43 keys) - generic labels
- `web.login.*` (5 keys)
- `web.signup.*` (2 keys)
- `web.homepage.*` (20 keys)
- Some `web.STATUS.*` keys
- Auth-related flat keys

---

## Key Usage Patterns

### High-Frequency Components (Most i18n Usage)

1. **SecretMetadataTable.vue** - 24 translation calls
   - Purpose: Display recent secrets for creators
   - User Type: **Creators only**

2. **VerifyDomainDetails.vue** - 20 translation calls
   - Purpose: Domain verification instructions
   - User Type: **Creators only**

3. **SecretDisplayCase (canonical)** - 14 translation calls
   - Purpose: Display secret content to recipient
   - User Type: **Recipients only**

4. **SecretForm.vue** - 14 translation calls
   - Purpose: Create new secrets
   - User Type: **Both** (homepage + dashboard)

5. **BurnSecret.vue** - 14 translation calls
   - Purpose: Confirm secret deletion
   - User Type: **Both** (creators burn own, recipients burn viewed)

### Translation Priority Tiers

Based on component analysis, here's the priority for translations:

#### Tier 1: Critical (Recipients + Core UX) - ~100 keys
- All recipient-facing keys
- Authentication flow
- Error messages
- Core navigation

#### Tier 2: Important (Creators + Account Management) - ~150 keys
- Dashboard and recent secrets
- Secret creation form (extended options)
- Account settings
- Metadata viewing

#### Tier 3: Advanced Features - ~200 keys
- Custom domains management
- Domain branding
- API keys
- Billing

#### Tier 4: Marketing/Optional - ~400 keys
- Homepage taglines and CTAs
- Testimonials
- Feature descriptions
- Help documentation
- Colonel (admin) interface
- Flat keys (many seem unused)

---

## Reorganization Recommendations

### Strategy 1: User-Type Segmentation (Recommended)

Reorganize locale files into clear user-type namespaces:

```json
{
  "recipient": {
    "secret_view": {
      "title": "You have a message",
      "warning_once": "Careful: we will only show it once.",
      "passphrase_prompt": "Enter the passphrase here",
      "click_to_reveal": "Click to reveal →",
      "copy_button": "Copy to Clipboard",
      "safely_close": "You can safely close this tab"
    },
    "secret_burn": {
      "title": "Burn this secret",
      "confirmation": "Are you sure you want to burn this secret?",
      "confirm_button": "Yes, burn this secret",
      "security_notice": "Burning a secret will delete it before it has been received."
    },
    "errors": {
      "not_found": "That information is no longer available",
      "already_viewed": "Information shared through this service can only be viewed once"
    },
    "help": {
      "need_help": "Need help?",
      "contact_sender": "Contact the person who sent you this link"
    }
  },
  "creator": {
    "dashboard": {
      "title": "Dashboard",
      "no_secrets": "You haven't created any secrets yet",
      "get_started": "Get started by creating your first secret"
    },
    "secrets": {
      "metadata_title": "Your Secret Details",
      "viewed": "Viewed",
      "not_received": "Not Received",
      "burn_action": "Burn this secret"
    },
    "domains": {
      "add_domain": "Add your domain",
      "verify_domain": "Verify your domain",
      "dns_instructions": "Add this hostname to your DNS configuration"
    },
    "account": {
      "settings": "Account Settings",
      "change_password": "Change Password",
      "api_keys": "API Keys",
      "billing": "Billing"
    }
  },
  "shared": {
    "common": {
      "loading": "Loading...",
      "submit": "Submit",
      "cancel": "Cancel",
      "confirm": "Confirm",
      "back": "Back",
      "close": "Close"
    },
    "auth": {
      "sign_in": "Sign In",
      "sign_up": "Sign Up",
      "email_placeholder": "e.g. tom@myspace.com",
      "password": "Password",
      "forgot_password": "Forgot your password?"
    },
    "secret_form": {
      "placeholder": "Secret content goes here...",
      "passphrase": "Passphrase",
      "recipient": "Recipient Address",
      "expiration": "Expiration time",
      "create_button": "Create a secret link"
    },
    "errors": {
      "unexpected": "An unexpected error occurred",
      "try_again": "Please try again"
    }
  },
  "public": {
    "homepage": {
      "tagline": "Secure links that only work once",
      "description": "Keep sensitive information out of your chat logs and email",
      "cta_title": "Share a secret",
      "sign_up": "Sign up free"
    },
    "footer": {
      "about": "About",
      "privacy_policy": "Privacy Policy",
      "terms": "Terms of Service",
      "powered_by": "Powered by Onetime Secret"
    }
  }
}
```

**Benefits:**
- Clear separation of recipient vs. creator keys
- Easy to identify which keys are essential for translation
- Reduced translation costs (focus on recipient + shared first)
- Better code organization and maintainability

**Migration Effort:** High (requires updating all $t() calls in components)

---

### Strategy 2: Phased Translation Tiers

Keep current structure but add tier metadata for translation prioritization:

```json
{
  "_tiers": {
    "tier1_critical": ["recipient.*", "shared.common.*", "shared.auth.*"],
    "tier2_important": ["creator.dashboard.*", "creator.secrets.*"],
    "tier3_advanced": ["creator.domains.*", "creator.account.*"],
    "tier4_optional": ["public.homepage.*", "marketing.*"]
  },
  "recipient": { ... },
  "creator": { ... },
  "shared": { ... }
}
```

**Benefits:**
- Can incrementally translate (start with tier 1, expand to tier 2, etc.)
- Clear documentation for translators on priority
- Reduced initial translation costs

**Migration Effort:** Medium (requires documentation + tooling updates)

---

### Strategy 3: Minimal Refactor - Namespace Cleanup

Improve current structure without major reorganization:

#### Current Issues to Fix:
1. **Consolidate flat keys**: 427 flat keys should move into web.* namespaces
2. **Rename confusing namespaces**:
   - `web.private` → `web.metadata` (creator's metadata viewing)
   - `web.shared` → `web.recipient` (most are recipient-specific)
3. **Add new namespaces**:
   - `web.recipient.*` - Recipient-only keys
   - `web.creator.*` - Creator-only keys

#### Proposed Structure:
```json
{
  "web": {
    "COMMON": { ... },        // Keep - universal UI elements
    "LABELS": { ... },        // Keep - generic labels
    "STATUS": { ... },        // Keep - status messages
    "UNITS": { ... },         // Keep - time units, etc.

    "recipient": {            // NEW - recipient-only
      "secret_view": { ... },
      "secret_burn": { ... },
      "help": { ... }
    },

    "creator": {              // NEW - creator-only
      "dashboard": { ... },
      "metadata": { ... },    // Moved from web.private
      "domains": { ... },
      "account": { ... }
    },

    "auth": {                 // Merged web.login + web.signup
      "signin": { ... },
      "signup": { ... },
      "password_reset": { ... }
    },

    "public": {               // Public pages
      "homepage": { ... },
      "footer": { ... }
    },

    "secrets": { ... },       // Secret form (shared)
    "feedback": { ... },      // Keep
    "help": { ... }           // Keep
  }
}
```

**Benefits:**
- Clearer organization without breaking changes
- Easier to identify recipient vs. creator keys
- Consolidates flat keys into proper namespaces

**Migration Effort:** Medium (requires consolidating flat keys + renaming)

---

### Strategy 4: Split Locale Files by User Type

Create separate locale files for different user contexts:

```
src/locales/
  ├── recipient/
  │   ├── en.json          (~100 keys)
  │   ├── es.json
  │   └── ...
  ├── creator/
  │   ├── en.json          (~300 keys)
  │   ├── es.json
  │   └── ...
  ├── shared/
  │   ├── en.json          (~150 keys)
  │   ├── es.json
  │   └── ...
  └── marketing/
      ├── en.json          (~300 keys)
      └── ...
```

**Benefits:**
- Can translate recipient.json first (highest priority)
- Smaller files = easier for translators to work with
- Can load only necessary translations per route (performance)
- Clear separation of concerns

**Migration Effort:** High (requires build system + i18n plugin updates)

---

## Recommended Approach

### Phase 1: Immediate (Strategy 3 - Minimal Refactor)

1. **Audit and consolidate flat keys** (427 keys)
   - Move to appropriate web.* namespaces
   - Document which keys are actually used (many may be orphaned)

2. **Add user-type namespaces**:
   - Create `web.recipient.*` for recipient-only keys
   - Create `web.creator.*` for creator-only keys

3. **Rename confusing namespaces**:
   - `web.private` → `web.creator.metadata`
   - `web.shared` → `web.recipient.shared` (or move to web.recipient.*)

4. **Document translation tiers** in README:
   - List which namespaces are Tier 1/2/3/4
   - Provide key counts for translator estimation

### Phase 2: Medium-term (Strategy 2 - Phased Translations)

1. **Create translation priority guide**:
   - Document which keys recipients see
   - Which keys creators see
   - Which keys are marketing/optional

2. **Update translation workflow**:
   - New languages start with Tier 1 (recipient keys)
   - Expand to Tier 2 (creator keys) once budget allows
   - Tier 3/4 optional for community contributions

### Phase 3: Long-term (Strategy 4 - Split Files)

1. **Split locale files by context**:
   - Separate recipient, creator, shared, marketing
   - Update build system to merge at compile time
   - Load only necessary translations per route

2. **Optimize bundle size**:
   - Recipients only download ~100 keys
   - Creators download ~400 keys
   - Marketing content lazy-loaded

---

## Implementation Checklist

### Immediate Actions

- [ ] Audit flat keys - identify which are actually used in code
- [ ] Remove unused keys (likely 50-100 orphaned keys)
- [ ] Create `web.recipient.*` namespace
- [ ] Create `web.creator.*` namespace
- [ ] Move recipient-specific keys from `web.shared` to `web.recipient`
- [ ] Move creator-specific keys from `web.private` to `web.creator.metadata`
- [ ] Update components to use new namespace structure
- [ ] Document translation priority tiers in CONTRIBUTING.md

### Medium-term Actions

- [ ] Create translation guide with key counts per tier
- [ ] Update translation workflow documentation
- [ ] Set up automated key usage tracking (which keys are actually rendered)
- [ ] Create script to generate "translation coverage report" per language
- [ ] Migrate remaining flat keys to proper namespaces

### Long-term Actions

- [ ] Evaluate splitting locale files by user context
- [ ] Implement dynamic i18n loading per route
- [ ] Optimize bundle size with lazy-loaded translations
- [ ] Create automated tests to prevent flat keys from being added
- [ ] Set up CI checks for translation completeness by tier

---

## Translation Cost Reduction Estimates

### Current State
- **Total keys**: ~850
- **Cost per language** (estimated): $850 - $1,700 @ $1-2 per key
- **30 languages**: $25,500 - $51,000 total

### With Tier-Based Approach

**Tier 1 (Recipient + Core): ~100 keys**
- Cost per language: $100 - $200
- 30 languages: $3,000 - $6,000

**Tier 1 + 2 (Add Creator Features): ~250 keys**
- Cost per language: $250 - $500
- 30 languages: $7,500 - $15,000

**Tier 1 + 2 + 3 (Full Functionality): ~450 keys**
- Cost per language: $450 - $900
- 30 languages: $13,500 - $27,000

**Potential Savings**:
- Focus on Tier 1+2: Save $12,000 - $36,000 (50-70% reduction)
- Community contributions for Tier 3+4 (marketing)

---

## Conclusion

The current i18n structure mixes recipient-facing, creator-facing, and marketing content without clear delineation. This leads to:
- High translation costs (850+ keys × 30 languages)
- Difficulty prioritizing translations
- Confusion for translators about context

**Recommended path forward:**

1. **Immediate**: Clean up flat keys, add user-type namespaces (web.recipient.*, web.creator.*)
2. **Short-term**: Document translation tiers, focus new languages on Tier 1 (recipients)
3. **Long-term**: Consider splitting locale files for optimized loading

This approach will:
- Reduce translation costs by 50-70% initially
- Improve code maintainability
- Provide better experience for both recipients (always translated) and creators (progressively enhanced)
- Enable community contributions for lower-priority content

---

## Appendix: Key Statistics

### Components by i18n Usage Intensity

**High Usage (10+ keys):**
- SecretMetadataTable.vue (24) - Creator
- VerifyDomainDetails.vue (20) - Creator
- MetadataFAQ.vue (19) - Creator
- SecretDisplayCase.vue (14) - Recipient
- BurnSecret.vue (14) - Both
- SecretForm.vue (14) - Both
- AccountDeleteButton.vue (12) - Creator
- AccountBillingSection.vue (11) - Creator
- DashboardDomainVerify.vue (11) - Creator
- SecretDisplayHelpContent.vue (11) - Recipient

**Medium Usage (5-9 keys):**
- Most auth components (5-8 keys)
- Footer components (5-9 keys)
- Help modals (6-7 keys)

**Low Usage (1-4 keys):**
- Most other components

### Namespace Distribution

| Namespace Type | Count | % of Total |
|----------------|-------|------------|
| Flat keys | 427 | 50% |
| web.COMMON | 81 | 10% |
| web.LABELS | 43 | 5% |
| web.private | 34 | 4% |
| web.STATUS | 29 | 3% |
| web.homepage | 20 | 2% |
| web.footer | 20 | 2% |
| Other namespaces | ~196 | 24% |

**Total**: ~850 keys
