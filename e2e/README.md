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
- **Components with a `testid` prop** (`EmptyState`, `CopyButton`, `CopyToClipboardButton`):
  use the prop, not the HTML attribute. `data-testid="foo"` on these components gets
  swallowed by Vue's attribute priority—the explicit `:data-testid="testid"` binding in
  the template wins, and since the prop is undefined, nothing renders.
  ```vue
  <!-- WRONG: silently lost -->
  <EmptyState data-testid="my-empty">

  <!-- RIGHT: renders on the DOM -->
  <EmptyState testid="my-empty">
  ```

**Skip testids on:**
- Purely decorative elements (icons, dividers, background shapes)
- Wrapper divs that exist only for layout — target the interactive child instead
- Elements already reachable via `getByRole()` or `getByText()` with stable values

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PLAYWRIGHT_BASE_URL` | Target URL (e.g., `http://localhost:3000`) |
| `TEST_USER_EMAIL` | Auth user for `full/` tests |
| `TEST_USER_PASSWORD` | Auth password for `full/` tests |
| `PLAYWRIGHT_HEADLESS` | Set `false` for headed debugging |
| `E2E_DIAGNOSTICS_ENABLED` | Set `true` to let the auto-started server report to Sentry (default: off) |

### Diagnostics are off in test servers

An e2e run provokes errors on purpose, and a locally booted server inherits
your shell. If that shell exports `DIAGNOSTICS_ENABLED=true` and a real
`SENTRY_DSN` for your dev server, those errors used to land in the production
Sentry project. Three guards now prevent it, and none changes a production
boot:

- **The server Playwright starts itself** (no `PLAYWRIGHT_BASE_URL`) is given
  `DIAGNOSTICS_ENABLED=false`, whatever the shell says. Set
  `E2E_DIAGNOSTICS_ENABLED=true` to opt back in, for example to test the Sentry
  wiring against a scratch project.
- **A server Playwright reuses** (outside CI, anything already answering on
  `localhost:7143` is reused instead of spawned, so the setting above never
  reaches it) is checked before any test runs: global setup reads its
  bootstrap `d9s_enabled` and aborts the run if diagnostics are on
  (`support/diagnostics-guard.ts`). The same `E2E_DIAGNOSTICS_ENABLED=true`
  skips the check.
- **Any server booted with `RACK_ENV=test`** ignores `DIAGNOSTICS_ENABLED`
  unless `DIAGNOSTICS_ENABLED_IN_TEST=true` is also set
  (`Onetime::Config.diagnostics_enabled?`). This covers backend and frontend:
  the frontend SDK follows the same flag.

A server you start yourself with `RACK_ENV=production` and point the suite at
with `PLAYWRIGHT_BASE_URL` (the recipe in `.github/workflows/e2e-full-auth.yml`
does, because full auth mode needs it) is indistinguishable from a real
deployment, so no guard applies to it.
Start it with `DIAGNOSTICS_ENABLED=false`, or unset `SENTRY_DSN*` first. The
boot banner prints `Diagnostics: true/false`; check it before running the
suite.

Parallel sign-ups no longer need `--workers=1` against a SQLite authdb
(`Auth::Database.connect`).

## CI

Tests run in GitHub Actions. On failure, check:
- `test-results/` for screenshots and traces
- `playwright-report/` for HTML report
