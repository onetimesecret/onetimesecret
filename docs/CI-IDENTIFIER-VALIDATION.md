# CI Identifier Validation

This document describes how to integrate the `ots/no-internal-id-in-url` ESLint rule into CI pipelines and local development workflows.

## Overview

The Opaque Identifier Pattern requires using external IDs (`extid`) instead of internal IDs (`id`, `objid`) in URL contexts. The ESLint rule enforces this at lint time.

Related documentation:
- `src/types/identifiers.ts` - Branded type definitions
- `eslint-rules/no-internal-id-in-url.ts` - ESLint rule implementation
- `docs/IDENTIFIER-REVIEW-CHECKLIST.md` - Manual review guidance

## ESLint Rule Integration

### Rule Configuration

The rule is configured in `eslint.config.ts`:

```typescript
// eslint.config.ts
import noInternalIdInUrl from './eslint-rules/no-internal-id-in-url.js';

export default [
  // ... other config
  {
    plugins: {
      ots: {
        rules: {
          'no-internal-id-in-url': noInternalIdInUrl,
        },
      },
    },
    rules: {
      // Phase 1: Warning mode during migration
      'ots/no-internal-id-in-url': 'warn',
      // Phase 3: Enable as error for full enforcement
      // 'ots/no-internal-id-in-url': 'error',
    },
  },
];
```

### Running Locally

```bash
# Run linting with identifier validation
pnpm lint

# Auto-fix suggestions (where available)
pnpm lint:fix

# Check specific files
pnpm eslint src/apps/**/*.vue src/apps/**/*.ts
```

## GitHub Actions Integration

The existing CI workflow already includes ESLint in the `typescript-lint` job. The identifier rule runs as part of standard linting.

### Workflow Snippet (`.github/workflows/ci.yml`)

```yaml
typescript-lint:
  name: T1 - TypeScript Lint
  timeout-minutes: 5
  runs-on: ubuntu-24.04
  needs: [changes]
  if: needs.changes.outputs.typescript == 'true'
  steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Node.js environment
      uses: ./.github/actions/setup-node-env

    - name: Run type checking
      run: pnpm type-check

    - name: Run linting
      run: pnpm lint
      # Includes ots/no-internal-id-in-url rule
```

### Adding a Dedicated Identifier Validation Job (Optional)

For explicit visibility of IDOR violations, add a dedicated job:

```yaml
identifier-validation:
  name: T1 - Identifier Pattern Validation
  timeout-minutes: 3
  runs-on: ubuntu-24.04
  needs: [changes]
  if: needs.changes.outputs.typescript == 'true'
  steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Node.js environment
      uses: ./.github/actions/setup-node-env

    - name: Validate identifier usage in URLs
      run: |
        echo "## Identifier Pattern Validation" >> $GITHUB_STEP_SUMMARY
        # Run ESLint with only the identifier rule
        pnpm eslint \
          --rule 'ots/no-internal-id-in-url: error' \
          --no-eslintrc \
          'src/**/*.vue' 'src/**/*.ts' \
          --format stylish \
          2>&1 | tee eslint-output.txt

        # Report findings in summary
        if grep -q "no-internal-id-in-url" eslint-output.txt; then
          echo "### Potential IDOR Violations Found" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          grep "no-internal-id-in-url" eslint-output.txt >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          exit 1
        else
          echo "No identifier violations found." >> $GITHUB_STEP_SUMMARY
        fi
```

## Pre-commit Hook Configuration

### Using Husky

```bash
# Install husky if not already installed
pnpm add -D husky
pnpm exec husky init
```

Create `.husky/pre-commit`:

```bash
#!/bin/sh
. "$(dirname "$0")/_/husky.sh"

# Run identifier validation on staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(vue|ts|tsx)$')

if [ -n "$STAGED_FILES" ]; then
  echo "Validating identifier patterns in staged files..."
  echo "$STAGED_FILES" | xargs pnpm eslint --rule 'ots/no-internal-id-in-url: warn'
fi
```

### Using lint-staged

Add to `package.json`:

```json
{
  "lint-staged": {
    "*.{vue,ts,tsx}": [
      "eslint --rule 'ots/no-internal-id-in-url: warn'"
    ]
  }
}
```

## Migration Phases

### Phase 1 (Current)
- Rule severity: `warn`
- CI: Warnings logged but don't fail build
- Purpose: Identify existing violations without breaking CI

### Phase 2
- Update function signatures to require branded types
- Add `toExtId()`/`toObjId()` at data boundaries
- Fix identified violations

### Phase 3
- Rule severity: `error`
- CI: Violations fail the build
- Full enforcement of opaque identifier pattern

## Rule Detection Patterns

The rule flags `.id` usage in these contexts:

| Context | Example | Detection |
|---------|---------|-----------|
| Template literals with paths | `` `/org/${org.id}` `` | Yes |
| router.push calls | `router.push(\`/org/${org.id}\`)` | Yes |
| Object properties (to, href, path) | `{ to: \`/org/${org.id}\` }` | Yes |
| String concatenation | `'/org/' + org.id` | Yes |

### False Positives

Some `.id` usage is intentional and correct:

```vue
<!-- CORRECT: id for Vue :key binding -->
<div v-for="org in orgs" :key="org.id">

<!-- CORRECT: id for store lookups -->
const found = orgs.find(o => o.id === selectedId);
```

If the rule flags these, use an eslint-disable comment with explanation:

```typescript
// eslint-disable-next-line ots/no-internal-id-in-url -- id used for store lookup, not URL
const org = store.getOrganizationById(org.id);
```

## Troubleshooting

### Rule Not Running

1. Verify the rule is registered in `eslint.config.ts`
2. Check that `eslint-rules/no-internal-id-in-url.ts` is compiled to `.js`
3. Run `pnpm lint --debug` to see rule loading

### Too Many Warnings

During migration, use `--max-warnings` to limit CI noise:

```bash
pnpm eslint --max-warnings 50 'src/**/*.vue' 'src/**/*.ts'
```

### Type Errors in ESLint Rule

If the rule itself has type errors, ensure TypeScript is configured to compile ESLint rules:

```json
// tsconfig.json
{
  "include": ["eslint-rules/**/*.ts"]
}
```
