# Translation Scripts Documentation

This directory contains scripts for managing locale file harmonization and translation workflows.

## Scripts Overview

### `harmonize-locale-files`
Main script that synchronizes all locale files with the structure of `en.json`. Ensures all locale files have the same keys, hierarchy, and ordering.

### `github-action-harmonize.sh`
GitHub Actions wrapper for the harmonize script. Handles CI/CD integration and outputs workflow variables.

### `generate-translation-template.sh`
Generates JSON templates for keys that need translation after harmonization.

**Usage:**
```bash
./src/locales/scripts/generate-translation-template.sh [options]

Options:
  -o, --output DIR    Output directory (default: ./translation-templates)
  -h, --help          Show help message
```

### `apply-translations.sh`
Applies completed translations back to locale files.

**Usage:**
```bash
./src/locales/scripts/apply-translations.sh <translation_file> <locale>

Arguments:
  translation_file    Path to JSON file with translations
  locale             Target locale code (e.g., 'fr', 'es', 'de')
```

## Translation Workflow

### 1. Automatic Harmonization
When `src/locales/en.json` is updated, GitHub Actions automatically:
- Harmonizes all locale files
- Generates translation templates for missing keys
- Creates a PR with changes and translation artifacts

### 2. Translation Process
1. Download translation templates from GitHub Actions artifacts
2. Translate English phrases in the JSON templates
3. Keep JSON structure intact - only change values, not keys
4. Submit translations via PR or issue

### 3. Integration
Apply translations using the integration script:
```bash
./src/locales/scripts/apply-translations.sh translated-file.json locale-code
```

## File Structure

```
src/locales/
├── scripts/
│   ├── harmonize-locale-files           # Main harmonization script
│   ├── harmonize-locale-file           # Single file harmonizer
│   ├── github-action-harmonize.sh      # CI/CD wrapper
│   ├── generate-translation-template.sh # Template generator
│   ├── apply-translations.sh           # Translation applier
│   └── README.md                       # This file
├── en.json                             # Source English locale
├── fr.json                             # French translations
├── es.json                             # Spanish translations
└── ...                                 # Other locale files
```

## Generated Files

### Translation Templates
- `{locale}-translation-needed.json` - JSON with keys needing translation
- `{locale}-report.md` - Individual locale report with instructions

### Workflow Artifacts
- `translation-templates-and-reports` - Complete artifact package
- `enhanced-report.md` - Comprehensive translation status report

## Requirements

- **jq** - JSON processor for template generation and application
- **git** - Version control for detecting changes
- **bash** - Shell environment for script execution

## Best Practices

### For Translators
1. Preserve JSON structure and formatting
2. Escape quotes and special characters properly
3. Maintain consistent terminology across keys
4. Test JSON validity before submission

### For Developers
1. Always update `en.json` first
2. Use descriptive key names that provide context
3. Group related keys in logical hierarchies
4. Run harmonization locally before committing

## Troubleshooting

### Common Issues

**Invalid JSON after translation:**
```bash
# Validate JSON before applying
jq empty translated-file.json
```

**Missing translation keys:**
```bash
# Regenerate templates
./src/locales/scripts/generate-translation-template.sh
```

**Permission errors:**
```bash
# Make scripts executable
chmod +x src/locales/scripts/*.sh
```

### Error Recovery

**Restore from backup:**
```bash
# Backups are automatically created as .backup files
cp src/locales/locale.json.backup src/locales/locale.json
```

**Reset harmonization:**
```bash
git checkout HEAD -- src/locales/*.json
```

## GitHub Actions Integration

The workflow automatically triggers on:
- Push to `develop` or `i18n/**` branches affecting `en.json`
- Pull requests modifying `en.json`
- Manual workflow dispatch

### Workflow Outputs
- Translation templates as downloadable artifacts
- Automated PRs with harmonized locale files
- Comprehensive translation status reports
