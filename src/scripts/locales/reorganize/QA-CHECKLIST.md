# Locale Reorganization QA Checklist

Quality assurance checklist for migrating 430 keys from `uncategorized.json` to 15 category files across 30 locales.

## Overview

- **Source**: `uncategorized.json` (430 keys per locale)
- **Target**: 15 category files
- **Exclusions**: 3 keys (`emoji-x`, `emoji-checkmark`, `min-width-1024px`)
- **Net Migration**: 427 keys distributed to category files
- **Locales**: 30 language directories

---

## Phase 1: Pre-Flight Checks

Complete these checks BEFORE running the reorganization script.

### 1.1 Environment Validation

- [ ] Python 3.8+ installed and accessible
- [ ] Working directory is project root
- [ ] Git repository is clean (no uncommitted changes)
- [ ] Current branch is correct for this work

```bash
# Verify environment
python3 --version
git status
pwd
```

### 1.2 Backup Creation

- [ ] Create snapshot of current state

```bash
# Create pre-reorganization snapshot
./src/scripts/locales/reorganize/verify-reorganization.py --pre-check ./pre-reorg-snapshot.json

# Verify snapshot was created
ls -la pre-reorg-snapshot.json
```

- [ ] Optionally create git stash or backup branch

```bash
git stash push -m "pre-reorganization backup"
# OR
git checkout -b backup/pre-reorganization
git checkout -
```

### 1.3 Source File Validation

- [ ] Verify uncategorized.json exists in English locale
- [ ] Confirm key count matches expected (430 keys)
- [ ] Check all JSON files have valid syntax

```bash
# Count keys in English uncategorized.json
python3 -c "import json; print(len(json.load(open('src/locales/en/uncategorized.json'))))"
# Expected: 430

# Validate JSON syntax across all locales
./src/scripts/locales/harmonize/validate-locale-json.py -v en
```

### 1.4 Target File Assessment

- [ ] Document which category files already exist
- [ ] Note any existing keys that must be preserved

```bash
# List existing category files in English
ls -la src/locales/en/*.json

# Count existing keys in each file
for f in src/locales/en/*.json; do
  echo "$(basename $f): $(python3 -c "import json; print(len(json.load(open('$f'))))" 2>/dev/null || echo 'N/A')"
done
```

---

## Phase 2: Reorganization Execution

### 2.1 Dry Run (if available)

- [ ] Run reorganization script in dry-run mode
- [ ] Review proposed changes
- [ ] Verify no unexpected file modifications

### 2.2 Execute Reorganization

- [ ] Run reorganization script on English locale first
- [ ] Verify English locale before proceeding

```bash
# Run on English first
./path/to/reorganize-script.py en

# Immediate verification
./src/scripts/locales/reorganize/verify-reorganization.py en --verbose
```

### 2.3 Batch Execution

- [ ] Run on remaining locales
- [ ] Monitor for errors during execution

---

## Phase 3: Post-Reorganization Verification

Run the verification script after reorganization completes.

### 3.1 Automated Verification

```bash
# Verify all locales
./src/scripts/locales/reorganize/verify-reorganization.py --verbose

# For CI integration (JSON output)
./src/scripts/locales/reorganize/verify-reorganization.py --json
```

### 3.2 Verification Checks

The script validates:

| Check | Description | Pass Criteria |
|-------|-------------|---------------|
| JSON Syntax | All files parse without errors | No JSON decode errors |
| Expected Files | All 15 category files exist | All files present |
| File Structure | Category files use `{ "web": { ... } }` | Proper nesting |
| No Duplicates | Each key in exactly one file | Zero duplicates |
| Key Count | Total keys >= original - excluded | >= 427 keys |
| Interpolation | Markers like `{0}` preserved | All markers intact |
| Balanced Chars | No unbalanced `{}[]()` | All balanced |

### 3.3 Manual Spot Checks

- [ ] **Random Sample**: Pick 5 random keys, verify they appear in correct category file
- [ ] **Interpolation Check**: Verify keys with `{0}`, `{1}` markers are correct

```bash
# Example: Check a specific key moved correctly
grep -r "your-feedback" src/locales/en/*.json
# Should appear in exactly one file
```

- [ ] **Visual Inspection**: Open 2-3 category files, confirm structure looks correct

---

## Phase 4: Integration Testing

### 4.1 Build Verification

- [ ] Run TypeScript type check
- [ ] Run frontend build

```bash
pnpm run type-check
pnpm run build
```

### 4.2 Runtime Verification

- [ ] Start development server
- [ ] Navigate to pages using reorganized keys
- [ ] Verify translations display correctly
- [ ] Check browser console for i18n warnings

```bash
# Start dev server and manually test
pnpm run dev
```

### 4.3 Test Suite

- [ ] Run frontend unit tests
- [ ] Run any i18n-specific tests

```bash
pnpm test
```

---

## Common Issues and Diagnosis

### Issue: "Key not found" at runtime

**Symptoms**: Missing translation warnings in console, fallback text displayed

**Diagnosis**:
```bash
# Find where the key ended up
grep -r "the-missing-key" src/locales/en/*.json

# Check if key exists in any locale
grep -r "the-missing-key" src/locales/*/
```

**Resolution**:
1. Verify key was migrated to expected category file
2. Check i18n import includes the new category file
3. Verify key path matches usage in components

### Issue: JSON Syntax Error

**Symptoms**: Verification script reports JSON decode error

**Diagnosis**:
```bash
# Validate specific file
python3 -c "import json; json.load(open('src/locales/XX/file.json'))"
```

**Resolution**:
1. Check for trailing commas
2. Check for unescaped quotes in values
3. Check for truncated content

### Issue: Duplicate Keys Found

**Symptoms**: Verification reports key in multiple files

**Diagnosis**:
```bash
# Find all occurrences
grep -r "duplicate-key" src/locales/en/*.json
```

**Resolution**:
1. Determine which file should own the key
2. Remove duplicate from other file(s)
3. Re-run verification

### Issue: Missing Interpolation Markers

**Symptoms**: Text displays `{0}` or `{1}` instead of values

**Diagnosis**:
```bash
# Compare original vs migrated
grep "key-name" pre-reorg-snapshot.json
grep "key-name" src/locales/en/category-file.json
```

**Resolution**:
1. Restore correct value from snapshot
2. Verify escaping is correct

---

## Rollback Procedure

If reorganization fails or causes issues:

### Option 1: Git Reset (Preferred)

```bash
# Discard all changes
git checkout -- src/locales/

# Or reset to specific commit
git reset --hard HEAD~1
```

### Option 2: Restore from Snapshot

```bash
# If you have pre-reorganization snapshot
# Requires custom restore script to reverse the migration
```

### Option 3: Restore from Backup Branch

```bash
git checkout backup/pre-reorganization -- src/locales/
```

---

## Sign-Off Checklist

Final approval before merging:

### Technical Sign-Off

- [ ] All automated verification checks pass
- [ ] No JSON syntax errors
- [ ] No duplicate keys
- [ ] All interpolation markers preserved
- [ ] Build completes successfully
- [ ] Unit tests pass

### Manual Testing Sign-Off

- [ ] Spot-checked 5+ translated strings in UI
- [ ] Tested language switching
- [ ] No console warnings related to i18n

### Documentation Sign-Off

- [ ] Migration documented in commit message
- [ ] Any known issues noted
- [ ] Rollback procedure tested (optional but recommended)

---

## Metrics to Capture

Record these metrics for the PR/commit:

| Metric | Value |
|--------|-------|
| Locales processed | |
| Total keys migrated | |
| Category files created | |
| Category files updated | |
| Excluded keys | 3 |
| Verification failures | |
| Time to complete | |

---

## Appendix: Expected Category Distribution

Reference for where keys should be distributed:

| Category File | Expected Key Types |
|---------------|-------------------|
| `account.json` | Account management, profile, API keys |
| `account-billing.json` | Plans, pricing, subscriptions |
| `auth.json` | Login, signup, password reset |
| `colonel.json` | Admin panel, stats |
| `dashboard.json` | Dashboard navigation, overview |
| `email.json` | Email-related strings |
| `feature-domains.json` | Custom domain configuration |
| `feature-incoming.json` | Incoming features, beta |
| `feature-organizations.json` | Team/org management |
| `feature-regions.json` | Data regions, jurisdiction |
| `feature-secrets.json` | Secret creation, viewing |
| `homepage.json` | Landing page content |
| `layout.json` | Navigation, footer, common UI |
| `_common.json` | Shared utility strings |
| `uncategorized.json` | Excluded keys only |
