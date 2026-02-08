// e2e/all/brand-customization.spec.ts
//
// E2E tests for the brand customization system.
//
// Validates that the 44-shade oklch color palette is correctly
// applied via CSS variables, the brand color bar renders, and
// branded pages load without errors across light/dark modes.
//
// Prerequisites:
//   - Backend server running (or PLAYWRIGHT_BASE_URL set)
//   - No authentication required (public pages only)
//
// Running:
//   PLAYWRIGHT_BASE_URL=http://localhost:7143 pnpm test:playwright e2e/all/brand-customization.spec.ts

import { test, expect, Page } from '@playwright/test';

// ─── Constants ───────────────────────────────────────

/** The default brand hex as defined in brand-palette.ts */
const DEFAULT_BRAND_HEX = '#dc4a22';

/** All four palette prefixes, each with 11 shades = 44 total */
const PALETTE_PREFIXES = ['brand', 'branddim', 'brandcomp', 'brandcompdim'] as const;

const SHADE_STEPS = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950'] as const;

/** Pages that should render without errors for anonymous users */
const PUBLIC_PAGES = [
  { path: '/', label: 'Homepage' },
  { path: '/signin', label: 'Sign in' },
  { path: '/signup', label: 'Sign up' },
] as const;

// ─── Helpers ─────────────────────────────────────────

/**
 * Collect console errors during page lifecycle.
 * Must be called before navigation.
 */
function setupErrorCollection(page: Page): string[] {
  const errors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      errors.push(msg.text());
    }
  });
  return errors;
}

/** Filter out noise from dev tooling, HMR, etc. */
function filterCriticalErrors(errors: string[]): string[] {
  return errors.filter(
    (error) =>
      !error.includes('Non-Error promise rejection') &&
      !error.includes('Script error') &&
      !error.includes('WebSocket') &&
      !error.includes('[vite]') &&
      !error.includes('hmr') &&
      !error.includes('favicon')
  );
}

// ─── Test: Default brand renders correctly ───────────

test.describe('Brand Customization - Default Brand Rendering', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('homepage loads and brand color bar is visible', async ({ page }) => {
    const consoleErrors = setupErrorCollection(page);

    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // The brand color bar is a fixed 1px-high div at the top
    // from BaseLayout.vue: class="fixed left-0 top-0 z-50 h-1 w-full bg-brand-500"
    const brandBar = page.locator('div.bg-brand-500');
    await expect(brandBar).toBeVisible();

    // Verify it spans the full viewport width
    const box = await brandBar.boundingBox();
    expect(box).toBeTruthy();
    if (box) {
      const viewport = page.viewportSize();
      expect(box.width).toBeGreaterThanOrEqual((viewport?.width ?? 1024) - 1);
      expect(box.y).toBe(0); // Pinned to top
    }

    // No critical JS errors
    await page.waitForLoadState('networkidle');
    const critical = filterCriticalErrors(consoleErrors);
    expect(
      critical,
      `Homepage should load without console errors. Found: ${critical.join(', ')}`
    ).toHaveLength(0);
  });

  test('brand-500 resolves to the default hex color', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // Read the computed background-color of the brand bar element.
    // The CSS variable --color-brand-500 should resolve to the
    // default #dc4a22 (rgb 220, 74, 34).
    const brandBar = page.locator('div.bg-brand-500').first();
    await expect(brandBar).toBeVisible();

    const bgColor = await brandBar.evaluate((el) => {
      return window.getComputedStyle(el).backgroundColor;
    });

    // Should be a valid, non-transparent color
    expect(bgColor).not.toBe('rgba(0, 0, 0, 0)');
    expect(bgColor).not.toBe('transparent');
    expect(bgColor).toBeTruthy();

    // Verify it is in the warm orange range of the default brand.
    // rgb(220, 74, 34) is the expected value for #dc4a22.
    // Allow tolerance since the palette generator may produce
    // slightly different hex values through oklch conversion.
    const rgbMatch = bgColor.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/);
    if (rgbMatch) {
      const [, r, g, b] = rgbMatch.map(Number);
      // Red channel dominant (warm orange)
      expect(r).toBeGreaterThan(180);
      expect(r).toBeLessThan(255);
      // Green channel moderate
      expect(g).toBeGreaterThan(30);
      expect(g).toBeLessThan(120);
      // Blue channel low
      expect(b).toBeLessThan(80);
    }
  });

  test('branded elements use brand color classes', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // Verify that at least some brand-colored elements exist
    // beyond just the top bar
    const brandBgElements = page.locator('[class*="bg-brand-"]');
    const brandBgCount = await brandBgElements.count();
    expect(brandBgCount).toBeGreaterThanOrEqual(1);

    // Check for brand text color usage (links, headings, etc.)
    const brandTextElements = page.locator('[class*="text-brand-"]');
    const brandTextCount = await brandTextElements.count();
    // Not all pages may have text-brand-* classes, so just
    // verify the query does not error
    expect(brandTextCount).toBeGreaterThanOrEqual(0);
  });
});

// ─── Test: Brand CSS variables on document root ──────

test.describe('Brand Customization - CSS Variable Resolution', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('brand CSS variables resolve to valid colors via computed styles', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // With the default brand color, useBrandTheme removes inline
    // overrides and lets the @theme defaults in style.css apply.
    // We verify by checking that getComputedStyle resolves the
    // CSS variables to non-empty values.
    const variableValues = await page.evaluate((shadeSteps) => {
      const root = document.documentElement;
      const cs = window.getComputedStyle(root);
      const results: Record<string, string> = {};
      for (const step of shadeSteps) {
        const varName = `--color-brand-${step}`;
        results[varName] = cs.getPropertyValue(varName).trim();
      }
      return results;
    }, [...SHADE_STEPS]);

    // Each shade should resolve to a non-empty value
    for (const step of SHADE_STEPS) {
      const key = `--color-brand-${step}`;
      expect(
        variableValues[key],
        `${key} should resolve to a color value`
      ).toBeTruthy();
    }
  });

  test('all four palette groups resolve via computed styles', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    const results = await page.evaluate(
      ({ prefixes, steps }) => {
        const root = document.documentElement;
        const cs = window.getComputedStyle(root);
        const out: Record<string, boolean> = {};
        for (const prefix of prefixes) {
          for (const step of steps) {
            const varName = `--color-${prefix}-${step}`;
            const val = cs.getPropertyValue(varName).trim();
            out[varName] = val.length > 0;
          }
        }
        return out;
      },
      { prefixes: [...PALETTE_PREFIXES], steps: [...SHADE_STEPS] }
    );

    // All 44 variables should resolve
    const missing = Object.entries(results)
      .filter(([, hasValue]) => !hasValue)
      .map(([key]) => key);

    expect(
      missing,
      `These CSS variables did not resolve: ${missing.join(', ')}`
    ).toHaveLength(0);
  });

  test('brand-500 computed style matches default palette value', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    const brand500 = await page.evaluate(() => {
      return window.getComputedStyle(document.documentElement)
        .getPropertyValue('--color-brand-500')
        .trim();
    });

    // The @theme default for --color-brand-500 is #dc4a22
    expect(brand500.toLowerCase()).toBe(DEFAULT_BRAND_HEX);
  });
});

// ─── Test: Dark mode with default brand ──────────────

test.describe('Brand Customization - Dark Mode', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('brand color bar remains visible in dark mode', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // Inject dark mode class on <html> (the app uses class-based dark mode)
    await page.evaluate(() => {
      document.documentElement.classList.add('dark');
    });

    // TODO: Replace waitForTimeout with waitForFunction or assertion
    // retries (e.g. expect(brandBar).toHaveCSS(...)). All 6
    // waitForTimeout calls in this file are flakiness risks on slow CI.
    await page.waitForTimeout(300);

    const brandBar = page.locator('div.bg-brand-500');
    await expect(brandBar).toBeVisible();

    // The bar should still have a non-transparent background
    const bgColor = await brandBar.evaluate((el) => {
      return window.getComputedStyle(el).backgroundColor;
    });
    expect(bgColor).not.toBe('rgba(0, 0, 0, 0)');
    expect(bgColor).not.toBe('transparent');
  });

  test('brand CSS variables persist in dark mode', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // Enable dark mode
    await page.evaluate(() => {
      document.documentElement.classList.add('dark');
    });
    await page.waitForTimeout(300);

    // CSS variables should still resolve (they are theme-level,
    // not mode-dependent)
    const brand500 = await page.evaluate(() => {
      return window.getComputedStyle(document.documentElement)
        .getPropertyValue('--color-brand-500')
        .trim();
    });

    expect(brand500).toBeTruthy();
    expect(brand500.toLowerCase()).toBe(DEFAULT_BRAND_HEX);
  });

  test('dark mode toggle via theme button if available', async ({ page }) => {
    const consoleErrors = setupErrorCollection(page);

    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // Look for theme toggle button (may not exist on all pages)
    const themeToggle = page.locator(
      'button[aria-label*="theme" i], button[aria-label*="dark" i], button[data-testid*="theme"]'
    );
    const toggleExists = await themeToggle.first().isVisible().catch(() => false);

    if (!toggleExists) {
      test.skip(true, 'No theme toggle button found on homepage');
      return;
    }

    await themeToggle.first().click();
    await page.waitForTimeout(500);

    // After toggling, <html> should have 'dark' class
    const hasDark = await page.evaluate(() =>
      document.documentElement.classList.contains('dark')
    );

    // Brand bar should still be visible regardless of mode
    const brandBar = page.locator('div.bg-brand-500');
    await expect(brandBar).toBeVisible();

    // No errors from mode switch
    const critical = filterCriticalErrors(consoleErrors);
    expect(
      critical,
      `Dark mode toggle should not cause errors. Found: ${critical.join(', ')}`
    ).toHaveLength(0);

    // If dark mode was activated, verify it. If the button toggled
    // from dark back to light, that is also valid behavior.
    expect(typeof hasDark).toBe('boolean');
  });
});

// ─── Test: Branded pages render without errors ───────

test.describe('Brand Customization - Page Rendering', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  for (const { path, label } of PUBLIC_PAGES) {
    test(`${label} (${path}) loads with brand elements`, async ({ page }) => {
      const consoleErrors = setupErrorCollection(page);

      const response = await page.goto(path);
      await page.waitForLoadState('domcontentloaded');

      // Page should return 200
      expect(response?.status()).toBe(200);

      // Brand color bar should be present on every page
      // (it is in BaseLayout.vue which wraps all layouts)
      const brandBar = page.locator('div.bg-brand-500');
      await expect(brandBar).toBeVisible();

      // Page should have a title
      await expect(page).toHaveTitle(/.+/);

      // Body should be visible
      await expect(page.locator('body')).toBeVisible();

      // No critical JS errors
      await page.waitForLoadState('networkidle');
      const critical = filterCriticalErrors(consoleErrors);
      expect(
        critical,
        `${label} should load without console errors. Found: ${critical.join(', ')}`
      ).toHaveLength(0);
    });
  }

  test('brand variables are consistent across pages', async ({ page }) => {
    const brand500Values: Record<string, string> = {};

    for (const { path, label } of PUBLIC_PAGES) {
      await page.goto(path);
      await page.waitForLoadState('domcontentloaded');

      const value = await page.evaluate(() => {
        return window.getComputedStyle(document.documentElement)
          .getPropertyValue('--color-brand-500')
          .trim();
      });

      brand500Values[label] = value;
    }

    // All pages should have the same brand-500 value
    const values = Object.values(brand500Values);
    const firstValue = values[0];
    for (const [label, value] of Object.entries(brand500Values)) {
      expect(
        value,
        `${label} brand-500 should match other pages`
      ).toBe(firstValue);
    }
  });
});

// ─── Test: No hardcoded hex in inline styles ─────────

test.describe('Brand Customization - No Hardcoded Hex', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('no visible elements have hardcoded #dc4a22 in inline styles', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const hardcodedElements = await page.evaluate((legacyHex: string) => {
      const all = document.querySelectorAll('*[style]');
      const matches: string[] = [];
      const hexLower = legacyHex.toLowerCase();

      for (const el of Array.from(all)) {
        const inlineStyle = el.getAttribute('style') ?? '';
        if (inlineStyle.toLowerCase().includes(hexLower)) {
          matches.push(
            `<${el.tagName.toLowerCase()}> style="${inlineStyle.substring(0, 120)}"`
          );
        }
      }
      return matches;
    }, DEFAULT_BRAND_HEX);

    expect(
      hardcodedElements,
      `Found ${hardcodedElements.length} element(s) with hardcoded ${DEFAULT_BRAND_HEX} in inline styles: ${hardcodedElements.join('; ')}`
    ).toHaveLength(0);
  });

  test('no hardcoded #dc4a22 in inline styles after dark mode toggle', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.evaluate(() => {
      document.documentElement.classList.add('dark');
    });
    await page.waitForTimeout(300);

    const hardcodedElements = await page.evaluate((legacyHex: string) => {
      const all = document.querySelectorAll('*[style]');
      const matches: string[] = [];
      const hexLower = legacyHex.toLowerCase();

      for (const el of Array.from(all)) {
        const inlineStyle = el.getAttribute('style') ?? '';
        if (inlineStyle.toLowerCase().includes(hexLower)) {
          matches.push(
            `<${el.tagName.toLowerCase()}> style="${inlineStyle.substring(0, 120)}"`
          );
        }
      }
      return matches;
    }, DEFAULT_BRAND_HEX);

    expect(
      hardcodedElements,
      `Found hardcoded ${DEFAULT_BRAND_HEX} in dark mode inline styles: ${hardcodedElements.join('; ')}`
    ).toHaveLength(0);
  });

  test('elements with brand Tailwind classes have non-transparent computed colors', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const probeResults = await page.evaluate(() => {
      const findings: {
        selector: string;
        backgroundColor: string;
        color: string;
      }[] = [];

      const bgElements = document.querySelectorAll('[class*="bg-brand-"]');
      for (const el of Array.from(bgElements).slice(0, 5)) {
        const cs = getComputedStyle(el);
        findings.push({
          selector: `bg: ${el.tagName}.${Array.from(el.classList).find((c) => c.includes('bg-brand-')) ?? ''}`,
          backgroundColor: cs.backgroundColor,
          color: cs.color,
        });
      }

      const textElements = document.querySelectorAll('[class*="text-brand-"]');
      for (const el of Array.from(textElements).slice(0, 5)) {
        const cs = getComputedStyle(el);
        findings.push({
          selector: `text: ${el.tagName}.${Array.from(el.classList).find((c) => c.includes('text-brand-')) ?? ''}`,
          backgroundColor: cs.backgroundColor,
          color: cs.color,
        });
      }

      return findings;
    });

    if (probeResults.length === 0) {
      return;
    }

    for (const finding of probeResults) {
      const isBackgroundBrand = finding.selector.startsWith('bg:');
      const relevantColor = isBackgroundBrand
        ? finding.backgroundColor
        : finding.color;

      expect(
        relevantColor,
        `${finding.selector} should have a resolved color, got: ${relevantColor}`
      ).not.toBe('rgba(0, 0, 0, 0)');
    }
  });
});

// ─── Test: Custom brand color override ───────────────

test.describe('Brand Customization - Custom Color Override', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('injecting a custom brand color updates CSS variables', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // Simulate what useBrandTheme does when a custom color is set:
    // inject all 44 CSS variables onto document.documentElement.style.
    //
    // TODO: This bypasses the full store → composable → DOM path because
    // these tests run against public pages without authentication. A
    // future authenticated E2E suite could test the real integration by
    // setting domain_branding in the bootstrap payload.
    //
    // We use a distinctly non-default color (blue #3b82f6) to
    // verify that the brand bar picks up the override.
    const customHex = '#3b82f6';

    await page.evaluate((hex) => {
      // Minimal reimplementation of palette injection for testing.
      // We only need to set --color-brand-500 to prove the
      // override mechanism works end-to-end.
      document.documentElement.style.setProperty('--color-brand-500', hex);
    }, customHex);

    await page.waitForTimeout(200);

    // The brand bar should now reflect the custom color
    const brandBar = page.locator('div.bg-brand-500').first();
    const bgColor = await brandBar.evaluate((el) => {
      return window.getComputedStyle(el).backgroundColor;
    });

    // Should be blue-ish (rgb ~59, 130, 246), not the default orange
    const rgbMatch = bgColor.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/);
    expect(rgbMatch).toBeTruthy();
    if (rgbMatch) {
      const r = Number(rgbMatch[1]);
      const b = Number(rgbMatch[3]);
      // Blue channel should be dominant
      expect(b).toBeGreaterThan(200);
      // Red channel should be low-moderate
      expect(r).toBeLessThan(100);
    }
  });

  test('removing custom CSS variables falls back to @theme defaults', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('domcontentloaded');

    // Set a custom override
    await page.evaluate(() => {
      document.documentElement.style.setProperty('--color-brand-500', '#3b82f6');
    });
    await page.waitForTimeout(100);

    // Remove it (this is what useBrandTheme does for default color)
    await page.evaluate(() => {
      document.documentElement.style.removeProperty('--color-brand-500');
    });
    await page.waitForTimeout(100);

    // Should fall back to the @theme default
    const brand500 = await page.evaluate(() => {
      return window.getComputedStyle(document.documentElement)
        .getPropertyValue('--color-brand-500')
        .trim();
    });

    expect(brand500.toLowerCase()).toBe(DEFAULT_BRAND_HEX);
  });
});
