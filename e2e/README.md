# E2E Testing

Playwright-based end-to-end tests. See `playwright.config.ts` for configuration.

## Directory Structure

| Directory | Requires | Description |
|-----------|----------|-------------|
| `all/` | Nothing | Public pages, anonymous flows |
| `full/` | Auth session | Requires `TEST_USER_EMAIL` and `TEST_USER_PASSWORD` |
| `full-billing/` | Auth + billing | Requires billing.yaml config |

## Running Tests

```bash
# Dev server (terminal 1)
pnpm run dev

# Run tests (terminal 2)
PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright e2e/

# Or against production build
PLAYWRIGHT_BASE_URL=https://dev.onetime.dev pnpm test:playwright e2e/

# Specific test file
pnpm test:playwright e2e/full/scope-switcher.spec.ts

# With headed browser for debugging
pnpm test:playwright e2e/ --headed --project=chromium

# Interactive UI mode
pnpm test:playwright e2e/ --ui
```

## Debugging

```bash
# Generate traces on failure
pnpm test:playwright e2e/ --trace=on --reporter=html
pnpm playwright show-trace test-results/*/trace.zip

# Pause test for inspection
await page.pause();  # Add to test code

# Generate selectors interactively
pnpm playwright codegen http://localhost:3000
```

## Locator Strategy

Prefer user-facing locators first, fall back to `data-testid` when no stable text or role is available:

1. **`getByRole()`** - Accessible, semantic (buttons, links, headings)
2. **`getByText()`** - User-visible, but may break with i18n
3. **`getByTestId()`** - Stable, immune to styling changes
4. **CSS selectors** - Last resort, fragile

### Test ID Convention

Use `data-testid` attributes on elements tests interact with:

```vue
<button data-testid="save-button">Save</button>
<div :data-testid="`org-card-${org.extid}`">...</div>
```

```typescript
// In tests
page.getByTestId('save-button')
page.locator('[data-testid^="org-card-"]')  // Prefix match
```

**Conventions:**
- Place on the semantic element the test cares about, not wrapper divs
- Keep values short and hierarchical: `checkout/form/submit`
- Never reuse the same value for elements that can coexist
- Never use `data-testid` for styling or behavior—only tests

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PLAYWRIGHT_BASE_URL` | Target URL (e.g., `http://localhost:3000`) |
| `TEST_USER_EMAIL` | Auth user for `full/` tests |
| `TEST_USER_PASSWORD` | Auth password for `full/` tests |
| `PLAYWRIGHT_HEADLESS` | Set `false` for headed debugging |

## CI

Tests run in GitHub Actions. On failure, check:
- `test-results/` for screenshots and traces
- `playwright-report/` for HTML report
