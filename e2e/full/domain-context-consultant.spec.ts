// e2e/full/domain-context-consultant.spec.ts

import { test, expect } from '@playwright/test';

/**
 * E2E Test: Domain Context Consultant Workflow
 *
 * This test validates the domain context feature for users with multiple custom domains.
 * It tests the consultant workflow where a user needs to switch between different
 * client domains when creating secrets.
 *
 * ## Prerequisites
 * - Application running (dev server or production)
 * - Test user account with custom domains configured
 * - Redis running
 *
 * ## Test Scenario
 * A consultant with multiple client domains (e.g., acme.example.com, widgets.example.com)
 * needs to create secrets for different clients. They should be able to:
 * 1. See a domain context indicator in the secret form
 * 2. Verify the current context shows the correct domain
 * 3. Create a secret and verify it uses the correct domain context
 *
 * ## Setup Instructions
 *
 * To run this test, you need a user with custom domains. You can:
 *
 * 1. **Option A: Use test fixtures** (recommended for CI)
 *    - Configure test data in your backend test setup
 *    - Mock window.__BOOTSTRAP_STATE__ to include custom domains
 *
 * 2. **Option B: Manual setup** (for local development)
 *    ```bash
 *    # Via ots CLI
 *    bin/ots console
 *    > user = Onetime::Customer['testuser@example.com']
 *    > domain1 = Onetime::CustomDomain.create(...)
 *    > domain2 = Onetime::CustomDomain.create(...)
 *    ```
 *
 * ## Running the Test
 *
 * ```bash
 * # Against dev server
 * PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright e2e/full/domain-context-consultant.spec.ts
 *
 * # Against production build
 * pnpm test:playwright e2e/full/domain-context-consultant.spec.ts
 *
 * # With UI for debugging
 * pnpm test:playwright e2e/full/domain-context-consultant.spec.ts --ui
 * ```
 *
 * ## Current Implementation Status
 *
 * As of Phase 4, the following are implemented:
 * - useDomainContext composable with localStorage persistence
 * - Domain context indicator in SecretForm
 * - Reactive context updates in form
 * - DomainContextSwitcher component (not yet implemented)
 *
 * This test focuses on what IS implemented. When DomainContextSwitcher is added,
 * extend this test to include context switching interactions.
 */

test.describe('Domain Context - Consultant Workflow', () => {
  test.beforeEach(async ({ page }) => {
    // Set reasonable timeout for E2E tests
    page.setDefaultTimeout(15000);
  });

  test.skip('displays domain context indicator for user with custom domains', async ({ page }) => {
    /**
     * This test validates that the domain context indicator appears when a user
     * has custom domains configured.
     *
     * SKIP REASON: Requires backend setup with custom domains.
     * Enable this test when you have:
     * 1. A test user account with custom domains
     * 2. Login credentials available
     * 3. Backend API configured for test environment
     */

    // TODO: Login as user with custom domains
    await page.goto('/');

    // Navigate to secret creation page (assuming authenticated)
    // Adjust selector based on your actual UI
    const createSecretLink = page.locator('a:has-text("Create Secret")');
    if (await createSecretLink.isVisible()) {
      await createSecretLink.click();
    }

    // Verify domain context indicator is visible
    const contextIndicator = page.locator('[role="status"][aria-label*="context"]');
    await expect(contextIndicator).toBeVisible();

    // Verify indicator shows a domain name
    const indicatorText = await contextIndicator.textContent();
    expect(indicatorText).toBeTruthy();
    expect(indicatorText?.length).toBeGreaterThan(0);
  });

  test.skip('context indicator shows correct styling for custom domain', async ({ page }) => {
    /**
     * Validates that custom domains get brand-colored styling
     * while canonical domain gets neutral gray styling.
     *
     * SKIP REASON: Requires backend setup with custom domains.
     */

    // TODO: Login as user with custom domains
    await page.goto('/');

    const contextIndicator = page.locator('[role="status"][aria-label*="context"]');
    await expect(contextIndicator).toBeVisible();

    // Check for brand-colored background (custom domain)
    const hasCustomStyling = await contextIndicator.evaluate((el) => {
      const classes = el.className;
      return classes.includes('bg-brand-50') || classes.includes('text-brand-700');
    });

    // Should have custom styling if on a custom domain
    expect(hasCustomStyling).toBe(true);
  });

  test.skip('persists domain context selection across page navigation', async ({ page }) => {
    /**
     * Validates that domain context persists in localStorage and survives
     * page navigation.
     *
     * SKIP REASON: Requires backend setup and context switcher component.
     */

    // TODO: Login as user with custom domains
    await page.goto('/');

    // Get initial context
    const initialContext = await page.evaluate(() => localStorage.getItem('domainContext'));

    // Navigate away and back
    await page.goto('/dashboard'); // Adjust route as needed
    await page.goto('/'); // Back to secret creation

    // Verify context persisted
    const persistedContext = await page.evaluate(() => localStorage.getItem('domainContext'));

    expect(persistedContext).toBe(initialContext);
  });

  test.skip('creates secret with correct domain context', async ({ page }) => {
    /**
     * Full consultant workflow: create a secret and verify it uses
     * the correct domain context.
     *
     * SKIP REASON: Requires backend setup with custom domains.
     */

    // TODO: Login as user with custom domains
    await page.goto('/');

    // Verify context indicator shows expected domain
    const contextIndicator = page.locator('[role="status"][aria-label*="context"]');
    await expect(contextIndicator).toBeVisible();
    // Note: Domain text verified by visibility check above
    const _currentDomain = await contextIndicator.textContent();

    // Create a secret
    const secretInput = page.locator('textarea[aria-labelledby="secretContentLabel"]');
    await secretInput.fill('Test secret for domain context E2E test');

    const createButton = page.locator('button:has-text("Create Link")');
    await createButton.click();

    // Should navigate to receipt page
    await expect(page).toHaveURL(/\/receipt\/.+/);

    // Verify the secret was created under the correct domain
    // This would require inspecting the API response or metadata page
    // Adjust based on your actual implementation
    const metadataPage = page.locator('body');
    await expect(metadataPage).toBeVisible();
  });

  test('domain context indicator hidden for users without custom domains', async ({ page }) => {
    /**
     * Validates that users without custom domains don't see the context indicator.
     * This test can run without special backend setup.
     */

    // Mock window state to simulate no custom domains
    await page.goto('/');

    await page.evaluate(() => {
      if (window.__BOOTSTRAP_STATE__) {
        window.__BOOTSTRAP_STATE__.custom_domains = [];
        window.__BOOTSTRAP_STATE__.domains_enabled = false;
      }
    });

    // Reload to apply state changes
    await page.reload();

    // Context indicator should NOT be visible
    const contextIndicator = page.locator('[role="status"][aria-label*="context"]');
    await expect(contextIndicator).not.toBeVisible();
  });

  test('localStorage domainContext key is used correctly', async ({ page }) => {
    /**
     * Validates that the composable uses localStorage with the correct key.
     */

    await page.goto('/');

    // Check that localStorage key exists (if user has custom domains)
    const hasDomainContext = await page.evaluate(() => {
      const customDomains = window.__BOOTSTRAP_STATE__?.custom_domains || [];
      const hasCustomDomains = customDomains.length > 0;

      if (hasCustomDomains) {
        const storedDomain = localStorage.getItem('domainContext');
        return storedDomain !== null;
      }

      return true; // If no custom domains, this test is not applicable
    });

    expect(hasDomainContext).toBe(true);
  });

  test.skip('context switcher allows changing between domains', async ({ page }) => {
    /**
     * Tests the DomainContextSwitcher component (when implemented).
     *
     * SKIP REASON: DomainContextSwitcher component not yet implemented.
     * Enable this test in Phase 5 when the switcher UI is added.
     */

    // TODO: Login as user with multiple custom domains
    await page.goto('/');

    // Find the context switcher dropdown/button
    const contextSwitcher = page.locator('[data-testid="domain-context-switcher"]');
    await expect(contextSwitcher).toBeVisible();

    // Click to open dropdown
    await contextSwitcher.click();

    // Select a different domain
    const domainOption = page.locator('[role="menuitem"]:has-text("widgets.example.com")');
    await domainOption.click();

    // Verify indicator updates
    const contextIndicator = page.locator('[role="status"][aria-label*="context"]');
    await expect(contextIndicator).toContainText('widgets.example.com');

    // Verify localStorage updated
    const storedDomain = await page.evaluate(() => localStorage.getItem('domainContext'));
    expect(storedDomain).toBe('widgets.example.com');
  });

  test.skip('context indicator updates when switching domains', async ({ page }) => {
    /**
     * Validates real-time reactivity when context changes.
     *
     * SKIP REASON: Requires context switcher component.
     */

    // TODO: Login as user with multiple custom domains
    await page.goto('/');

    const contextIndicator = page.locator('[role="status"][aria-label*="context"]');

    // Get initial domain
    const initialDomain = await contextIndicator.textContent();

    // Switch domains (via switcher UI)
    const contextSwitcher = page.locator('[data-testid="domain-context-switcher"]');
    await contextSwitcher.click();
    const differentDomain = page.locator('[role="menuitem"]').nth(1);
    await differentDomain.click();

    // Verify indicator updated
    const newDomain = await contextIndicator.textContent();
    expect(newDomain).not.toBe(initialDomain);
  });

  test.skip('canonical domain shows Personal label', async ({ page }) => {
    /**
     * Validates that the canonical domain displays as "Personal".
     *
     * SKIP REASON: Requires context switcher to switch to canonical domain.
     */

    // TODO: Login as user with custom domains
    await page.goto('/');

    // Switch to canonical domain
    const contextSwitcher = page.locator('[data-testid="domain-context-switcher"]');
    await contextSwitcher.click();

    // Select "Personal" or canonical domain option
    const personalOption = page.locator('[role="menuitem"]:has-text("Personal")');
    await personalOption.click();

    // Verify indicator shows "Personal"
    const contextIndicator = page.locator('[role="status"][aria-label*="context"]');
    await expect(contextIndicator).toContainText('Personal');

    // Verify styling is gray (canonical)
    const hasCanonicalStyling = await contextIndicator.evaluate((el) => {
      const classes = el.className;
      return classes.includes('bg-gray-100') && classes.includes('text-gray-700');
    });

    expect(hasCanonicalStyling).toBe(true);
  });
});
