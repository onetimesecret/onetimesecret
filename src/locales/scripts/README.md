# Locale Migration Scripts

This directory contains scripts for managing locale file organization through a two-step splitting process.

## Overview

Onetime Secret's translation files have grown large (800+ keys) with an inconsistent structure mixing flat keys, `web.*` nested content, and `email.*` content. These scripts reorganize locale files into a clean, modular structure.

## The Two-Step Process

### Step 1: Structural Split (`split-locale-step1.ts`)

Separates locale files by top-level structure into:
- `web.json` - All UI and application content
- `email.json` - Email template content
- `uncategorized.json` - Flat uncategorized keys (result of rapid development)

**Usage:**
```bash
# Split by top-level structure
ts-node src/locales/scripts/split-locale-step1.ts src/locales/en.json

# Process multiple locales
ts-node src/locales/scripts/split-locale-step1.ts src/locales/*.json
```

**Output for `en.json`:**
```
src/locales/en/
├── web.json              (422 keys) - UI and application content
├── email.json            (14 keys)  - Email templates
└── uncategorized.json    (426 keys) - Flat uncategorized keys
```

### Step 2: Feature Domain Split (`split-locale-step2.ts`)

Splits `web.json` into 16 feature-specific files for better organization and code-splitting.

**Usage:**
```bash
# Split web.json by feature domains
ts-node src/locales/scripts/split-locale-step2.ts src/locales/en/web.json

# Process multiple locales
ts-node src/locales/scripts/split-locale-step2.ts src/locales/*/web.json
```

**Output for `en/web.json`:**
```
src/locales/en/
├── _common.json          (184 keys) - Common UI, labels, status, features
├── ui.json               (8 keys)   - ARIA labels, instructions
├── layout.json           (45 keys)  - Footer, navigation, site metadata
├── homepage.json         (26 keys)  - Homepage marketing
├── auth.json             (10 keys)  - Basic authentication
├── auth-advanced.json    (1 keys)   - MFA, sessions, recovery codes
├── secrets.json          (54 keys)  - Secret management
├── incoming.json         (13 keys)  - Incoming workflow
├── dashboard.json        (6 keys)   - Dashboard views
├── account.json          (22 keys)  - Account management
├── regions.json          (1 keys)   - Data sovereignty
├── domains.json          (4 keys)   - Custom domains
├── teams.json            (1 keys)   - Team management
├── organizations.json    (1 keys)   - Organization management
├── billing.json          (1 keys)   - Billing & subscriptions
└── colonel.json          (60 keys)  - Admin interface
```

## Complete Workflow

```bash
# 1. Run Step 1: Split by structure
ts-node src/locales/scripts/split-locale-step1.ts src/locales/en.json

# Output: src/locales/en/web.json, email.json, uncategorized.json

# 2. Run Step 2: Split web.json by feature
ts-node src/locales/scripts/split-locale-step2.ts src/locales/en/web.json

# Output: src/locales/en/_common.json, auth.json, secrets.json, etc.
```

## Final Structure

After running both steps on `en.json`:

```
src/locales/
├── en.json (original - unchanged)
└── en/
    ├── web.json              # Intermediate - can be kept or removed
    ├── email.json            # Email templates (from step 1)
    ├── uncategorized.json    # Flat keys (from step 1)
    ├── _common.json          # Common UI (from step 2)
    ├── auth.json             # Authentication (from step 2)
    ├── auth-advanced.json    # Advanced auth (from step 2)
    ├── secrets.json          # Secret features (from step 2)
    ├── incoming.json         # Incoming workflow (from step 2)
    ├── dashboard.json        # Dashboard (from step 2)
    ├── account.json          # Account management (from step 2)
    ├── regions.json          # Data sovereignty (from step 2)
    ├── domains.json          # Custom domains (from step 2)
    ├── teams.json            # Team management (from step 2)
    ├── organizations.json    # Organizations (from step 2)
    ├── billing.json          # Billing (from step 2)
    ├── colonel.json          # Admin interface (from step 2)
    ├── homepage.json         # Homepage (from step 2)
    ├── layout.json           # Layout/footer (from step 2)
    └── ui.json               # UI utilities (from step 2)
```

## File Descriptions

### Step 1 Outputs

- **web.json** - All content under the `web.*` key (UI, features, etc.)
- **email.json** - All content under the `email.*` key (email templates)
- **uncategorized.json** - All flat top-level keys (legacy quick-expansion keys)

### Step 2 Outputs (from web.json)

- **_common.json** - COMMON, LABELS, STATUS, FEATURES, UNITS, TITLES
- **ui.json** - ARIA labels, instructions, validation messages
- **layout.json** - Footer, navigation, site metadata, help
- **homepage.json** - Homepage marketing content
- **auth.json** - Basic authentication (login, signup, password reset)
- **auth-advanced.json** - MFA, sessions, recovery codes, WebAuthn, magic links
- **secrets.json** - Secret creation, viewing, sharing
- **incoming.json** - Incoming secret workflow
- **dashboard.json** - Dashboard and recent items
- **account.json** - Account management and settings
- **regions.json** - Data sovereignty and region selection
- **domains.json** - Custom domain management
- **teams.json** - Team management features
- **organizations.json** - Organization management
- **billing.json** - Billing, plans, invoices
- **colonel.json** - Admin interface and feedback

## Reversibility

Both scripts include automatic verification:
- **Step 1**: Verifies that `web.json + email.json + uncategorized.json = original file`
- **Step 2**: Verifies that recombining all 16 feature files = web.json

If verification fails, debug files are created in `src/locales/{locale}/_debug/` with sorted JSON for easy comparison.

## Integration with vue-i18n

After splitting, update your i18n configuration:

```typescript
// Option 1: Lazy load specific features
const messages = {
  en: {
    ...await import('./locales/en/_common.json'),
    ...await import('./locales/en/auth.json'),
    ...await import('./locales/en/secrets.json'),
    // ... load other files as needed
  }
};

// Option 2: Glob import all files
const localeFiles = import.meta.glob('./locales/en/*.json');
```

## Notes

- Original files (`en.json`, `fr.json`, etc.) are never modified
- Intermediate files (`web.json`) can be kept or deleted after Step 2
- Empty-looking files (e.g., `teams.json` with 1 key) indicate planned features
- All scripts are idempotent - safe to run multiple times
- The `_common.json` prefix ensures it loads first in alphabetical ordering

## Troubleshooting

### Step 1 Issues

**Verification fails:**
```bash
# Check debug files
diff -u src/locales/en/_debug/step1-original-sorted.json \
        src/locales/en/_debug/step1-combined-sorted.json
```

### Step 2 Issues

**Verification fails:**
```bash
# Check debug files
diff -u src/locales/en/_debug/step2-original-sorted.json \
        src/locales/en/_debug/step2-combined-sorted.json
```

**Missing features:**
- Some files may have minimal content (1-2 keys) for planned features
- This is normal and indicates features not yet fully implemented
