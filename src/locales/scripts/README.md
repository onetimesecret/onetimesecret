# Locale Migration Scripts

This directory contains scripts for managing locale file organization.

## split-locale.ts

Splits monolithic locale JSON files into multiple feature-domain-specific files.

### Purpose

Onetime Secret's translation files have grown large (800+ keys). This script reorganizes a single locale file into 16 smaller files organized by feature domain, making them easier to maintain, translate, and code-split.

### Usage

```bash
# Split a single locale file
ts-node src/locales/scripts/split-locale.ts src/locales/en.json

# Split multiple locale files at once
ts-node src/locales/scripts/split-locale.ts src/locales/en.json src/locales/fr.json src/locales/de.json
```

### What It Does

For each input file (e.g., `src/locales/en.json`), the script:

1. **Creates a directory** using the file's basename: `src/locales/en/`
2. **Splits content** into 16 files based on feature domains
3. **Verifies reversibility** - Confirms that recombining split files produces identical JSON

### File Mapping

- `common.json` - Common UI elements, labels, status, features, units, titles (plus all flat top-level keys)
- `ui.json` - ARIA labels, instructions, validation messages
- `layout.json` - Footer, navigation, site metadata, help
- `homepage.json` - Homepage marketing content
- `auth.json` - Basic authentication (login, signup, password reset)
- `auth-advanced.json` - MFA, sessions, recovery codes, WebAuthn, magic links
- `secrets.json` - Secret creation, viewing, sharing
- `incoming.json` - Incoming workflow
- `dashboard.json` - Dashboard and recent items
- `account.json` - Account management and settings
- `regions.json` - Data sovereignty
- `domains.json` - Custom domains
- `teams.json` - Team management
- `organizations.json` - Organization management
- `billing.json` - Billing, plans, invoices
- `colonel.json` - Admin interface and feedback

### Reversibility Guarantee

The script automatically verifies that recombining the split files produces identical JSON to the original (key order may differ).

If verification fails, debug files are created in `src/locales/{locale}/_debug/`.
