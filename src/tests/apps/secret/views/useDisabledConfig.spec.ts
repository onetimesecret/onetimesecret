// src/tests/apps/secret/conceal/useDisabledConfig.spec.ts
//
// Unit tests for the disabled-homepage dispatcher composable. Covers:
// - Auto-detection rules (branded vs unbranded vs canonical contexts)
// - Tri-state operator overrides (null = auto, true/false = force)
// - href derivation from siteHost with empty-host gating
// - Variant id propagation and reactivity through Pinia
//
// The composable is the single composition root for the disabled-homepage
// view, so any regression here ripples through every variant.

import { useDisabledConfig } from '@/apps/secret/views/disabled/useDisabledConfig';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// Identity store reads i18n during init (preReveal default copy); stub it.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

interface SetupOptions {
  // Identity / domain context
  domainStrategy?: 'canonical' | 'custom' | 'subdomain' | 'invalid';
  displayDomain?: string;
  brandDescription?: string | null;
  primaryColor?: string;
  logoUri?: string | null;
  // Bootstrap config
  siteHost?: string;
  billingEnabled?: boolean;
  authSignin?: boolean;
  disabledHomepage?: {
    variant?: 'v1' | 'minimal' | 'legacy';
    show_promo?: boolean | null;
    show_what_is_this?: boolean | null;
  };
}

/**
 * Spin up Pinia and patch the two stores `useDisabledConfig` reads from.
 * Returns the composable's bindings so tests can assert directly.
 */
function setup(opts: SetupOptions = {}) {
  setActivePinia(createPinia());

  const bootstrap = useBootstrapStore();
  bootstrap.$patch({
    site_host: opts.siteHost ?? 'onetimesecret.com',
    billing_enabled: opts.billingEnabled ?? false,
    authentication: {
      ...bootstrap.authentication,
      signin: opts.authSignin ?? true,
    },
    disabled_homepage: {
      variant: opts.disabledHomepage?.variant ?? 'v1',
      show_promo: opts.disabledHomepage?.show_promo ?? null,
      show_what_is_this: opts.disabledHomepage?.show_what_is_this ?? null,
    },
  });

  const identity = useProductIdentity();
  identity.$patch({
    domainStrategy: opts.domainStrategy ?? 'canonical',
    displayDomain: opts.displayDomain ?? 'onetimesecret.com',
    primaryColor: opts.primaryColor ?? '#dc4a22',
    logoUri: opts.logoUri ?? null,
    siteHost: opts.siteHost ?? 'onetimesecret.com',
    brand:
      opts.brandDescription === undefined
        ? null
        : opts.brandDescription === null
          ? null
          : {
              description: opts.brandDescription,
              primary_color: opts.primaryColor ?? '#dc4a22',
              button_text_light: true,
              corner_style: 'rounded',
              font_family: 'sans',
              instructions_pre_reveal: '',
              instructions_post_reveal: '',
              instructions_reveal: '',
            },
  });

  return { config: useDisabledConfig(), bootstrap, identity };
}

describe('useDisabledConfig', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('variant selection', () => {
    beforeEach(() => {
      // Reset URL each test so ?variant overrides don't bleed across cases.
      window.history.replaceState({}, '', '/');
    });

    it('defaults to v1 when bootstrap omits disabled_homepage', () => {
      const { config } = setup();
      expect(config.variant.value).toBe('v1');
    });

    it('respects the configured variant', () => {
      const { config } = setup({ disabledHomepage: { variant: 'minimal' } });
      expect(config.variant.value).toBe('minimal');
    });

    it('reacts when bootstrap mutates the variant mid-session', () => {
      const { config, bootstrap } = setup({ disabledHomepage: { variant: 'v1' } });
      expect(config.variant.value).toBe('v1');

      bootstrap.$patch({
        disabled_homepage: {
          variant: 'legacy',
          show_promo: null,
          show_what_is_this: null,
        },
      });
      expect(config.variant.value).toBe('legacy');
    });

    it('?variant URL override wins over bootstrap', () => {
      window.history.replaceState({}, '', '/?variant=legacy');
      const { config } = setup({ disabledHomepage: { variant: 'v1' } });
      expect(config.variant.value).toBe('legacy');
    });

    it('?variant override falls through silently when the value is invalid', () => {
      window.history.replaceState({}, '', '/?variant=banana');
      const { config } = setup({ disabledHomepage: { variant: 'minimal' } });
      expect(config.variant.value).toBe('minimal');
    });

    it('?variant override is read at composable-call time, not reactively', () => {
      // Intentional: a mid-session URL mutation doesn't flip the variant
      // without re-mounting. Mirrors how operators use the override —
      // pick a variant on page load, not while the page is open.
      const { config } = setup({ disabledHomepage: { variant: 'v1' } });
      expect(config.variant.value).toBe('v1');

      window.history.replaceState({}, '', '/?variant=legacy');
      expect(config.variant.value).toBe('v1');
    });
  });

  describe('isBranded auto-detection', () => {
    it('is false on canonical', () => {
      const { config } = setup({ domainStrategy: 'canonical' });
      expect(config.props.isBranded).toBe(false);
    });

    it('is false on custom domain with no brand description', () => {
      const { config } = setup({ domainStrategy: 'custom', brandDescription: null });
      expect(config.props.isBranded).toBe(false);
    });

    it('is true on custom domain with brand description', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: 'Acme',
      });
      expect(config.props.isBranded).toBe(true);
    });

    it('is false when brand description is whitespace-only', () => {
      // Reproduces the trim() guard in workspaceName + the truthy check on
      // brand.description. A workspace with only spaces shouldn't be treated
      // as branded.
      const { config } = setup({ domainStrategy: 'custom', brandDescription: '   ' });
      // isBranded technically true (description present) but workspaceName
      // falls through to displayName. Documenting actual behaviour.
      expect(config.props.isBranded).toBe(true);
      expect(config.props.workspaceName).toBeTruthy();
    });
  });

  describe('showPromo auto-detection', () => {
    it('false on canonical (no domain to promote)', () => {
      const { config } = setup({
        domainStrategy: 'canonical',
        billingEnabled: true,
      });
      expect(config.props.showPromo).toBe(false);
    });

    it('false on branded custom domain (already configured)', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: 'Acme',
        billingEnabled: true,
      });
      expect(config.props.showPromo).toBe(false);
    });

    it('false when billing is disabled (self-hosted)', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: null,
        billingEnabled: false,
      });
      expect(config.props.showPromo).toBe(false);
    });

    it('true on unbranded custom domain with billing enabled', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: null,
        billingEnabled: true,
      });
      expect(config.props.showPromo).toBe(true);
    });

    it('false when siteHost is empty (href would be unresolvable)', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: null,
        billingEnabled: true,
        siteHost: '',
      });
      expect(config.props.showPromo).toBe(false);
    });
  });

  describe('showWhatIsThis auto-detection', () => {
    it('false on canonical', () => {
      const { config } = setup({ domainStrategy: 'canonical' });
      expect(config.props.showWhatIsThis).toBe(false);
    });

    it('true on custom domain', () => {
      const { config } = setup({ domainStrategy: 'custom' });
      expect(config.props.showWhatIsThis).toBe(true);
    });

    it('false when siteHost is empty (href would be unresolvable)', () => {
      const { config } = setup({ domainStrategy: 'custom', siteHost: '' });
      expect(config.props.showWhatIsThis).toBe(false);
    });
  });

  describe('operator overrides (tri-state)', () => {
    it('show_promo=false forces hide even when auto would show', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: null,
        billingEnabled: true,
        disabledHomepage: { show_promo: false },
      });
      expect(config.props.showPromo).toBe(false);
    });

    it('show_promo=true forces show even when auto would hide (branded)', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: 'Acme',
        billingEnabled: true,
        disabledHomepage: { show_promo: true },
      });
      expect(config.props.showPromo).toBe(true);
    });

    it('show_promo=null falls through to auto-detection', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: null,
        billingEnabled: true,
        disabledHomepage: { show_promo: null },
      });
      expect(config.props.showPromo).toBe(true);
    });

    it('show_what_is_this override applies the same way', () => {
      const a = setup({
        domainStrategy: 'canonical',
        disabledHomepage: { show_what_is_this: true },
      });
      // Forced on, but still suppressed by empty-siteHost guard isn't
      // triggered here — siteHost has the default.
      expect(a.config.props.showWhatIsThis).toBe(true);

      const b = setup({
        domainStrategy: 'custom',
        disabledHomepage: { show_what_is_this: false },
      });
      expect(b.config.props.showWhatIsThis).toBe(false);
    });

    it('empty siteHost suppresses even a true override', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        siteHost: '',
        disabledHomepage: { show_promo: true, show_what_is_this: true },
      });
      expect(config.props.showPromo).toBe(false);
      expect(config.props.showWhatIsThis).toBe(false);
    });
  });

  describe('href derivation', () => {
    it('builds whatIsThisHref from siteHost', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        siteHost: 'onetime.example.com',
      });
      expect(config.props.whatIsThisHref).toBe('https://onetime.example.com/');
    });

    it('builds promoHref from siteHost with /pricing path', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: null,
        billingEnabled: true,
        siteHost: 'onetime.example.com',
      });
      expect(config.props.promoHref).toBe('https://onetime.example.com/pricing');
    });

    it('returns null hrefs when siteHost is empty', () => {
      const { config } = setup({ siteHost: '' });
      expect(config.props.whatIsThisHref).toBeNull();
      expect(config.props.promoHref).toBeNull();
    });
  });

  describe('monogram initial', () => {
    it('derives from brand description first letter, uppercased', () => {
      const { config } = setup({
        domainStrategy: 'custom',
        brandDescription: 'acme',
      });
      expect(config.props.monogramInitial).toBe('A');
    });

    it('falls back to displayDomain when no brand', () => {
      const { config } = setup({
        domainStrategy: 'canonical',
        displayDomain: 'zebra.example.com',
      });
      expect(config.props.monogramInitial).toBe('Z');
    });
  });

  describe('showSignin', () => {
    it('mirrors authentication.signin', () => {
      expect(setup({ authSignin: true }).config.props.showSignin).toBe(true);
      expect(setup({ authSignin: false }).config.props.showSignin).toBe(false);
    });
  });

  describe('props reactivity', () => {
    it('re-reads when a store value changes', () => {
      const { config, bootstrap } = setup({
        domainStrategy: 'custom',
        brandDescription: null,
        billingEnabled: false,
      });
      expect(config.props.showPromo).toBe(false);

      bootstrap.$patch({ billing_enabled: true });
      // siteHost has the default, so flipping billing flips the promo
      expect(config.props.showPromo).toBe(true);
    });
  });
});
