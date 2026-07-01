// src/tests/stores/identityStore.spec.ts
//
// Precedence contract tests for the primaryColor 3-step fallback chain
// in identityStore's resolvePrimaryColor():
//   1. Per-domain branding (Redis custom domain settings)
//   2. Install config (BRAND_PRIMARY_COLOR via bootstrapStore)
//   3. Neutral last resort (NEUTRAL_BRAND_DEFAULTS.primary_color)
//
// These tests pin the resolution order so a partial port or refactor
// cannot silently drop a rung (the class of bug that produced #3381).

import {
  describe,
  it,
  expect,
  beforeEach,
  vi,
} from 'vitest';
import { nextTick } from 'vue';
import { createPinia, setActivePinia } from 'pinia';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const NEUTRAL_HEX = NEUTRAL_BRAND_DEFAULTS.primary_color;
const INSTALL_COLOR = '#E11D48';
const DOMAIN_COLOR = '#22C55E';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapSnapshot: vi.fn(() => null),
  updateBootstrapSnapshot: vi.fn(),
  _resetForTesting: vi.fn(),
}));

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useProductIdentity } from '@/shared/stores/identityStore';

function upperHex(hex: string): string {
  return hex.toUpperCase();
}

describe('identityStore primaryColor resolution', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIAL STATE — tests getInitialState() path
  // ═══════════════════════════════════════════════════════════════════════════

  describe('3-step fallback chain (initial state)', () => {
    it('uses per-domain color when set (step 1 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: DOMAIN_COLOR },
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(DOMAIN_COLOR));
    });

    it('falls through to install config when no per-domain color (step 2 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(INSTALL_COLOR));
    });

    it('falls through to install config when per-domain color is null (step 2 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: null },
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(INSTALL_COLOR));
    });

    it('falls through to neutral default when neither is set (step 3 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: undefined,
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(NEUTRAL_HEX));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // WATCHER PATH — tests domain_branding watcher
  // ═══════════════════════════════════════════════════════════════════════════

  describe('3-step fallback chain (reactive watcher)', () => {
    it('domain color arriving via watcher overrides install config', async () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();
      expect(upperHex(identity.primaryColor)).toBe(upperHex(INSTALL_COLOR));

      bootstrap.$patch({ domain_branding: { primary_color: DOMAIN_COLOR } });
      await nextTick();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(DOMAIN_COLOR));
    });

    it('clearing domain color via watcher falls back to install config', async () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: DOMAIN_COLOR },
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();
      expect(upperHex(identity.primaryColor)).toBe(upperHex(DOMAIN_COLOR));

      bootstrap.$patch({ domain_branding: null });
      await nextTick();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(INSTALL_COLOR));
    });

    it('clearing domain color with no install config falls to neutral', async () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: DOMAIN_COLOR },
        brand_primary_color: undefined,
      });

      const identity = useProductIdentity();
      expect(upperHex(identity.primaryColor)).toBe(upperHex(DOMAIN_COLOR));

      bootstrap.$patch({ domain_branding: null });
      await nextTick();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(NEUTRAL_HEX));
    });

    it('install config changing independently of domain_branding updates primaryColor', async () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();
      expect(upperHex(identity.primaryColor)).toBe(upperHex(INSTALL_COLOR));

      const NEW_INSTALL = '#8B5CF6';
      bootstrap.$patch({ brand_primary_color: NEW_INSTALL });
      await nextTick();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(NEW_INSTALL));
    });

    it('install config removed independently falls to neutral', async () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();
      expect(upperHex(identity.primaryColor)).toBe(upperHex(INSTALL_COLOR));

      bootstrap.$patch({ brand_primary_color: undefined });
      await nextTick();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(NEUTRAL_HEX));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // VALIDATION — malformed inputs degrade gracefully
  // ═══════════════════════════════════════════════════════════════════════════

  describe('graceful degradation for invalid inputs', () => {
    it('invalid per-domain hex falls through to install config', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: 'not-a-color' },
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(INSTALL_COLOR));
    });

    it('invalid per-domain hex with no install config falls to neutral', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: 'bad' },
        brand_primary_color: undefined,
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(NEUTRAL_HEX));
    });

    it('invalid install config hex falls through to neutral', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: 'rgb(255,0,0)',
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(NEUTRAL_HEX));
    });

    it('both inputs invalid falls through to neutral', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: 'garbage' },
        brand_primary_color: 'also-garbage',
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe(upperHex(NEUTRAL_HEX));
    });

    it('3-digit hex is normalized to 6-digit', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: '#F00',
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe('#FF0000');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ORPHAN GUARD — brand_primary_color has a live consumer
  // ═══════════════════════════════════════════════════════════════════════════

  describe('brand_primary_color is no longer an orphaned bootstrap field', () => {
    it('bootstrapStore.brand_primary_color is consumed by identityStore', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: '#8B5CF6',
      });

      const identity = useProductIdentity();

      expect(upperHex(identity.primaryColor)).toBe('#8B5CF6');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CROSS-SOURCE CONSTANT EQUALITY
  //
  // The neutral brand color (#3B82F6) is defined in four places:
  //   - TS:   NEUTRAL_BRAND_DEFAULTS.primary_color  (brand.ts)
  //   - Ruby: BrandSettings::DEFAULTS[:primary_color] (brand_settings.rb)
  //   - CSS:  @theme { --color-brand-500 }           (style.css)
  //   - ENV:  .env.reference BRAND_PRIMARY_COLOR      (.env.reference)
  //
  // If any of these drift, the sentinel-value collision described in #3381
  // makes the boundary between "unset" and "explicitly neutral" unobservable.
  // ═══════════════════════════════════════════════════════════════════════════

  describe('cross-source neutral color constant', () => {
    const CANONICAL = NEUTRAL_BRAND_DEFAULTS.primary_color.toUpperCase();

    it('TS NEUTRAL_BRAND_DEFAULTS.primary_color is #3B82F6', () => {
      expect(CANONICAL).toBe('#3B82F6');
    });

    it('Ruby BrandSettings::DEFAULTS[:primary_color] matches TS constant', () => {
      const ruby = readFileSync(
        resolve(process.cwd(), 'lib/onetime/models/custom_domain/brand_settings.rb'),
        'utf-8',
      );
      // Match primary_color inside the DEFAULTS hash, not in comments or examples
      const defaultsBlock = ruby.match(/DEFAULTS\s*=\s*\{([^}]+)\}/s);
      expect(defaultsBlock).not.toBeNull();
      const colorMatch = defaultsBlock![1].match(/primary_color:\s*'(#[0-9A-Fa-f]{6})'/);
      expect(colorMatch).not.toBeNull();
      expect(colorMatch![1].toUpperCase()).toBe(CANONICAL);
    });

    it('.env.reference BRAND_PRIMARY_COLOR example matches TS constant', () => {
      const env = readFileSync(
        resolve(process.cwd(), '.env.reference'),
        'utf-8',
      );
      const match = env.match(/BRAND_PRIMARY_COLOR='(#[0-9A-Fa-f]{6})'/);
      expect(match).not.toBeNull();
      expect(match![1].toUpperCase()).toBe(CANONICAL);
    });

    it('CSS @theme --color-brand-500 seed matches TS constant', () => {
      const css = readFileSync(
        resolve(process.cwd(), 'src/assets/style.css'),
        'utf-8',
      );
      const match = css.match(/--color-brand-500:\s*(#[0-9A-Fa-f]{6})/);
      expect(match).not.toBeNull();
      expect(match![1].toUpperCase()).toBe(CANONICAL);
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// productName — neutral-safe install product name (A1 consolidation)
//
// The store is the single source of truth for the product-name fallback that
// MastHead and DefaultLogo previously re-derived by hand. It must degrade to
// the neutral default ('My App'), never a hardcoded "Onetime Secret", and must
// treat an empty string as unset (|| not ??).
// ═══════════════════════════════════════════════════════════════════════════

describe('identityStore productName resolution', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('uses brand_product_name when set', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ brand_product_name: 'Acme Vault' });

    const identity = useProductIdentity();

    expect(identity.productName).toBe('Acme Vault');
  });

  it('falls back to the neutral default when undefined', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ brand_product_name: undefined });

    const identity = useProductIdentity();

    expect(identity.productName).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
    expect(identity.productName).not.toBe('Onetime Secret');
  });

  it('falls back to the neutral default when null', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ brand_product_name: null });

    const identity = useProductIdentity();

    expect(identity.productName).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
  });

  it('treats an empty string as unset and falls back to the neutral default', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ brand_product_name: '' });

    const identity = useProductIdentity();

    // `||` (not `??`) — a blank product-name config degrades to 'My App'
    // rather than rendering an empty name.
    expect(identity.productName).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
  });

  it('reacts to brand_product_name changes', async () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ brand_product_name: undefined });

    const identity = useProductIdentity();
    expect(identity.productName).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);

    bootstrap.$patch({ brand_product_name: 'Acme Vault' });
    await nextTick();

    expect(identity.productName).toBe('Acme Vault');
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// showPlatformIdentity — base "may we show the platform wordmark?" guard (A3)
//
// False on any custom domain and whenever a per-tenant logo is present, so a
// consumer can suppress the platform name/wordmark without re-deriving the
// leak rule. Canonical + subdomain contexts return true (subject to the
// consumer's own config).
// ═══════════════════════════════════════════════════════════════════════════

describe('identityStore showPlatformIdentity', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('is true on the canonical domain with no logo', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ domain_strategy: 'canonical', domain_logo: null });

    const identity = useProductIdentity();

    expect(identity.showPlatformIdentity).toBe(true);
  });

  it('is true on a subdomain (the subdomain IS the platform)', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ domain_strategy: 'subdomain', domain_logo: null });

    const identity = useProductIdentity();

    expect(identity.showPlatformIdentity).toBe(true);
  });

  it('is false on a custom domain with no uploaded logo (A3 leak guard)', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ domain_strategy: 'custom', domain_logo: null });

    const identity = useProductIdentity();

    expect(identity.showPlatformIdentity).toBe(false);
  });

  it('is false on a custom domain that has an uploaded logo', () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({
      domain_strategy: 'custom',
      domain_logo: 'https://cdn.example.com/acme.png',
    });

    const identity = useProductIdentity();

    expect(identity.showPlatformIdentity).toBe(false);
  });

  it('is false whenever a per-tenant logo is present, independent of strategy', () => {
    // Defensive: a logo implies a tenant surface — never show the platform name
    // beside it even if the strategy field says otherwise.
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({
      domain_strategy: 'canonical',
      domain_logo: 'https://cdn.example.com/acme.png',
    });

    const identity = useProductIdentity();

    expect(identity.showPlatformIdentity).toBe(false);
  });

  it('reacts to domain_strategy changing to custom', async () => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ domain_strategy: 'canonical', domain_logo: null });

    const identity = useProductIdentity();
    expect(identity.showPlatformIdentity).toBe(true);

    bootstrap.$patch({ domain_strategy: 'custom' });
    await nextTick();

    expect(identity.showPlatformIdentity).toBe(false);
  });
});
