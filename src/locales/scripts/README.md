# Locale Scripts

Organized tools for managing i18n locale files in the Onetime Secret project.

## Directory Structure

### `/harmonize`
Synchronization and conflict resolution scripts for maintaining consistency across locale files.
- Fix structural conflicts between locale files
- Harmonize key structures with base English locale
- CI/CD integration for automated maintenance

### `/validate`
Validation tools for checking locale file integrity.
- Verify JSON structure and key consistency
- Identify missing or extra keys
- Pre-commit validation checks

### `/debug`
Diagnostic tools for troubleshooting locale file issues.
- Analyze structural conflicts and type mismatches
- Generate detailed reports of locale discrepancies
- Debug harmonization failures

### `/migrate`
Migration tools for refactoring locale structures.
- Migrate keys between different i18n versions
- Apply bulk translations from external sources
- Handle breaking changes in locale structure

### `/utils`
General utility scripts for locale maintenance.
- Fix Unicode encoding issues
- Search for i18n key usage in codebase
- Generate translation templates

### `/experiments`
Experimental scripts for testing new approaches.
- Prototype scripts not ready for production
- Testing ground for new locale management strategies

## Common Workflows

### 1. Fix and Harmonize All Locales
```bash
# Step 1: Fix structural conflicts
./harmonize/fix-all-locale-conflicts -v

# Step 2: Harmonize with base locale
./harmonize/harmonize-locale-files -v

# Step 3: Validate results
./validate/check-locale-files
```

### 2. Debug Locale Issues
```bash
# Analyze specific locale
./debug/debug-locale-structure.sh src/locales/fr_FR.json

# Check all locales
./debug/debug-all-locales -v
```

### 3. Add New Translation
```bash
# Generate template
./utils/generate-translation-template.sh > new_locale.json

# Fix conflicts after editing
./harmonize/fix-locale-conflicts new_locale.json

# Harmonize with base
./harmonize/harmonize-locale-file new_locale.json
```

## Script Options

Most scripts support these common options:
- `-q` : Quiet mode (suppress output)
- `-f` : Filename-only output (for scripting)
- `-v` : Verbose output (detailed information)
- `-c` : Copy values from base file (where applicable)

## Base Locale

The default base locale is `en.json`. Override with:
```bash
BASELOCALE=en BASEPATH=src/locales/en.json ./script-name
```

## Exit Codes

- `0` : Success / No issues found
- `1` : Failure / Issues detected

## Dependencies

- `jq` : JSON processing (required)
- `python3` : For Python migration scripts
- `bash` : Shell scripts (v4+ recommended)
