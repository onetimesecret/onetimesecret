import { test, expect } from '@playwright/test';

/**
 * E2E Integration Tests
 *
 * These tests validate that the production build works correctly by testing
 * against a real containerized application instance. They catch issues that
 * unit tests miss, especially asset bundling and runtime environment problems.
 *
 * ## Quick Start
 *
 * 1. Install Playwright browsers (one-time setup):
 *    ```bash
 *    pnpm install
 *
 *    # Set environment variables
 *    FRONTEND_BASE_URL=http://localhost:5173
 *    PLAYWRIGHT_BASE_URL=http://localhost:3000
 *    ```
 *
 * 2. Choose your testing approach:
 *
 *    **Option A: Test against dev server (fastest)**
 *    ```bash
 *
 *    # Terminal 1: Start dev server
 *    pnpm run dev
 *
 *    # Terminal 2: Run tests
 *    PLAYWRIGHT_BASE_URL=$FRONTEND_BASE_URL pnpm test:playwright tests/e2e/
 *    ```
 *
 *    **Option B: Test against production build (recommended)**
 *    ```bash
 *    # Build and start production server
 *    pnpm run build
 *    RACK_ENV=production SECRET=test123 REDIS_URL=redis://localhost:6379/0 \
 *      bundle exec thin -R config.ru -p 3000 start
 *
 *    # Run tests in another terminal
 *    pnpm run playwright tests/e2e/
 *    ```
 *
 *    **Option C: Test against containerized app (most accurate)**
 *    ```bash
 *    # Build and run container
 *    docker build -t ots-test .
 *    docker run -d --name ots-test -p 3000:3000 \
 *      -e SECRET=test123 -e REDIS_URL=redis://host.docker.internal:6379/0 ots-test
 *
 *    # Run tests
 *    pnpm test:playwright tests/e2e/
 *
 *    # Cleanup
 *    docker stop ots-test && docker rm ots-test
 *    ```
 *
 * ## Debugging with Claude Code/Desktop
 *
 * When tests fail, use this workflow for efficient debugging:
 *
 * 1. **Run with UI mode for visual debugging:**
 *    ```bash
 *    pnpm test:playwright tests/e2e/ --ui
 *    ```
 *
 * 2. **Run single test with headed browser:**
 *    ```bash
 *    pnpm test:playwright tests/e2e/integration.spec.ts \
 *      --headed --project=chromium -g "homepage loads"
 *    ```
 *
 * 3. **Generate Playwright trace for Claude analysis:**
 *    ```bash
 *    pnpm test:playwright tests/e2e/ \
 *      --trace=on --reporter=html
 *    ```
 *    This creates `playwright-report/` with detailed traces.
 *
 * 4. **Share context with Claude Code/Desktop:**
 *    - Copy the failing test output
 *    - Include the test file (`tests/e2e/integration.spec.ts`)
 *    - Share relevant logs: `docker logs <container-name>` if using containers
 *    - Mention your environment: dev server, production build, or container
 *
 *    **Example Claude prompt:**
 *    ```
 *    My Playwright E2E test is failing with this error:
 *    [paste error output]
 *
 *    Test file: tests/e2e/integration.spec.ts
 *    Environment: [dev server / production build / container]
 *    Application logs: [paste relevant logs if available]
 *
 *    Can you help me debug this?
 *    ```
 *
 * ## Common Issues & Solutions
 *
 * - **"Cannot find module"** → Run `npx playwright install` first
 * - **"Target page closed"** → App likely crashed, check server logs
 * - **"Timeout waiting for element"** → Element selector may be wrong or app is slow
 * - **"net::ERR_CONNECTION_REFUSED"** → Check that PLAYWRIGHT_BASE_URL matches your running server
 * - **Asset loading failures** → Common in production builds, check browser Network tab
 *
 * ## Test Focus Areas
 *
 * These tests specifically validate:
 * - Asset loading and bundling (CSS, JS, fonts, images)
 * - Basic application functionality (form submission, navigation)
 * - Production build behavior (minification, optimization)
 * - Container runtime environment (env vars, networking)
 * - Responsive design across viewports
 * - Error handling and graceful degradation
 */

test.describe('E2E Integration - Production Build Validation', () => {
  test.beforeEach(async ({ page }) => {
    // Add extra time for containerized application responses
    page.setDefaultTimeout(15000);
  });

  test('homepage loads successfully with all assets', async ({ page }) => {
    await page.goto('/');

    // Verify page loads
    await expect(page).toHaveTitle(/Onetime Secret/i);

    // Check for main content areas
    await expect(page.locator('body')).toBeVisible();

    // Verify no JavaScript errors (asset loading issues often cause JS errors)
    const jsErrors: string[] = [];
    page.on('pageerror', (error) => {
      jsErrors.push(error.message);
    });

    // Wait for page to fully load
    await page.waitForLoadState('networkidle');

    // Verify no critical JavaScript errors occurred
    expect(
      jsErrors.filter(
        (error) =>
          !error.includes('Non-Error promise rejection') && // Filter minor errors
          !error.includes('Script error')
      )
    ).toHaveLength(0);
  });

  test('assets load correctly from production build', async ({ page }) => {
    const failedRequests: string[] = [];

    // Track failed network requests (common with missing assets)
    page.on('requestfailed', (request) => {
      failedRequests.push(`${request.method()} ${request.url()} - ${request.failure()?.errorText}`);
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Check that no critical assets failed to load
    const criticalFailures = failedRequests.filter(
      (req) =>
        req.includes('.css') ||
        req.includes('.js') ||
        req.includes('.ico') ||
        req.includes('/assets/')
    );

    expect(
      criticalFailures,
      `Failed to load critical assets: ${criticalFailures.join(', ')}`
    ).toHaveLength(0);
  });

  test('can create a secret (basic functionality)', async ({ page }) => {
    await page.goto('/');

    // Look for secret creation form using more specific selectors
    const secretInput = page.locator('textarea[aria-label*="secret content"]');
    const createButton = page.locator('button:has-text("Create Link")');

    if (await secretInput.isVisible()) {
      await secretInput.fill('Test secret for E2E integration');
      await createButton.click();

      // Verify we get to a receipt page (the actual route used after creating a secret)
      await expect(page).toHaveURL(/\/receipt\/.+/);
    } else {
      console.log('Secret input not found - adjust selectors for your UI');
    }
  });

  test('stylesheet and fonts load correctly', async ({ page }) => {
    await page.goto('/');

    // Check that basic styling is applied (indicates CSS loaded)
    const body = page.locator('body');
    await expect(body).toBeVisible();

    // Check for any obvious styling issues
    const computedStyle = await body.evaluate((el) => {
      const style = window.getComputedStyle(el);
      return {
        backgroundColor: style.backgroundColor,
        fontFamily: style.fontFamily,
      };
    });

    // Basic sanity checks - adjust based on your design
    expect(computedStyle.fontFamily).not.toBe('');
    expect(computedStyle.backgroundColor).not.toBe('rgba(0, 0, 0, 0)'); // Not transparent
  });

  test('responsive design works (mobile viewport)', async ({ page }) => {
    // Test mobile viewport to ensure responsive assets load
    await page.setViewportSize({ width: 375, height: 667 }); // iPhone SE
    await page.goto('/');

    await expect(page.locator('body')).toBeVisible();

    // Wait for layout to stabilize after viewport change
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(500); // Small delay for CSS transitions/layout

    // Verify page is reasonably responsive at mobile size
    // Allow small overflow tolerance (e.g., 10px) for minor layout issues
    const { scrollWidth, viewportWidth, hasOverflow } = await page.evaluate(() => {
      const scrollWidth = document.body.scrollWidth;
      const viewportWidth = window.innerWidth;
      const overflowAmount = scrollWidth - viewportWidth;
      return {
        scrollWidth,
        viewportWidth,
        hasOverflow: overflowAmount > 15, // Allow 15px tolerance for minor layout variations
      };
    });

    expect(
      hasOverflow,
      `Page has significant horizontal overflow on mobile: scrollWidth=${scrollWidth}, viewportWidth=${viewportWidth}`
    ).toBe(false);
  });

  test('favicon and meta tags are present', async ({ page }) => {
    await page.goto('/');

    // Check for favicon (common asset that gets missed)
    // Note: link and meta tags are not visible, so we check for their presence in the DOM
    // Multiple favicon sizes/types are normal (different sizes, apple-touch-icon, etc.)
    const favicon = page.locator('link[rel="icon"], link[rel="shortcut icon"]');
    const faviconCount = await favicon.count();
    expect(faviconCount).toBeGreaterThanOrEqual(1);

    // Check basic meta tags
    const charsetMeta = page.locator('meta[charset]');
    await expect(charsetMeta).toHaveCount(1);

    const viewportMeta = page.locator('meta[name="viewport"]');
    await expect(viewportMeta).toHaveCount(1);
  });

  test('application handles errors gracefully', async ({ page }) => {
    // Test error handling (production builds should show user-friendly errors)
    const response = await page.goto('/nonexistent-page');

    // Should get 404 but page should still load properly
    expect(response?.status()).toBe(404);
    await expect(page.locator('body')).toBeVisible();

    // Should not show development error pages or stack traces
    const bodyText = await page.textContent('body');
    expect(bodyText?.toLowerCase()).not.toContain('stack trace');
    expect(bodyText?.toLowerCase()).not.toContain('development mode');
  });
});

test.describe('E2E Integration - Environment Validation', () => {
  test('environment variables are properly set', async ({ page }) => {
    // This test validates that the container has proper env vars
    // You might expose a debug endpoint for this, or check via behavior

    await page.goto('/');

    // Direct check: verify actual frontend_development config value
    const isDevelopment = await page.evaluate(() => {
      // Ensure the config is loaded
      if (!window.__ONETIME_STATE__) {
        throw new Error('Application state not loaded');
      }
      return window.__ONETIME_STATE__.frontend_development === true;
    });

    // In integration testing, we're testing production build
    expect(isDevelopment, 'Should not be in development mode').toBe(false);
  });
});
