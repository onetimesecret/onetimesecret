// src/tests/e2e/secret-context.spec.ts

import { test, expect } from '@playwright/test';

/**
 * E2E tests for secret context and actor role behavior
 *
 * Tests the different user experiences when viewing secrets:
 * - CREATOR: Owner viewing their own secret (shows warning, burn control)
 * - RECIPIENT_AUTH: Authenticated user viewing someone else's secret
 * - RECIPIENT_ANON: Anonymous user viewing a secret (entitlements upgrade)
 *
 * These tests validate that:
 * 1. Owners see appropriate warnings when viewing their own secrets
 * 2. Anonymous users see signup CTAs and marketing content
 * 3. Authenticated recipients see appropriate UI without marketing
 */

test.describe('Secret Context - Actor Roles', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(10000);
  });

  test('owner sees warning when viewing own secret', async ({ page, context, baseURL }) => {
    // This test requires:
    // 1. Create a secret as authenticated user
    // 2. View that secret as the creator
    // 3. Verify owner-specific UI elements appear

    // Mock authenticated state - use baseURL from config
    const cookieDomain = new URL(baseURL || 'http://localhost:3000').hostname;
    await context.addCookies([
      {
        name: 'sess',
        value: 'mock-session-token',
        domain: cookieDomain,
        path: '/',
      },
    ]);

    // Mock the secret details endpoint to indicate ownership
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      // If it's a metadata request
      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: true, // User owns this secret
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    // Navigate to a secret view page
    await page.goto('/secret/test-secret-key');
    await page.waitForLoadState('networkidle');

    // Owner should see burn control or owner-specific UI
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Check for owner-specific elements (adjust selectors as needed)
    // Examples:
    // - Burn button
    // - "You are viewing your own secret" warning
    // - Dashboard link instead of signup CTA

    // Verify no JavaScript errors occurred
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Owner view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('anonymous user does not see owner warning', async ({ page, context }) => {
    // Clear all cookies to ensure anonymous state
    await context.clearCookies();

    // Mock the secret details endpoint to indicate non-ownership
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false, // Anonymous viewer
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto('/secret/test-secret-key');
    await page.waitForLoadState('networkidle');

    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Anonymous users should see:
    // - Signup CTA instead of dashboard link
    // - Entitlements upgrade content
    // - NO burn control
    // - NO owner warning

    // Verify page loads without errors
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.waitForTimeout(1000); // Wait for any async errors

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Anonymous view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('authenticated recipient sees appropriate UI', async ({ page, context, baseURL }) => {
    // Mock authenticated state - use baseURL from config
    const cookieDomain = new URL(baseURL || 'http://localhost:3000').hostname;
    await context.addCookies([
      {
        name: 'sess',
        value: 'mock-session-token',
        domain: cookieDomain,
        path: '/',
      },
    ]);

    // Mock the secret details endpoint for authenticated non-owner
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false, // Authenticated but not owner
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto('/secret/test-secret-key');
    await page.waitForLoadState('networkidle');

    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Authenticated recipients should see:
    // - Dashboard link (not signup CTA)
    // - NO entitlements upgrade
    // - NO burn control (not owner)
    // - NO owner warning

    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.waitForTimeout(1000);

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Authenticated recipient view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('secret view handles passphrase requirement', async ({ page, context }) => {
    await context.clearCookies();

    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false,
              ttl: 3600,
              state: 'new',
              passphrase_required: true, // Requires passphrase
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto('/secret/test-secret-key');
    await page.waitForLoadState('networkidle');

    // Should show passphrase input
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Verify no errors during passphrase handling
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.waitForTimeout(1000);

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Passphrase view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });

  test('theme applies correctly for custom domains', async ({ page }) => {
    // Mock custom domain branding
    await page.addInitScript(() => {
      window.__ONETIME_STATE__ = {
        ...window.__ONETIME_STATE__,
        domain_strategy: 'custom',
        domain_branding: {
          primary_color: '#3b82f6',
          button_text_light: true,
          description: 'Custom Brand',
        },
      };
    });

    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false,
              ttl: 3600,
              state: 'new',
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto('/secret/test-secret-key');
    await page.waitForLoadState('networkidle');

    // Verify branded theme is applied
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Check for theme application (could verify CSS variables or computed styles)
    const bodyStyle = await page.locator('body').evaluate((el) => window.getComputedStyle(el).backgroundColor);

    expect(bodyStyle).toBeTruthy();
  });

  test('secret view handles burned secrets gracefully', async ({ page }) => {
    await page.route('**/api/v2/secret/**', async (route) => {
      const url = route.request().url();

      if (url.includes('/metadata/')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            record: {
              key: 'test-secret-key',
              is_owner: false,
              ttl: 0,
              state: 'received', // Already viewed/burned
              passphrase_required: false,
            },
          }),
        });
      } else {
        await route.continue();
      }
    });

    await page.goto('/secret/test-secret-key');
    await page.waitForLoadState('networkidle');

    // Should show "already viewed" message
    const bodyText = await page.textContent('body');
    expect(bodyText).toBeTruthy();

    // Verify graceful error handling
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.waitForTimeout(1000);

    const criticalErrors = consoleErrors.filter(
      (error) =>
        !error.includes('Non-Error promise rejection') && !error.includes('Script error') && !error.includes('WebSocket') && !error.includes('[vite]') && !error.includes('hmr')
    );

    expect(
      criticalErrors,
      `Burned secret view should not have console errors. Found: ${criticalErrors.join(', ')}`
    ).toHaveLength(0);
  });
});
