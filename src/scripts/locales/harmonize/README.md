# Harmonize Scripts

Tools for synchronizing locale file structures with the base English locale.

## Locale Structure

Each locale is a directory containing 17 JSON files:
- `_common.json` - Common translations
- `account.json`, `account-billing.json` - Account management
- `auth.json`, `auth-advanced.json` - Authentication
- `colonel.json`, `dashboard.json` - Admin and dashboard
- `email.json` - Email templates
- `feature-*.json` - Feature-specific translations (domains, incoming, organizations, regions, secrets, teams)
- `homepage.json`, `layout.json` - UI structure
- `uncategorized.json` - Miscellaneous translations

All scripts process each locale file individually against its English counterpart.

## Scripts

### Individual Locale Processing
- `harmonize-locale-file LOCALE` - Synchronizes all files in a locale directory with base English
- `fix-locale-conflicts LOCALE` - Resolves type mismatches in all files for a locale

Arguments:
- `LOCALE` - Locale code (e.g., `es`, `fr_FR`, `pt_BR`)
- `-q` - Quiet mode
- `-f` - Filename only output (for errors)
- `-v` - Verbose output
- `-c` - Copy values from base file for missing keys

### Batch Processing
- `harmonize-all-locale-files` - Batch harmonize all locale directories
- `fix-all-locale-conflicts` - Batch fix structural conflicts in all locales

### CI/CD Integration
- `github-action-harmonize.sh` - GitHub Actions wrapper

## Usage

Process a single locale:
```bash
./harmonize-locale-file es
./fix-locale-conflicts -v fr_FR
```

Process all locales:
```bash
./fix-all-locale-conflicts
./harmonize-all-locale-files
```

Recommended workflow: First run `fix-all-locale-conflicts`, then `harmonize-all-locale-files`.
