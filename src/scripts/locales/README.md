# Locale Scripts

Organized tools for managing i18n locale files in the Onetime Secret project.

## Directory Structure

### Root Scripts

- **`generate-i18n-types.ts`** - Generates TypeScript types from locale JSON files for compile-time key validation

### `/harmonize`
Synchronization and conflict resolution scripts for maintaining consistency across locale files.
- **`create-missing-locale-files.sh`** - Creates empty `{}` JSON files for locales missing files that exist in `en/`
- **`harmonize-locale-file.py`** - Repairs locale files to match English key structure
- **`harmonize-all-locale-files`** - Wrapper to harmonize all locales
- **`validate-locale-json.py`** - Validates JSON structure
- **`github-action-harmonize.sh`** - CI/CD integration

### `/validate`
Pre-commit validation tools for checking locale file integrity.
- Verify JSON structure and key consistency
- Identify missing or extra keys

### `/debug`
Diagnostic tools for troubleshooting locale file issues.
- Analyze structural conflicts and type mismatches
- Generate detailed reports of locale discrepancies

### `/audit`
Translation coverage analysis tools.
- **`audit-translations.js`** - Identify missing translations across locales
- **`extract-i18n-manifest.py`** - Extract i18n key manifest from codebase
- **`analyze-by-file.js`** - Break down missing keys by file
- **`analyze-common-missing.js`** - Find keys missing across many locales

### `/translate`
AI-powered translation using Claude CLI.
- **`claude-translate-locale.py`** - Translate a single locale from git diff

### `/migrate`
Migration tools for locale key transformations.
- **`migrate-camel-to-snake.py`** - Migrates camelCase keys to snake_case (run with `--dry-run` first)
- **`apply-translations.sh`** - Apply bulk translations from external sources

### `/utils`
General utility scripts for locale maintenance.
- **`fix-json-unicode.py`** - Fix Unicode encoding issues from translation tools
- **`generate-translation-template.sh`** - Generate translation templates for contributors

## Common Workflows

### 1. Harmonize All Locales
```bash
# Harmonize all locale files with English structure
./harmonize/harmonize-all-locale-files

# Validate results
./validate/check-locale-files
```

### 2. Add New Locale File Type
```bash
# After adding a new JSON file to src/locales/en/
./harmonize/create-missing-locale-files.sh --dry-run  # Preview
./harmonize/create-missing-locale-files.sh            # Create empty files
```

### 3. Migrate camelCase Keys
```bash
# Preview changes
python3 ./migrate/migrate-camel-to-snake.py --dry-run

# Apply migration (creates backup)
python3 ./migrate/migrate-camel-to-snake.py
```

### 4. Debug Locale Issues
```bash
# Analyze specific locale directory
./debug/debug-locale-structure.sh src/locales/fr_FR/

# Check all locales
./debug/debug-all-locales -v
```

### 5. Audit Translation Coverage
```bash
node ./audit/audit-translations.js
```

### 6. Translate Locales with Claude
```bash
# Single locale
./translate/claude-translate-locale.py pt_PT --verbose --stream

# All locales with changed email.json files
git diff --name-only | grep 'email.json' | sed 's|src/locales/\(.*\)/email.json|\1|' | while read locale; do
  ./translate/claude-translate-locale.py "$locale" --verbose --stream
done
```

## Script Options

Most scripts support these common options:
- `-q` : Quiet mode (suppress output)
- `-v` : Verbose output (detailed information)
- `--dry-run` : Preview changes without modifying files

## Dependencies

- `jq` : JSON processing (required for bash scripts)
- `python3` : For Python scripts
- `node` : For JavaScript scripts
- `tsx` : For TypeScript execution
