// src/tests/stores/identityStore.spec.ts
//
// Precedence contract tests for the primaryColor 3-step fallback chain
// in identityStore's resolvePrimaryColor():
//   1. Per-domain branding (Redis custom domain settings)
//   2. Install config (BRAND_PRIMARY_COLOR via bootstrapStore)
//   3. Neutral last resort (NEUTRAL_BRAND_DEFAULTS.primary_color)

import {
  describe,
  it,
  expect,
  beforeEach,
  vi,
} from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';

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

describe('identityStore primaryColor resolution', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  describe('3-step fallback chain precedence', () => {
    it('uses per-domain color when set (step 1 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: DOMAIN_COLOR },
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(identity.primaryColor.toUpperCase()).toBe(DOMAIN_COLOR.toUpperCase());
    });

    it('falls through to install config when no per-domain color (step 2 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(identity.primaryColor.toUpperCase()).toBe(INSTALL_COLOR.toUpperCase());
    });

    it('falls through to install config when per-domain color is null (step 2 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: null },
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(identity.primaryColor.toUpperCase()).toBe(INSTALL_COLOR.toUpperCase());
    });

    it('falls through to neutral default when neither is set (step 3 wins)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: undefined,
      });

      const identity = useProductIdentity();

      expect(identity.primaryColor.toUpperCase()).toBe(NEUTRAL_HEX.toUpperCase());
    });

    it('falls through to neutral default when per-domain color is invalid hex', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: 'not-a-color' },
        brand_primary_color: undefined,
      });

      const identity = useProductIdentity();

      expect(identity.primaryColor.toUpperCase()).toBe(NEUTRAL_HEX.toUpperCase());
    });

    it('falls through to install config when per-domain color is invalid hex (step 2 catches)', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: { primary_color: 'bad' },
        brand_primary_color: INSTALL_COLOR,
      });

      const identity = useProductIdentity();

      expect(identity.primaryColor.toUpperCase()).toBe(INSTALL_COLOR.toUpperCase());
    });
  });

  describe('brand_primary_color is no longer an orphaned bootstrap field', () => {
    it('bootstrapStore.brand_primary_color is consumed by identityStore', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({
        domain_branding: null,
        brand_primary_color: '#8B5CF6',
      });

      const identity = useProductIdentity();

      expect(identity.primaryColor.toUpperCase()).toBe('#8B5CF6');
    });
  });
});
