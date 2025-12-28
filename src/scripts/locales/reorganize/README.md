# Locale Reorganization Scripts

Tools for auditing and reorganizing keys from `uncategorized.json` into proper categorized locale files.

## Overview

The Onetime Secret project uses a hierarchical i18n structure where translation keys are organized into feature-specific files (e.g., `feature-domains.json`, `auth.json`). Over time, new keys accumulate in `uncategorized.json`. These scripts help:

1. **Audit** uncategorized files for quality issues before reorganization
2. **Reorganize** keys into proper files based on a category mapping configuration

## Scripts

### `audit-uncategorized.py`

Scans `uncategorized.json` files for quality issues that should be addressed before reorganization.

**Detects:**
- Near-duplicate keys (similarity >= 0.85)
- Near-duplicate values (similarity >= 0.95)
- Malformed values (backticks, unclosed `{0}` placeholders, JS template literals)
- Empty values
- Truncated keys (abrupt endings, numeric suffixes)

**Usage:**

```bash
# Audit single locale
./audit-uncategorized.py --locale en

# Audit all locales
./audit-uncategorized.py --all

# Output JSON report
./audit-uncategorized.py --locale en --json

# Save JSON report to file
./audit-uncategorized.py --all --output audit-report.json

# Verbose mode (show full values)
./audit-uncategorized.py --locale en -v

# Custom thresholds
./audit-uncategorized.py --locale en --key-threshold 0.90 --value-threshold 0.98
```

**Exit codes:**
- `0` = No issues found
- `1` = Issues detected

**Known issues the script detects:**
- Lines 44/46: `about-onetime-secret-0` vs `about-onetime-secret` (duplicate with suffix)
- Lines 115/116: `this-is-an-interactive-preview-o` (truncated key)
- Line 240: `customer-verified-verified-not-verified` (contains JS template literal)

### `reorganize-uncategorized.py`

Moves keys from `uncategorized.json` to their target files based on a category mapping configuration.

**Features:**
- Atomic writes with backup files (`.bak`)
- Verification pass ensures no keys lost
- Dry-run mode for safe testing
- Parallel processing for `--all` mode
- Merges into existing files (preserves existing keys)
- Creates nested structures from flat keys

**Usage:**

```bash
# Preview changes (dry run)
./reorganize-uncategorized.py --locale en --dry-run

# Apply to single locale
./reorganize-uncategorized.py --locale en

# Apply to all locales with backups
./reorganize-uncategorized.py --all --backup

# Skip backups (not recommended)
./reorganize-uncategorized.py --locale en --no-backup

# Custom mapping file
./reorganize-uncategorized.py --locale en --mapping custom-mapping.json

# Parallel processing with 8 workers
./reorganize-uncategorized.py --all --workers 8

# JSON output
./reorganize-uncategorized.py --all --json
```

**Exit codes:**
- `0` = Success
- `1` = Errors occurred

## Configuration

### `category-mapping.json`

The reorganization script requires a `category-mapping.json` file that defines where each key should be moved.

**Structure:**

```json
{
  "mappings": [
    {
      "source_key": "add-domain",
      "target_file": "feature-domains.json",
      "target_path": "web.domains.add-domain"
    },
    {
      "source_key": "domain-status",
      "target_file": "feature-domains.json",
      "target_path": "web.domains.domain-status"
    },
    {
      "source_key": "sign-in-to-your-account",
      "target_file": "auth.json",
      "target_path": "web.auth.sign-in-heading"
    }
  ]
}
```

**Fields:**
- `source_key`: The flat key name in `uncategorized.json`
- `target_file`: The JSON file to move the key to
- `target_path`: The nested path within the target file (dot-separated)

**Example transformation:**

Before (`uncategorized.json`):
```json
{
  "add-domain": "Add Domain",
  "sign-in-to-your-account": "Welcome Back"
}
```

After (`feature-domains.json`):
```json
{
  "web": {
    "domains": {
      "add-domain": "Add Domain"
    }
  }
}
```

After (`auth.json`):
```json
{
  "web": {
    "auth": {
      "sign-in-heading": "Welcome Back"
    }
  }
}
```

## Workflow

### Recommended workflow for reorganizing locales:

1. **Audit first** - Find and fix issues before reorganization:

   ```bash
   ./audit-uncategorized.py --locale en --output audit-en.json
   ```

2. **Fix issues** - Address duplicates, malformed values, etc. in `uncategorized.json`

3. **Create mapping** - Build `category-mapping.json` for keys to move

4. **Dry run** - Preview changes:

   ```bash
   ./reorganize-uncategorized.py --locale en --dry-run
   ```

5. **Apply to English** - English is the base locale:

   ```bash
   ./reorganize-uncategorized.py --locale en --backup
   ```

6. **Verify** - Check the changes:

   ```bash
   cat src/locales/en/feature-domains.json
   ```

7. **Apply to all** - Once English is correct, apply to other locales:

   ```bash
   ./reorganize-uncategorized.py --all --backup --workers 8
   ```

8. **Harmonize** - Sync other locales with English structure:

   ```bash
   ../harmonize/harmonize-locale-file.py -v fr_FR
   ```

## Preserving Interpolation Markers

Both scripts preserve interpolation markers like `{0}`, `{1}`, etc. The audit script will flag unclosed placeholders (e.g., `{0` without closing `}`) as malformed values.

## File Structure

```
src/scripts/locales/reorganize/
├── README.md                      # This file
├── audit-uncategorized.py         # Quality audit script
├── reorganize-uncategorized.py    # Reorganization script
├── category-mapping.json          # Key mapping configuration (you create this)
└── test-fixtures/                 # Test data
```

## Integration with Other Scripts

- **harmonize**: After reorganization, use `harmonize-locale-file.py` to sync non-English locales
- **validate**: Use `validate-locale-json.py` to verify JSON syntax after changes
- **split-locale**: Use `verify-split.sh` pattern for verification

## Troubleshooting

### "Category mapping file not found"

Create a `category-mapping.json` file in the same directory as the script, or specify a path with `--mapping`.

### "Target path already exists"

The key already exists at the target location. Either:
- Remove it from the mapping (it's already where it should be)
- Choose a different target path
- Manually resolve the conflict

### "Path conflict: X is not a dict"

The target path tries to nest under a value that isn't an object. For example, setting `web.domains.add-domain.label` when `web.domains.add-domain` is already a string.

### Partial failures

If the script fails mid-operation, check for `.bak` files to restore from:

```bash
# List backup files
ls -la src/locales/en/*.bak

# Restore a file
cp src/locales/en/feature-domains.json.bak src/locales/en/feature-domains.json
```

## Exit Codes Summary

| Script | Code | Meaning |
|--------|------|---------|
| audit-uncategorized.py | 0 | No issues found |
| audit-uncategorized.py | 1 | Issues detected |
| reorganize-uncategorized.py | 0 | Success |
| reorganize-uncategorized.py | 1 | Errors occurred |
