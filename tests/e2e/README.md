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
pnpm install

# Run all E2E tests against dev server

# In both terminals, one of the following depending on whether you are running a reverse proxy:
FRONTEND_HOST=http://localhost:5173
PLAYWRIGHT_BASE_URL=https://dev.onetime.dev

pnpm run dev  # In terminal 1

PLAYWRIGHT_BASE_URL=$HOST pnpm test:playwright tests/e2e/  # In terminal 2
```

## Test Environments

### 1. Development Server (Fastest)
```bash
# Start dev server
pnpm run dev

# Run tests
PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright tests/e2e/
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
PLAYWRIGHT_BASE_URL=http://localhost:3000 pnpm test:playwright tests/e2e/
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
PLAYWRIGHT_BASE_URL=http://localhost:3000 pnpm test:playwright tests/e2e/

# Cleanup
docker stop ots-test && docker rm ots-test
```
**Use for:** Final validation, CI/CD pipeline testing, deployment environment simulation

## Debugging Workflows

### Visual Debugging
```bash
# Interactive UI mode
pnpm test:playwright tests/e2e/ --ui

# Watch mode (headed browser)
pnpm test:playwright tests/e2e/ --headed --project=chromium
```

### Trace Generation
```bash
# Generate detailed traces
pnpm test:playwright tests/e2e/ --trace=on --reporter=html

# View traces
pnpm playwright show-trace test-results/*/trace.zip
```

### Targeted Testing
```bash
# Run specific test
pnpm test:playwright tests/e2e/integration.spec.ts -g "homepage loads"

# Run against specific browser
pnpm test:playwright tests/e2e/ --project=firefox

# Debug specific test
pnpm test:playwright tests/e2e/integration.spec.ts --debug
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
   **Test Command:** PLAYWRIGHT_BASE_URL=... pnpm playwright ...
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
pnpm test:playwright tests/e2e/ --headed
# Open browser DevTools → Network tab

# Test specific asset loading
curl -I http://localhost:3000/assets/application.css
```

#### Element Selector Issues
```bash
# Generate selectors interactively
pnpm playwright codegen http://localhost:3000

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
| `FRONTEND_BASE_URL` | Target vue frontend URL | `http://localhost:5173` |
| `CI` | CI environment flag | Auto-set in GitHub Actions |
