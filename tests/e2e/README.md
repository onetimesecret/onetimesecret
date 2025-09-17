# E2E Testing Guide - 2025-09-17

This directory contains end-to-end integration tests that validate the complete application stack from build to deployment.

## Directory Structure

```
tests/e2e/
├── README.md              # This file
├── playwright.config.ts   # Playwright configuration
├── integration.spec.ts    # Main integration tests
└── fixtures/              # Test data and helpers (create as needed)
```

## Quick Setup

```bash
# One-time setup
pnpx playwright install

# Run all E2E tests against dev server

# In both terminals, one of the following depending on whether you are running a reverse proxy:
FRONTEND_HOST=http://localhost:5173
PLAYWRIGHT_BASE_URL=https://dev.onetime.dev

pnpm run dev  # In terminal 1

PLAYWRIGHT_BASE_URL=$HOST pnpx playwright test tests/e2e/  # In terminal 2
```

## Test Environments

### 1. Development Server (Fastest)
```bash
# Start dev server
pnpm run dev

# Run tests
PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpx playwright test tests/e2e/
```
**Use for:** Rapid iteration, UI development, selector debugging

### 2. Production Build (Recommended)
```bash
# Build production assets
pnpm run build

# Start production server
RACK_ENV=production SECRET=test123 REDIS_URL=redis://localhost:6379/0 \
  bundle exec thin -R config.ru -p 3000 start

# Run tests
PLAYWRIGHT_BASE_URL=http://localhost:3000 pnpx playwright test tests/e2e/
```
**Use for:** Asset bundling validation, performance testing, pre-deployment verification

### 3. Containerized (Most Accurate)
```bash
# Build and run container
docker build -t onetimesecret-test .
docker run -d --name ots-test -p 3000:3000 \
  -e SECRET=test123 \
  -e REDIS_URL=redis://host.docker.internal:6379/0 \
  onetimesecret-test

# Run tests
PLAYWRIGHT_BASE_URL=http://localhost:3000 pnpx playwright test tests/e2e/

# Cleanup
docker stop ots-test && docker rm ots-test
```
**Use for:** Final validation, CI/CD pipeline testing, deployment environment simulation

## Debugging Workflows

### Visual Debugging
```bash
# Interactive UI mode
npx playwright test tests/e2e/ --ui

# Watch mode (headed browser)
npx playwright test tests/e2e/ --headed --project=chromium
```

### Trace Generation
```bash
# Generate detailed traces
npx playwright test tests/e2e/ --trace=on --reporter=html

# View traces
npx playwright show-trace test-results/*/trace.zip
```

### Targeted Testing
```bash
# Run specific test
npx playwright test tests/e2e/integration.spec.ts -g "homepage loads"

# Run against specific browser
npx playwright test tests/e2e/ --project=firefox

# Debug specific test
npx playwright test tests/e2e/integration.spec.ts --debug
```

## Working with Claude Code/Desktop

### When Tests Fail

1. **Gather Context:**
   - Copy the complete error output
   - Note which environment you're testing against
   - Include relevant application logs
   - Capture any browser console errors

2. **Share with Claude:**
   ```
   My E2E test is failing. Here's the context:

   **Environment:** [dev server / production build / container]
   **Test Command:** PLAYWRIGHT_BASE_URL=... pnpx playwright test ...
   **Error Output:**
   [paste complete error]

   **Application Logs:** (if relevant)
   [paste server/container logs]

   **Test File:** tests/e2e/integration.spec.ts
   [share the specific failing test]

   Can you help debug this issue?
   ```

3. **Claude Code Workflow:**
   - Open the test file in Claude Code
   - Run `@workspace /explain` to get context about the test setup
   - Use `/fix` command with the error details
   - Apply suggested changes iteratively

### Common Debugging Patterns

#### Asset Loading Issues
```bash
# Check network requests
npx playwright test tests/e2e/ --headed
# Open browser DevTools → Network tab

# Test specific asset loading
curl -I http://localhost:3000/assets/application.css
```

#### Element Selector Issues
```bash
# Generate selectors interactively
npx playwright codegen http://localhost:3000

# Test selectors in browser console
document.querySelector('your-selector')
```

#### Timing Issues
```bash
# Add debugging to test
await page.pause(); // Pauses execution for manual inspection
```

## Best Practices

### Test Organization
- Keep tests focused on integration scenarios
- Separate unit tests from E2E tests
- Use descriptive test names that explain the scenario
- Group related tests in `describe` blocks

### Selector Strategy
- Prefer `data-testid` attributes for test-specific selectors
- Use semantic selectors (`role`, `text`) when possible
- Avoid brittle CSS selectors that change with styling

### Performance
- Run tests in parallel when possible
- Use `page.waitForLoadState('networkidle')` for dynamic content
- Set appropriate timeouts for different environments

### CI/CD Integration
- Tests run automatically in GitHub Actions
- Check `test-results/` and `playwright-report/` artifacts on failure
- Use environment-specific configurations for different deployment stages

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `PLAYWRIGHT_BASE_URL` | Target application URL | `http://localhost:3000` |
| `PLAYWRIGHT_HEADLESS` | Run in headless mode | `false` (for debugging) |
| `PLAYWRIGHT_BROWSER` | Specific browser to use | `chromium` |
| `CI` | CI environment flag | Auto-set in GitHub Actions |

## Troubleshooting

### Common Issues

**"Cannot find module '@playwright/test'"**
```bash
npm install @playwright/test
npx playwright install
```

**"Target page closed / Target crashed"**
- Application likely crashed
- Check server logs: `docker logs container-name`
- Verify correct environment variables

**"Timeout: waiting for element"**
- Element selector may be incorrect
- Application may be loading slowly
- Use `page.waitForSelector()` with longer timeout

**"net::ERR_CONNECTION_REFUSED"**
- Server not running on expected port
- Check `PLAYWRIGHT_BASE_URL` matches your server
- Verify firewall/network settings

### Getting Help

1. Check the Playwright documentation: https://playwright.dev
2. Review test artifacts in `test-results/` directory
3. Share context with Claude Code/Desktop using the patterns above
4. Check GitHub Actions logs for CI-specific issues

## Adding New Tests

1. Create test files with `.spec.ts` extension
2. Follow the existing patterns in `integration.spec.ts`
3. Focus on user workflows and critical paths
4. Test error conditions and edge cases
5. Validate both happy path and error scenarios

Example test structure:
```typescript
import { test, expect } from '@playwright/test';

test.describe('Feature Name', () => {
  test.beforeEach(async ({ page }) => {
    // Setup for each test
  });

  test('should do something specific', async ({ page }) => {
    // Test implementation
  });
});
```
