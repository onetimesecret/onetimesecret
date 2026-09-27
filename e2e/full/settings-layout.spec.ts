// e2e/full/settings-layout.spec.ts

import { expect, type Page, test } from '@playwright/test';

/**
 * E2E Tests - Account Settings Layout
 *
 * Validates SettingsLayout (src/apps/workspace/layouts/SettingsLayout.vue):
 * a page header (h1 "Account" + "Back to Dashboard" link), a horizontal tab
 * bar (nav "Settings navigation") and the section panel below it. Child
 * pages (Change Email, Change Password, ...) are reached through links in
 * the section panels, not through the tab bar.
 *
 * ## Prerequisites
 *
 * Runs in the full-auth lane as the storageState owner (e2e/global.setup.ts):
 * the account has a password and owns its default org, so the tab bar shows
 * Profile, Security, API Key, Region and Careful Consideration Zone, and the
 * Security panel shows the password and active-sessions cards.
 *
 * ## Running Tests
 *
 * ```bash
 * PLAYWRIGHT_BASE_URL=http://localhost:3000 \
 *   pnpm test:playwright e2e/full/settings-layout.spec.ts
 * ```
 *
 * ## Test Categories
 *
 * 1. Settings Page Navigation - tab links and panel links route correctly
 * 2. Settings Sections Rendering - each section panel renders its content
 * 3. Mobile Responsive Behavior - the tab bar fits small screens
 * 4. Route Transitions - navigation between settings pages keeps the layout
 */

const EXPECTED_TABS = ['Profile', 'Security', 'API Key', 'Region', 'Careful Consideration Zone'];

function settingsNav(page: Page) {
  return page.getByRole('navigation', { name: 'Settings navigation' });
}

function tab(page: Page, name: string) {
  return settingsNav(page).getByRole('link', { name, exact: true });
}

/** Panel content lives in <main>; the tab bar and header are above it. */
function panelHeading(page: Page, name: string) {
  return page.getByRole('main').getByRole('heading', { level: 2, name, exact: true });
}

test.describe('E2E - Settings Layout', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test.describe('Settings Page Navigation', () => {
    test('tab navigation renders all main sections', async ({ page }) => {
      await page.goto('/account/settings/profile');

      await expect(settingsNav(page)).toBeVisible();
      await expect(settingsNav(page).getByRole('link')).toHaveText(EXPECTED_TABS);
    });

    test('clicking navigation item navigates to correct route', async ({ page }) => {
      await page.goto('/account/settings/profile');

      await tab(page, 'Security').click();

      await expect(page).toHaveURL(/\/account\/settings\/security$/);
      // The Security panel is its card grid; the password card is always
      // present for a password account.
      await expect(panelHeading(page, 'Change Password')).toBeVisible();
    });

    test('active navigation item is marked aria-current', async ({ page }) => {
      // /account/settings/profile redirects to /profile/preferences; the
      // Profile tab still has to be the current one.
      await page.goto('/account/settings/profile');
      await expect(page).toHaveURL(/\/account\/settings\/profile\/preferences$/);

      await expect(tab(page, 'Profile')).toHaveAttribute('aria-current', 'page');
      await expect(settingsNav(page).locator('[aria-current]')).toHaveCount(1);

      await tab(page, 'Security').click();
      await expect(page).toHaveURL(/\/account\/settings\/security$/);

      await expect(tab(page, 'Security')).toHaveAttribute('aria-current', 'page');
      await expect(tab(page, 'Profile')).not.toHaveAttribute('aria-current');
      await expect(settingsNav(page).locator('[aria-current]')).toHaveCount(1);
    });

    test('section panels link to their child pages', async ({ page }) => {
      await page.goto('/account/settings/profile');

      // Profile panel: Change Email (owner with a password)
      await expect(page.getByRole('main').getByRole('link', { name: 'Change Email' })).toHaveAttribute(
        'href',
        '/account/settings/profile/email'
      );

      await tab(page, 'Security').click();
      await expect(page).toHaveURL(/\/account\/settings\/security$/);

      // Security panel: every card action is a child route of the tab
      await expect(
        page.getByRole('main').locator('a[href="/account/settings/security/password"]')
      ).toBeVisible();
      await expect(
        page.getByRole('main').locator('a[href="/account/settings/security/sessions"]')
      ).toBeVisible();
    });

    test('child routes keep their parent tab current', async ({ page }) => {
      await page.goto('/account/settings/security');

      await page.getByRole('main').locator('a[href="/account/settings/security/password"]').click();

      await expect(page).toHaveURL(/\/account\/settings\/security\/password$/);
      await expect(tab(page, 'Security')).toHaveAttribute('aria-current', 'page');
      await expect(settingsNav(page).locator('[aria-current]')).toHaveCount(1);
    });
  });

  test.describe('Settings Sections Rendering', () => {
    test('Profile settings section renders correctly', async ({ page }) => {
      await page.goto('/account/settings/profile');

      const main = page.getByRole('main');
      await expect(panelHeading(page, 'Email Address')).toBeVisible();
      await expect(panelHeading(page, 'Preferences')).toBeVisible();
      await expect(main.getByText('Appearance', { exact: true })).toBeVisible();
      await expect(main.getByRole('button', { name: 'Toggle dark mode' })).toBeVisible();
    });

    test('Security settings section renders correctly', async ({ page }) => {
      await page.goto('/account/settings/security');

      // Cards render after the account-info fetch resolves; web-first
      // assertions wait for them.
      await expect(panelHeading(page, 'Change Password')).toBeVisible();
      await expect(panelHeading(page, 'Active Sessions')).toBeVisible();
    });

    test('API settings section renders correctly', async ({ page }) => {
      await page.goto('/account/settings/api');

      await expect(panelHeading(page, 'API Key')).toBeVisible();
      await expect(panelHeading(page, 'API Username')).toBeVisible();
      await expect(page.getByTestId('api-username-field')).toBeVisible();
    });

    test('section cards are headed by h2 in order', async ({ page }) => {
      await page.goto('/account/settings/profile');

      // The layout owns the only h1; each panel card starts with an h2.
      await expect(page.getByRole('main').getByRole('heading', { level: 2 })).toHaveText([
        'Email Address',
        'Preferences',
      ]);
    });
  });

  test.describe('Mobile Responsive Behavior', () => {
    test('tab bar fits the mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await page.goto('/account/settings/profile');

      await expect(settingsNav(page)).toBeVisible();
      await expect(panelHeading(page, 'Email Address')).toBeVisible();

      // The tab bar scrolls inside its own box (overflow-x-auto) rather than
      // widening the page.
      await expect
        .poll(async () => {
          const box = await settingsNav(page).boundingBox();
          return box ? box.x >= 0 && box.x + box.width <= 375 : false;
        })
        .toBe(true);
    });

    test('navigation is accessible on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await page.goto('/account/settings/profile');

      await expect(settingsNav(page)).toBeVisible();

      // Tabs past the fold are scrolled into view by the click.
      await tab(page, 'Careful Consideration Zone').click();
      await expect(page).toHaveURL(/\/account\/settings\/caution$/);

      await tab(page, 'Security').click();
      await expect(page).toHaveURL(/\/account\/settings\/security$/);
    });

    test('content does not overflow horizontally on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await page.goto('/account/settings/profile');

      // Measure after the panel content (the widest part) has rendered.
      await expect(panelHeading(page, 'Preferences')).toBeVisible();

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
  });

  test.describe('Route Transitions', () => {
    test('navigation between settings pages preserves layout', async ({ page }) => {
      await page.goto('/account/settings/profile');

      const routes = [
        { tab: 'Security', urlPattern: /\/account\/settings\/security$/ },
        { tab: 'API Key', urlPattern: /\/account\/settings\/api$/ },
        { tab: 'Profile', urlPattern: /\/account\/settings\/profile\/preferences$/ },
      ];

      for (const route of routes) {
        await tab(page, route.tab).click();
        await expect(page).toHaveURL(route.urlPattern);

        await expect(page.getByRole('heading', { level: 1, name: 'Account' })).toBeVisible();
        await expect(tab(page, route.tab)).toHaveAttribute('aria-current', 'page');
      }
    });

    test('page header persists across settings tabs', async ({ page }) => {
      for (const url of ['/account/settings/profile', '/account/settings/security']) {
        await page.goto(url);

        await expect(page.getByRole('heading', { level: 1, name: 'Account' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'Back to Dashboard' })).toHaveAttribute(
          'href',
          '/'
        );
      }
    });

    test('Back to Dashboard link leaves settings', async ({ page }) => {
      await page.goto('/account/settings/profile');

      await page.getByRole('link', { name: 'Back to Dashboard' }).click();

      // The link targets '/', which sends a signed-in user on to /dashboard.
      await expect(page).toHaveURL(/\/dashboard$/);
      await expect(settingsNav(page)).toHaveCount(0);
    });

    test('browser back button works correctly', async ({ page }) => {
      await page.goto('/account/settings/profile');
      await expect(page).toHaveURL(/\/account\/settings\/profile\/preferences$/);

      await tab(page, 'Security').click();
      await expect(page).toHaveURL(/\/account\/settings\/security$/);

      await page.goBack();

      await expect(page).toHaveURL(/\/account\/settings\/profile\/preferences$/);
      await expect(tab(page, 'Profile')).toHaveAttribute('aria-current', 'page');
    });

    test('direct URL navigation works', async ({ page }) => {
      const pages = [
        { url: '/account/settings/profile', current: 'Profile', heading: 'Email Address' },
        { url: '/account/settings/security', current: 'Security', heading: 'Change Password' },
        { url: '/account/settings/api', current: 'API Key', heading: 'API Key' },
      ];

      for (const target of pages) {
        await page.goto(target.url);
        await expect(tab(page, target.current)).toHaveAttribute('aria-current', 'page');
        await expect(panelHeading(page, target.heading)).toBeVisible();
      }
    });
  });

  test.describe('Accessibility', () => {
    test('settings navigation is exposed as a named landmark', async ({ page }) => {
      await page.goto('/account/settings/profile');

      // Resolving by role + accessible name is the assertion.
      await expect(settingsNav(page)).toBeVisible();
    });

    test('page has single h1', async ({ page }) => {
      await page.goto('/account/settings/profile');

      await expect(page.getByRole('heading', { level: 1, name: 'Account' })).toBeVisible();
      await expect(page.locator('h1')).toHaveCount(1);
    });

    test('navigation links are focusable', async ({ page }) => {
      await page.goto('/account/settings/profile');
      await expect(settingsNav(page)).toBeVisible();

      // Tab from the top of the document until focus lands in the tab bar.
      let foundNavLink = false;
      for (let i = 0; i < 20; i++) {
        await page.keyboard.press('Tab');
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
      }

      expect(foundNavLink).toBe(true);
    });

    test('Enter key activates navigation links', async ({ page }) => {
      await page.goto('/account/settings/profile');

      await tab(page, 'Security').focus();
      await page.keyboard.press('Enter');

      await expect(page).toHaveURL(/\/account\/settings\/security$/);
    });
  });

  test.describe('Error Handling', () => {
    test('handles missing settings route gracefully', async ({ page }) => {
      await page.goto('/account/settings/nonexistent');

      // The catch-all route renders the 404 view, not a crash or blank page.
      await expect(page.getByRole('heading', { name: /404/ })).toBeVisible();
      await expect(page.locator('body')).not.toContainText(/stack trace/i);
    });

    test('settings page recovers from failed API calls', async ({ page }) => {
      // Block API calls to simulate failure
      await page.route('**/api/**', (route) => route.abort());

      await page.goto('/account/settings/profile');

      // The layout and the panels that need no API data still render.
      await expect(page.getByRole('heading', { level: 1, name: 'Account' })).toBeVisible();
      await expect(settingsNav(page).getByRole('link')).toHaveText(EXPECTED_TABS);
      await expect(panelHeading(page, 'Preferences')).toBeVisible();
    });
  });
});

/**
 * Manual Test Cases Checklist
 *
 * These test cases should be verified manually if automation is not feasible:
 *
 * ## Navigation Testing
 * - [ ] All tab bar items display correctly
 * - [ ] Active state styling is visible on current tab
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
 * - [ ] Mobile (375px): Tab bar scrolls horizontally inside its own box
 * - [ ] Tablet (768px): Layout transitions smoothly
 * - [ ] Desktop (1280px): Content column stays at max-w-5xl
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
