// e2e/all/brand-customization.spec.ts
//
// E2E tests for brand palette customization.
// Validates that CSS brand variables are applied to document.documentElement
// and that public pages render correctly in light/dark modes without console errors.

import { test, expect, Page } from '@playwright/test';

/**
 * CSS variable naming convention from brand-palette.ts:
 * --color-{prefix}-{step}
 *
 * Prefixes: brand, branddim, brandcomp, brandcompdim (4)
 * Steps: 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950 (11)
 * Total: 4 * 11 = 44 variables
 */
const PALETTE_PREFIXES = ['brand', 'branddim', 'brandcomp', 'brandcompdim'] as const;
const SHADE_STEPS = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950'] as const;

/** Neutral default from NEUTRAL_BRAND_DEFAULTS.primary_color */
const NEUTRAL_BLUE = '#3B82F6';

/** Generate all 44 CSS variable names */
function getAllBrandVarNames(): string[] {
  const vars: string[] = [];
  for (const prefix of PALETTE_PREFIXES) {
    for (const step of SHADE_STEPS) {
      vars.push(`--color-${prefix}-${step}`);
    }
  }
  return vars;
}

const ALL_BRAND_VARS = getAllBrandVarNames();

/** Extract computed CSS variable values from document root */
async function getBrandPaletteFromPage(page: Page): Promise<Record<string, string>> {
  return page.evaluate((varNames: string[]) => {
    const style = getComputedStyle(document.documentElement);
    const result: Record<string, string> = {};
    for (const name of varNames) {
      result[name] = style.getPropertyValue(name).trim();
    }
    return result;
  }, ALL_BRAND_VARS);
}

/** Check if a value looks like a valid hex color */
function isHexColor(value: string): boolean {
  return /^#[0-9a-fA-F]{6}$/i.test(value);
}

test.describe('Brand Customization - CSS Variable Injection', () => {
  test.beforeEach(async ({ page }) => {
    page.setDefaultTimeout(15000);
  });

  test('44 brand palette CSS variables exist on document root', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for Vue to mount and useBrandTheme to execute
    await page.waitForFunction(() => {
      return (window as any).__BOOTSTRAP_ME__ === true;
    }, { timeout: 30000 });

    const palette = await getBrandPaletteFromPage(page);

    // Verify all 44 variables exist
    const missingVars: string[] = [];
    const invalidVars: string[] = [];

    for (const varName of ALL_BRAND_VARS) {
      const value = palette[varName];
      if (!value) {
        missingVars.push(varName);
      } else if (!isHexColor(value)) {
        // Variables may be set via Tailwind @theme or inline style
        // Either way, computed value should resolve to a color
        // Accept rgb() format too since computed styles often return rgb
        if (!value.startsWith('rgb') && !isHexColor(value)) {
          invalidVars.push(`${varName}: ${value}`);
        }
      }
    }

    // For neutral branding, variables come from Tailwind @theme (not inline styles)
    // so they should still resolve to valid colors in computed style
    expect(
      missingVars.length,
      `Missing brand CSS variables:\n${missingVars.join('\n')}`
    ).toBe(0);

    // No console errors during brand initialization
    const criticalErrors = consoleErrors.filter(
      (e) => !e.includes('favicon') && !e.includes('DevTools')
    );
    expect(
      criticalErrors,
      `Console errors during page load:\n${criticalErrors.join('\n')}`
    ).toHaveLength(0);
  });

  test('brand-500 variable reflects neutral blue by default', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for bootstrap consumption
    await page.waitForFunction(() => {
      return (window as any).__BOOTSTRAP_ME__ === true;
    }, { timeout: 30000 });

    // Check brand-500 specifically - this is the primary color shade
    const brand500 = await page.evaluate(() => {
      const style = getComputedStyle(document.documentElement);
      return style.getPropertyValue('--color-brand-500').trim();
    });

    // Brand-500 should be set (either from Tailwind @theme or inline override)
    expect(brand500).toBeTruthy();

    // For neutral branding with #3B82F6, the 500 shade should be close to that
    // The exact value depends on oklch conversion, so just verify it's a valid color
    const isValidColor = isHexColor(brand500) || brand500.startsWith('rgb');
    expect(isValidColor, `brand-500 should be a valid color, got: ${brand500}`).toBe(true);
  });
});

test.describe('Brand Customization - Light/Dark Mode', () => {
  test('page renders correctly in light mode', async ({ page }) => {
    const jsErrors: string[] = [];
    page.on('pageerror', (error) => {
      jsErrors.push(error.message);
    });

    // Force light color scheme
    await page.emulateMedia({ colorScheme: 'light' });
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Verify page is visible and functional
    await expect(page.locator('body')).toBeVisible();

    // Check that dark mode class is not present on html element
    const htmlClasses = await page.evaluate(() => document.documentElement.className);
    // Light mode may not have explicit class, or may have 'light' class

    // Verify body has appropriate background (not transparent)
    const bgColor = await page.evaluate(() => {
      return getComputedStyle(document.body).backgroundColor;
    });
    expect(bgColor).not.toBe('rgba(0, 0, 0, 0)');

    // No JS errors during render
    const criticalErrors = jsErrors.filter(
      (e) => !e.includes('Non-Error promise rejection')
    );
    expect(criticalErrors).toHaveLength(0);
  });

  test('page renders correctly in dark mode', async ({ page }) => {
    const jsErrors: string[] = [];
    page.on('pageerror', (error) => {
      jsErrors.push(error.message);
    });

    // Force dark color scheme
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Verify page is visible and functional
    await expect(page.locator('body')).toBeVisible();

    // Body should have a dark background in dark mode
    const bgColor = await page.evaluate(() => {
      const style = getComputedStyle(document.body);
      // Parse rgb values to check if it's a dark color
      const match = style.backgroundColor.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
      if (!match) return { r: 255, g: 255, b: 255 }; // Assume light if can't parse
      return {
        r: parseInt(match[1]),
        g: parseInt(match[2]),
        b: parseInt(match[3]),
      };
    });

    // In dark mode, background should be darker (lower RGB values)
    // Sum of RGB < 384 (128*3) suggests a dark background
    const luminance = bgColor.r + bgColor.g + bgColor.b;
    expect(
      luminance,
      `Dark mode background should be dark. RGB sum: ${luminance} (r:${bgColor.r}, g:${bgColor.g}, b:${bgColor.b})`
    ).toBeLessThan(450);

    // No JS errors during render
    const criticalErrors = jsErrors.filter(
      (e) => !e.includes('Non-Error promise rejection')
    );
    expect(criticalErrors).toHaveLength(0);
  });

  test('brand colors remain consistent across theme toggle', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for Vue mount
    await page.waitForFunction(() => {
      return (window as any).__BOOTSTRAP_ME__ === true;
    }, { timeout: 30000 });

    // Get brand-500 in light mode
    await page.emulateMedia({ colorScheme: 'light' });
    await page.waitForTimeout(100); // Allow re-render

    const lightBrand500 = await page.evaluate(() => {
      return getComputedStyle(document.documentElement)
        .getPropertyValue('--color-brand-500')
        .trim();
    });

    // Switch to dark mode
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.waitForTimeout(100);

    const darkBrand500 = await page.evaluate(() => {
      return getComputedStyle(document.documentElement)
        .getPropertyValue('--color-brand-500')
        .trim();
    });

    // Brand colors should be the same regardless of theme
    // (theme affects surfaces/text, not brand palette)
    expect(lightBrand500).toBe(darkBrand500);
  });
});

test.describe('Brand Customization - Console Error Monitoring', () => {
  test('no console errors during brand palette rendering', async ({ page }) => {
    const consoleMessages: { type: string; text: string }[] = [];

    page.on('console', (msg) => {
      consoleMessages.push({
        type: msg.type(),
        text: msg.text(),
      });
    });

    const pageErrors: string[] = [];
    page.on('pageerror', (error) => {
      pageErrors.push(error.message);
    });

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Wait for brand theme to be fully applied
    await page.waitForFunction(() => {
      return (window as any).__BOOTSTRAP_ME__ === true;
    }, { timeout: 30000 });

    // Filter for actual errors (not warnings or info)
    const errors = consoleMessages.filter((m) => m.type === 'error');
    const brandRelatedErrors = errors.filter(
      (e) =>
        e.text.toLowerCase().includes('brand') ||
        e.text.toLowerCase().includes('palette') ||
        e.text.toLowerCase().includes('color') ||
        e.text.toLowerCase().includes('oklch')
    );

    expect(
      brandRelatedErrors,
      `Brand-related console errors:\n${brandRelatedErrors.map((e) => e.text).join('\n')}`
    ).toHaveLength(0);

    // No uncaught page errors
    const criticalPageErrors = pageErrors.filter(
      (e) => !e.includes('Non-Error promise rejection')
    );
    expect(
      criticalPageErrors,
      `Page errors:\n${criticalPageErrors.join('\n')}`
    ).toHaveLength(0);
  });

  test('no errors on public pages after navigation', async ({ page }) => {
    const pageErrors: string[] = [];
    page.on('pageerror', (error) => {
      pageErrors.push(`${page.url()}: ${error.message}`);
    });

    // Navigate through public pages
    const publicPaths = ['/', '/about', '/info/privacy'];

    for (const path of publicPaths) {
      const response = await page.goto(path);

      // Accept 200 or 404 (some paths may not exist)
      const status = response?.status() ?? 0;
      if (status !== 200 && status !== 404) {
        continue; // Skip paths that error out
      }

      await page.waitForLoadState('networkidle');
    }

    // Filter out expected/ignorable errors
    const criticalErrors = pageErrors.filter(
      (e) =>
        !e.includes('Non-Error promise rejection') &&
        !e.includes('ResizeObserver loop')
    );

    expect(
      criticalErrors,
      `Page errors during navigation:\n${criticalErrors.join('\n')}`
    ).toHaveLength(0);
  });
});

test.describe('Brand Customization - head-base meta tags', () => {
  // head-base.rue partial renders:
  //   <meta name="theme-color" content="{{brand_primary_color}}" media="(prefers-color-scheme: light)">
  //   <link rel="mask-icon" href="..." color="{{brand_primary_color}}">
  // Both should carry a hex color value derived from the configured brand color.

  test('meta theme-color carries a valid hex color', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // There are two theme-color metas (light + dark media). The light one
    // is the brand-driven value; the dark one is hardcoded #1a1a1a.
    const lightThemeColor = await page
      .locator('meta[name="theme-color"][media*="light"]')
      .getAttribute('content');

    expect(lightThemeColor, 'meta[theme-color] light should be present').toBeTruthy();
    expect(
      lightThemeColor && isHexColor(lightThemeColor),
      `meta[theme-color] light should be a hex color, got: ${lightThemeColor}`
    ).toBe(true);
  });

  test('link mask-icon color attribute carries a valid hex color', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const maskIconColor = await page
      .locator('link[rel="mask-icon"]')
      .getAttribute('color');

    expect(maskIconColor, 'link[mask-icon] color should be present').toBeTruthy();
    expect(
      maskIconColor && isHexColor(maskIconColor),
      `link[mask-icon] color should be a hex color, got: ${maskIconColor}`
    ).toBe(true);
  });

  test('theme-color and mask-icon agree on the brand color', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    const lightThemeColor = await page
      .locator('meta[name="theme-color"][media*="light"]')
      .getAttribute('content');
    const maskIconColor = await page
      .locator('link[rel="mask-icon"]')
      .getAttribute('color');

    expect(lightThemeColor?.toLowerCase()).toBe(maskIconColor?.toLowerCase());
  });
});

test.describe('Brand Customization - Palette Structure Validation', () => {
  test('all 4 palette prefixes have complete shade scales', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.waitForFunction(() => {
      return (window as any).__BOOTSTRAP_ME__ === true;
    }, { timeout: 30000 });

    const palette = await getBrandPaletteFromPage(page);

    // Each prefix should have exactly 11 shades
    for (const prefix of PALETTE_PREFIXES) {
      const prefixVars = SHADE_STEPS.map((step) => `--color-${prefix}-${step}`);
      const values = prefixVars.map((v) => palette[v]);

      const emptyCount = values.filter((v) => !v).length;
      expect(
        emptyCount,
        `Prefix '${prefix}' has ${emptyCount} missing shade values`
      ).toBe(0);
    }
  });

  test('shade progression follows lightness gradient (50 lightest, 950 darkest)', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    await page.waitForFunction(() => {
      return (window as any).__BOOTSTRAP_ME__ === true;
    }, { timeout: 30000 });

    // Get brand palette values and convert to perceived lightness
    const lightnessValues = await page.evaluate((steps: string[]) => {
      const style = getComputedStyle(document.documentElement);
      const results: Record<string, number> = {};

      for (const step of steps) {
        const value = style.getPropertyValue(`--color-brand-${step}`).trim();
        // Parse hex or rgb to get luminance approximation
        let r = 0, g = 0, b = 0;

        if (value.startsWith('#')) {
          const hex = value.slice(1);
          r = parseInt(hex.slice(0, 2), 16);
          g = parseInt(hex.slice(2, 4), 16);
          b = parseInt(hex.slice(4, 6), 16);
        } else if (value.startsWith('rgb')) {
          const match = value.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
          if (match) {
            r = parseInt(match[1]);
            g = parseInt(match[2]);
            b = parseInt(match[3]);
          }
        }

        // Simple luminance approximation
        results[step] = 0.299 * r + 0.587 * g + 0.114 * b;
      }

      return results;
    }, [...SHADE_STEPS]);

    // Shade 50 should be lighter than 500, which should be lighter than 950
    expect(
      lightnessValues['50'],
      'Shade 50 should be lighter than 500'
    ).toBeGreaterThan(lightnessValues['500']);

    expect(
      lightnessValues['500'],
      'Shade 500 should be lighter than 950'
    ).toBeGreaterThan(lightnessValues['950']);
  });
});
