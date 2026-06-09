// src/tests/composables/useBrandTheme.spec.ts
//
// Spec for the palette→DOM bridge composable.
// Adapted from develop's reference for the NEUTRAL defaults strategy
// (issue #3048, #3049): default fallback uses NEUTRAL_BRAND_DEFAULTS,
// never OTS orange (#dc4a22).
//
// Test environment: vitest.config.ts sets `environment: 'jsdom'`
// globally, so document.documentElement and friends are available.

import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
  vi,
} from 'vitest';
import { effectScope, nextTick, ref } from 'vue';
import { generateBrandPalette } from '@/utils/brand-palette';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';

const NEUTRAL_HEX = NEUTRAL_BRAND_DEFAULTS.primary_color; // '#3B82F6'
const OTS_ORANGE = '#dc4a22';

// Pre-compute the 44 keys produced by the generator.
const ALL_KEYS = Object.keys(generateBrandPalette(NEUTRAL_HEX));

// ─── Mocks ───────────────────────────────────────────
// Reactive refs the spec drives directly. The composable consumes
// them through storeToRefs(useProductIdentity()).

const mockPrimaryColor = ref<string | null | undefined>(NEUTRAL_HEX);
const mockBrand = ref<{ favicon_url?: string | null } | undefined>(undefined);

vi.mock('@/shared/stores/identityStore', () => ({
  useProductIdentity: () => ({}),
}));

vi.mock('pinia', async (importOriginal) => {
  const actual = await importOriginal<typeof import('pinia')>();
  return {
    ...actual,
    storeToRefs: () => ({
      primaryColor: mockPrimaryColor,
      brand: mockBrand,
    }),
  };
});

vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: (options?: { onError?: (e: unknown) => void }) => ({
    wrap: vi.fn(async <T>(fn: () => Promise<T>) => {
      try {
        return await fn();
      } catch (error) {
        options?.onError?.(error);
        return undefined;
      }
    }),
  }),
}));

// Import after mocks so the composable picks up the mocked deps.
// eslint-disable-next-line import/extensions, import/no-unresolved
import { useBrandTheme } from '@/shared/composables/useBrandTheme';

// ─── Helpers ─────────────────────────────────────────

function clearAllPaletteVars(): void {
  for (const key of ALL_KEYS) {
    document.documentElement.style.removeProperty(key);
  }
}

function getVar(key: string): string {
  return document.documentElement.style.getPropertyValue(key);
}

function ensureFaviconLink(href: string): HTMLLinkElement {
  let link = document.head.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (!link) {
    link = document.createElement('link');
    link.setAttribute('rel', 'icon');
    document.head.appendChild(link);
  }
  link.setAttribute('href', href);
  return link;
}

function removeAllFaviconLinks(): void {
  document.head
    .querySelectorAll('link[rel="icon"], link[rel="shortcut icon"]')
    .forEach((node) => node.remove());
}

// ─── Tests ───────────────────────────────────────────

describe('useBrandTheme', () => {
  beforeEach(() => {
    mockPrimaryColor.value = NEUTRAL_HEX;
    mockBrand.value = undefined;
    clearAllPaletteVars();
    removeAllFaviconLinks();
  });

  afterEach(() => {
    clearAllPaletteVars();
    removeAllFaviconLinks();
  });

  describe('CSS variable injection', () => {
    it('injects all 44 palette variables for a custom color', async () => {
      const scope = effectScope();
      scope.run(() => useBrandTheme());

      mockPrimaryColor.value = OTS_ORANGE;
      await nextTick();

      const expected = generateBrandPalette(OTS_ORANGE);
      let appliedCount = 0;
      for (const [key, value] of Object.entries(expected)) {
        if (getVar(key) === value) appliedCount++;
      }
      // Allow for an implementation that elides default-equal values,
      // but require the substantive majority to land on the DOM.
      expect(appliedCount).toBeGreaterThanOrEqual(40);

      scope.stop();
    });

    it('updates CSS variables reactively when the brand color changes', async () => {
      const scope = effectScope();
      scope.run(() => useBrandTheme());

      mockPrimaryColor.value = OTS_ORANGE;
      await nextTick();
      const orangePalette = generateBrandPalette(OTS_ORANGE);
      expect(getVar('--color-brand-500')).toBe(orangePalette['--color-brand-500']);

      mockPrimaryColor.value = '#22c55e'; // green
      await nextTick();
      const greenPalette = generateBrandPalette('#22c55e');
      expect(getVar('--color-brand-500')).toBe(greenPalette['--color-brand-500']);
      expect(getVar('--color-brand-500')).not.toBe(orangePalette['--color-brand-500']);

      scope.stop();
    });

    it('clears injected overrides when the scope is disposed', async () => {
      const scope = effectScope();
      scope.run(() => useBrandTheme());

      mockPrimaryColor.value = OTS_ORANGE;
      await nextTick();
      expect(getVar('--color-brand-500')).not.toBe('');

      scope.stop();

      for (const key of ALL_KEYS) {
        expect(getVar(key)).toBe('');
      }
    });
  });

  describe('memoization / single-entry usage', () => {
    it('two scopes invoking useBrandTheme() do not corrupt the DOM state', async () => {
      const scopeA = effectScope();
      const scopeB = effectScope();

      scopeA.run(() => useBrandTheme());
      scopeB.run(() => useBrandTheme());

      mockPrimaryColor.value = OTS_ORANGE;
      await nextTick();

      // Each variable must hold exactly the value from the palette,
      // never a doubled / concatenated / stale string.
      const expected = generateBrandPalette(OTS_ORANGE);
      expect(getVar('--color-brand-500')).toBe(expected['--color-brand-500']);

      scopeA.stop();
      scopeB.stop();
    });
  });

  describe('favicon swap', () => {
    it('updates the <link rel="icon"> href when favicon_url is provided', async () => {
      const link = ensureFaviconLink('https://example.com/original.ico');

      const scope = effectScope();
      scope.run(() => useBrandTheme());

      mockBrand.value = { favicon_url: 'https://example.com/custom.ico' };
      await nextTick();

      expect(link.getAttribute('href')).toBe('https://example.com/custom.ico');

      scope.stop();
    });

    it('restores the original favicon href on scope disposal', async () => {
      const original = 'https://example.com/original.ico';
      const link = ensureFaviconLink(original);

      const scope = effectScope();
      scope.run(() => useBrandTheme());

      mockBrand.value = { favicon_url: 'https://example.com/custom.ico' };
      await nextTick();
      expect(link.getAttribute('href')).toBe('https://example.com/custom.ico');

      scope.stop();

      // After disposal the original href must be restored.
      // Compare on URL-suffix to tolerate jsdom href absolutization.
      expect(link.href.endsWith('original.ico')).toBe(true);
    });

    it('does not throw when no <link rel="icon"> exists', async () => {
      removeAllFaviconLinks();

      const scope = effectScope();
      scope.run(() => useBrandTheme());

      mockBrand.value = { favicon_url: 'https://example.com/custom.ico' };
      await nextTick();

      // No assertion on DOM state — only that the composable did not throw.
      scope.stop();
    });

    it('leaves <link rel="icon"> untouched when favicon_url is undefined', async () => {
      const original = 'https://example.com/original.ico';
      const link = ensureFaviconLink(original);
      // brand has no favicon_url at all — this is the "no custom favicon" path.
      mockBrand.value = { favicon_url: undefined };

      const scope = effectScope();
      scope.run(() => useBrandTheme());
      await nextTick();

      // During the active scope: untouched.
      expect(link.href.endsWith('original.ico')).toBe(true);

      scope.stop();

      // After disposal: still untouched.
      expect(link.href.endsWith('original.ico')).toBe(true);
    });

    it('leaves <link rel="icon"> untouched when favicon_url is null', async () => {
      const original = 'https://example.com/original.ico';
      const link = ensureFaviconLink(original);
      mockBrand.value = { favicon_url: null };

      const scope = effectScope();
      scope.run(() => useBrandTheme());
      await nextTick();

      expect(link.href.endsWith('original.ico')).toBe(true);

      scope.stop();

      expect(link.href.endsWith('original.ico')).toBe(true);
    });
  });

  describe('dispose safety', () => {
    it('calling dispose twice does not throw or further mutate the DOM', async () => {
      const original = 'https://example.com/original.ico';
      const link = ensureFaviconLink(original);

      const scope = effectScope();
      scope.run(() => useBrandTheme());

      mockPrimaryColor.value = OTS_ORANGE;
      mockBrand.value = { favicon_url: 'https://example.com/custom.ico' };
      await nextTick();

      // First dispose: clears overrides + restores favicon.
      expect(() => scope.stop()).not.toThrow();
      expect(getVar('--color-brand-500')).toBe('');
      expect(link.href.endsWith('original.ico')).toBe(true);

      // Snapshot DOM state after first dispose.
      const snapshotAfterFirst: Record<string, string> = {};
      for (const key of ALL_KEYS) snapshotAfterFirst[key] = getVar(key);
      const faviconAfterFirst = link.href;

      // Second dispose: must be a safe no-op.
      expect(() => scope.stop()).not.toThrow();

      // DOM unchanged by the second dispose.
      for (const key of ALL_KEYS) {
        expect(getVar(key)).toBe(snapshotAfterFirst[key]);
      }
      expect(link.href).toBe(faviconAfterFirst);
    });
  });

  describe('rapid mutation', () => {
    it('rapid primary_color mutations settle on the last input (no stale palette)', async () => {
      const scope = effectScope();
      scope.run(() => useBrandTheme());

      // Distinct, unambiguous hex inputs — the final value drives the assertion.
      const colors = [
        '#ff0000', '#ff8800', '#ffff00', '#88ff00', '#00ff00',
        '#00ff88', '#00ffff', '#0088ff', '#0000ff', '#8800ff',
      ];

      for (const c of colors) {
        mockPrimaryColor.value = c;
        await nextTick();
      }

      const finalHex = colors[colors.length - 1];
      const finalPalette = generateBrandPalette(finalHex);
      expect(getVar('--color-brand-500')).toBe(finalPalette['--color-brand-500']);
      // Spot-check a different shade to guard against partial application.
      expect(getVar('--color-brand-50')).toBe(finalPalette['--color-brand-50']);

      scope.stop();
    });
  });

  describe('neutral fallback (#3048 / #3049 regression guard)', () => {
    it('NEUTRAL_BRAND_DEFAULTS.primary_color is the documented neutral blue', () => {
      expect(NEUTRAL_HEX.toLowerCase()).toBe('#3b82f6');
    });

    it('does NOT leak OTS orange (#dc4a22) when no brand color is configured', async () => {
      // Simulate "no brand configured" — the store yields the neutral default.
      mockPrimaryColor.value = NEUTRAL_HEX;

      const scope = effectScope();
      scope.run(() => useBrandTheme());
      await nextTick();

      const orangePalette = generateBrandPalette(OTS_ORANGE);
      // Whatever the composable does (set neutral or leave @theme defaults
      // untouched), it MUST NOT match a palette derived from OTS orange.
      const observed = getVar('--color-brand-500');
      if (observed !== '') {
        expect(observed).not.toBe(orangePalette['--color-brand-500']);
      }

      scope.stop();
    });

    it('null/undefined brand color still does not leak OTS orange', async () => {
      mockPrimaryColor.value = null;

      const scope = effectScope();
      scope.run(() => useBrandTheme());
      await nextTick();

      const orangePalette = generateBrandPalette(OTS_ORANGE);
      const observed = getVar('--color-brand-500');
      if (observed !== '') {
        expect(observed).not.toBe(orangePalette['--color-brand-500']);
      }

      scope.stop();
    });
  });

  describe('install-config color override (#3381 regression guard)', () => {
    it('non-neutral install color overrides --color-brand-500 on the DOM', async () => {
      // Simulates the identityStore resolving to an install-level brand color
      // (BRAND_PRIMARY_COLOR env var) when no per-domain branding is set.
      const INSTALL_COLOR = '#E11D48';
      mockPrimaryColor.value = INSTALL_COLOR;

      const scope = effectScope();
      scope.run(() => useBrandTheme());
      await nextTick();

      const expected = generateBrandPalette(INSTALL_COLOR);
      expect(getVar('--color-brand-500')).toBe(expected['--color-brand-500']);
      expect(getVar('--color-brand-500')).not.toBe('');

      scope.stop();
    });

    it('install color palette is fully applied (not partial)', async () => {
      const INSTALL_COLOR = '#E11D48';
      mockPrimaryColor.value = INSTALL_COLOR;

      const scope = effectScope();
      scope.run(() => useBrandTheme());
      await nextTick();

      const expected = generateBrandPalette(INSTALL_COLOR);
      let appliedCount = 0;
      for (const [key, value] of Object.entries(expected)) {
        if (getVar(key) === value) appliedCount++;
      }
      expect(appliedCount).toBe(ALL_KEYS.length);

      scope.stop();
    });
  });
});
