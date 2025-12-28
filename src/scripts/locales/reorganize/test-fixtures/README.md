# Test Fixtures

Sample data for testing the locale reorganization process.

## Files

### `sample-uncategorized.json`

A subset of 20 keys from the full `uncategorized.json` for testing:

- 17 keys to be distributed across category files
- 3 excluded keys that remain in `uncategorized.json`
- Includes keys with interpolation markers (`{0}`)
- Covers multiple target categories

### `expected-output/`

Expected results after reorganization of the sample data:

| File | Keys | Description |
|------|------|-------------|
| `account.json` | 2 | Account management keys |
| `account-billing.json` | 2 | Billing/subscription keys |
| `auth.json` | 4 | Authentication keys |
| `feature-domains.json` | 4 | Domain configuration keys |
| `layout.json` | 4 | Common UI/navigation keys |
| `_common.json` | 3 | Status/state keys |
| `uncategorized.json` | 3 | Excluded keys only |

**Total**: 22 keys (17 distributed + 3 excluded + 2 keys may appear in existing files)

## Usage

```bash
# Run reorganization on test fixtures
./path/to/reorganize.py --input test-fixtures/sample-uncategorized.json

# Compare output against expected
diff -r output/ test-fixtures/expected-output/
```

## Key Distribution Logic

The sample demonstrates these categorization rules:

1. **Domain-related keys** -> `feature-domains.json`
   - Keys containing "domain" in name

2. **Auth-related keys** -> `auth.json`
   - Sign-in, email, password, account creation

3. **Account management** -> `account.json`
   - API key, account deletion

4. **Billing** -> `account-billing.json`
   - Payment frequency (monthly/yearly)

5. **Common UI** -> `_common.json`
   - Generic status labels

6. **Layout/Navigation** -> `layout.json`
   - Feedback, navigation, previews

7. **Excluded keys** -> remain in `uncategorized.json`
   - Emoji characters
   - CSS media queries

## Validation

All expected output files use the standard structure:

```json
{
  "web": {
    "category": {
      "key": "value"
    }
  }
}
```

Exception: `uncategorized.json` uses flat structure for excluded keys.
