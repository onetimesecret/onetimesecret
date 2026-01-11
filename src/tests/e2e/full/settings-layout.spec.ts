// src/tests/e2e/settings-layout.spec.ts

import { test, expect, Page } from '@playwright/test';

/**
 * E2E Tests - Settings Layout Refactoring Validation
 *
 * These tests validate the SettingsLayout component and its extracted children
 * (SettingsNavigation, SettingsSection) work correctly after refactoring.
 *
 * ## Prerequisites
 *
 * 1. User must be authenticated to access settings pages
 * 2. Application must be running (dev server or production build)
 *
 * ## Running Tests
 *
 * ```bash
 * # Against dev server
 * PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright src/tests/e2e/settings-layout.spec.ts
 *
 * # Against production build
 * pnpm test:playwright src/tests/e2e/settings-layout.spec.ts
 * ```
 *
 * ## Test Categories
 *
 * 1. Settings Page Navigation - sidebar links work correctly
 * 2. Settings Sections Rendering - all sections display properly
 * 3. Mobile Responsive Behavior - layout adapts to small screens
 * 4. Route Transitions - navigation between settings pages is smooth
 */

// Check if test credentials are configured (required for authenticated tests)
const hasTestCredentials = !!(process.env.TEST_USER_EMAIL && process.env.TEST_USER_PASSWORD);

// Helper to authenticate user (adjust based on actual auth flow)
async function loginUser(page: Page): Promise<void> {
  // Navigate to login page
  await page.goto('/signin');

  // Fill login form - adjust selectors to match actual form
  const emailInput = page.locator('input[type="email"], input[name="email"]');
  const passwordInput = page.locator('input[type="password"], input[name="password"]');
  const submitButton = page.locator('button[type="submit"]');

  // Check if login form is visible
  if (await emailInput.isVisible()) {
    await emailInput.fill(process.env.TEST_USER_EMAIL || 'test@example.com');
    await passwordInput.fill(process.env.TEST_USER_PASSWORD || 'testpassword');
    await submitButton.click();

    // Wait for redirect to dashboard/account (longer timeout for CI)
    await page.waitForURL(/\/(account|dashboard)/, { timeout: 30000 });
  }
}

test.describe('E2E - Settings Layout Refactoring', () => {
  // Skip all tests if test credentials are not configured
  // These tests require authentication which needs a seeded test user
  test.skip(!hasTestCredentials, 'Skipping: TEST_USER_EMAIL and TEST_USER_PASSWORD required');

  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test.describe('Settings Page Navigation', () => {
    test('sidebar navigation renders all main sections', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Wait for settings layout to load
      await page.waitForSelector('nav[aria-label="Settings navigation"]');

      // Verify main navigation items are present
      const nav = page.locator('nav[aria-label="Settings navigation"]');
      await expect(nav).toBeVisible();

      // Check for expected navigation items
      await expect(nav.getByText('Profile')).toBeVisible();
      await expect(nav.getByText('Security')).toBeVisible();
      await expect(nav.getByText('API')).toBeVisible();
    });

    test('clicking navigation item navigates to correct route', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Click on Security link
      await page.click('nav[aria-label="Settings navigation"] a:has-text("Security")');

      // Verify URL changed
      await expect(page).toHaveURL(/\/account\/settings\/security/);

      // Verify content changed (looking for security-specific content)
      await expect(page.locator('h1, h2').filter({ hasText: /security/i }).first()).toBeVisible();
    });

    test('active navigation item is visually distinguished', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Find the Profile nav item
      const profileLink = page.locator('nav[aria-label="Settings navigation"] a:has-text("Profile")');

      // Check it has active styling (brand color background)
      await expect(profileLink).toHaveClass(/bg-brand|active|selected/);

      // Navigate to Security and verify active state changes
      await page.click('nav[aria-label="Settings navigation"] a:has-text("Security")');
      await page.waitForURL(/\/account\/settings\/security/);

      const securityLink = page.locator('nav[aria-label="Settings navigation"] a:has-text("Security")');
      await expect(securityLink).toHaveClass(/bg-brand|active|selected/);

      // Profile should no longer be active
      await expect(profileLink).not.toHaveClass(/bg-brand-50|active/);
    });

    test('child navigation items appear when parent is active', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Profile children should be visible
      const preferencesLink = page.locator('a:has-text("Preferences")');
      await expect(preferencesLink).toBeVisible();

      // Navigate to Security
      await page.click('nav[aria-label="Settings navigation"] a:has-text("Security")');
      await page.waitForURL(/\/account\/settings\/security/);

      // Security children should now be visible
      const passwordLink = page.locator('a:has-text("Change Password"), a:has-text("Password")');
      await expect(passwordLink).toBeVisible();
    });

    test('child navigation routes work correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Click on Preferences (child of Profile)
      await page.click('a:has-text("Preferences")');

      // Verify URL
      await expect(page).toHaveURL(/\/account\/settings\/profile\/preferences/);
    });
  });

  test.describe('Settings Sections Rendering', () => {
    test('Profile settings section renders correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Check for profile-specific content
      const content = page.locator('main');
      await expect(content).toBeVisible();

      // Look for typical profile settings elements
      // Adjust selectors based on actual content
      const hasProfileContent =
        (await page.locator('text=/theme|appearance|language/i').count()) > 0 ||
        (await page.locator('section').count()) > 0;

      expect(hasProfileContent).toBe(true);
    });

    test('Security settings section renders correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/security');

      const content = page.locator('main');
      await expect(content).toBeVisible();

      // Look for security-specific content
      const hasSecurityContent =
        (await page.locator('text=/password|mfa|two-factor|session/i').count()) > 0;

      expect(hasSecurityContent).toBe(true);
    });

    test('API settings section renders correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/api');

      const content = page.locator('main');
      await expect(content).toBeVisible();

      // Look for API-specific content
      const hasApiContent =
        (await page.locator('text=/api.*key|token|generate/i').count()) > 0;

      expect(hasApiContent).toBe(true);
    });

    test('section cards have proper structure', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Check for card-style sections
      const sections = page.locator('section.rounded-lg, div.rounded-lg.border');
      const sectionCount = await sections.count();

      expect(sectionCount).toBeGreaterThan(0);

      // Verify first section has header
      const firstSection = sections.first();
      const header = firstSection.locator('h2, .font-semibold');
      await expect(header.first()).toBeVisible();
    });
  });

  test.describe('Mobile Responsive Behavior', () => {
    test('layout adapts to mobile viewport', async ({ page }) => {
      await loginUser(page);

      // Set mobile viewport
      await page.setViewportSize({ width: 375, height: 667 });

      await page.goto('/account/settings/profile');

      // Sidebar should stack above content on mobile
      const sidebar = page.locator('aside, nav[aria-label="Settings navigation"]');
      const main = page.locator('main');

      await expect(sidebar).toBeVisible();
      await expect(main).toBeVisible();

      // Check layout direction (should be column on mobile)
      const layoutContainer = page.locator('.flex.flex-col');
      await expect(layoutContainer).toBeVisible();
    });

    test('navigation is accessible on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Navigation should still be usable
      const nav = page.locator('nav[aria-label="Settings navigation"]');
      await expect(nav).toBeVisible();

      // Should be able to click navigation items
      await page.click('nav a:has-text("Security")');
      await expect(page).toHaveURL(/\/account\/settings\/security/);
    });

    test('content does not overflow horizontally on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Wait for layout to stabilize
      await page.waitForLoadState('networkidle');
      await page.waitForTimeout(300);

      // Check for horizontal overflow
      const { hasOverflow, scrollWidth, viewportWidth } = await page.evaluate(() => {
        const scrollWidth = document.body.scrollWidth;
        const viewportWidth = window.innerWidth;
        return {
          hasOverflow: scrollWidth - viewportWidth > 15,
          scrollWidth,
          viewportWidth,
        };
      });

      expect(
        hasOverflow,
        `Page has horizontal overflow: scrollWidth=${scrollWidth}, viewportWidth=${viewportWidth}`
      ).toBe(false);
    });

    test('sidebar width is correct on desktop', async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });

      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Sidebar should have fixed width on desktop (md:w-72 = 288px)
      const sidebar = page.locator('aside').first();
      const box = await sidebar.boundingBox();

      if (box) {
        // md:w-72 = 18rem = 288px (approximately)
        expect(box.width).toBeGreaterThanOrEqual(250);
        expect(box.width).toBeLessThanOrEqual(320);
      }
    });
  });

  test.describe('Route Transitions', () => {
    test('navigation between settings pages preserves layout', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Navigate through multiple pages
      const routes = [
        { link: 'Security', urlPattern: /security/ },
        { link: 'API', urlPattern: /api/ },
        { link: 'Profile', urlPattern: /profile/ },
      ];

      for (const route of routes) {
        await page.click(`nav[aria-label="Settings navigation"] a:has-text("${route.link}")`);
        await expect(page).toHaveURL(route.urlPattern);

        // Verify layout is still intact
        await expect(page.locator('nav[aria-label="Settings navigation"]')).toBeVisible();
        await expect(page.locator('main')).toBeVisible();
      }
    });

    test('breadcrumb updates on navigation', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Check breadcrumb shows Settings
      const breadcrumb = page.locator('nav.breadcrumb, nav:has-text("Account")');
      await expect(breadcrumb).toBeVisible();
      await expect(breadcrumb.getByText('Settings')).toBeVisible();

      // Account link should be present in breadcrumb
      const accountLink = breadcrumb.locator('a:has-text("Account")');
      await expect(accountLink).toBeVisible();
    });

    test('clicking breadcrumb Account link navigates to account page', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Click Account in breadcrumb
      await page.click('nav a:has-text("Account")');

      // Should navigate to account page
      await expect(page).toHaveURL(/\/account$/);
    });

    test('browser back button works correctly', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Navigate to Security
      await page.click('nav[aria-label="Settings navigation"] a:has-text("Security")');
      await expect(page).toHaveURL(/\/account\/settings\/security/);

      // Go back
      await page.goBack();

      // Should be back on profile
      await expect(page).toHaveURL(/\/account\/settings\/profile/);
    });

    test('direct URL navigation works', async ({ page }) => {
      await loginUser(page);

      // Navigate directly to various settings pages
      const pages = [
        '/account/settings/profile',
        '/account/settings/security',
        '/account/settings/api',
      ];

      for (const url of pages) {
        await page.goto(url);
        await expect(page.locator('nav[aria-label="Settings navigation"]')).toBeVisible();
        await expect(page.locator('main')).toBeVisible();
      }
    });
  });

  test.describe('Accessibility', () => {
    test('settings navigation has proper ARIA attributes', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      const nav = page.locator('nav[aria-label="Settings navigation"]');
      await expect(nav).toBeVisible();
      await expect(nav).toHaveAttribute('aria-label', 'Settings navigation');
    });

    test('page has single h1', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      const h1Elements = page.locator('h1');
      const count = await h1Elements.count();

      expect(count).toBe(1);
    });

    test('navigation links are focusable', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Tab to first nav link
      await page.keyboard.press('Tab');

      // Eventually should reach a nav link (may need multiple tabs)
      let foundNavLink = false;
      for (let i = 0; i < 20; i++) {
        const focused = await page.evaluate(() => {
          const el = document.activeElement;
          return {
            tagName: el?.tagName,
            inNav: el?.closest('nav[aria-label="Settings navigation"]') !== null,
          };
        });

        if (focused.tagName === 'A' && focused.inNav) {
          foundNavLink = true;
          break;
        }
        await page.keyboard.press('Tab');
      }

      expect(foundNavLink).toBe(true);
    });

    test('Enter key activates navigation links', async ({ page }) => {
      await loginUser(page);
      await page.goto('/account/settings/profile');

      // Focus on Security link
      const securityLink = page.locator('nav[aria-label="Settings navigation"] a:has-text("Security")');
      await securityLink.focus();

      // Press Enter
      await page.keyboard.press('Enter');

      // Should navigate
      await expect(page).toHaveURL(/\/account\/settings\/security/);
    });
  });

  test.describe('Error Handling', () => {
    test('handles missing settings route gracefully', async ({ page }) => {
      await loginUser(page);

      await page.goto('/account/settings/nonexistent');

      // Should either redirect or show 404
      // Not crash or show blank page
      await expect(page.locator('body')).toBeVisible();

      // Should not show stack trace
      const bodyText = await page.textContent('body');
      expect(bodyText?.toLowerCase()).not.toContain('stack trace');
    });

    test('settings page recovers from failed API calls', async ({ page }) => {
      await loginUser(page);

      // Block API calls to simulate failure
      await page.route('**/api/**', (route) => route.abort());

      await page.goto('/account/settings/profile');

      // Page should still load, possibly with error state
      await expect(page.locator('body')).toBeVisible();

      // Should show some content, not blank
      const content = await page.textContent('body');
      expect(content?.length).toBeGreaterThan(100);
    });
  });
});

/**
 * Manual Test Cases Checklist
 *
 * These test cases should be verified manually if automation is not feasible:
 *
 * ## Navigation Testing
 * - [ ] All sidebar navigation items display correctly
 * - [ ] Active state styling is visible on current page
 * - [ ] Child items expand/collapse appropriately
 * - [ ] Icons render correctly for all items
 * - [ ] Hover states work on all links
 *
 * ## Visual Testing
 * - [ ] Layout matches design mockups
 * - [ ] Dark mode styling is correct
 * - [ ] Spacing and alignment is consistent
 * - [ ] Typography hierarchy is clear
 * - [ ] Card styling (borders, shadows) is correct
 *
 * ## Responsive Testing
 * - [ ] Mobile (375px): Sidebar stacks above content
 * - [ ] Tablet (768px): Layout transitions smoothly
 * - [ ] Desktop (1280px): Side-by-side layout
 * - [ ] Large (1920px): Content stays centered, max-width honored
 *
 * ## Interaction Testing
 * - [ ] Keyboard navigation through all links
 * - [ ] Focus states are visible
 * - [ ] Touch targets are large enough on mobile
 * - [ ] Scroll behavior is smooth
 *
 * ## Integration Testing
 * - [ ] Settings changes persist after navigation
 * - [ ] Form submissions work from each section
 * - [ ] Error messages display correctly
 * - [ ] Loading states are visible during API calls
 */
