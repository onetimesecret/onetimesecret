// src/tests/apps/secret/composables/useSecretContext.spec.ts

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref, nextTick } from 'vue';
import { setActivePinia } from 'pinia';
import { createTestingPinia } from '@pinia/testing';
import { useSecretContext } from '@/shared/composables/useSecretContext';
import type { ClientAuthStatus } from '@/schemas/contracts/bootstrap';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useProductIdentity } from '@/shared/stores/identityStore';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

// Default bootstrap state for tests
const defaultBootstrapState = {
  domain_strategy: 'canonical',
  domains_enabled: false,
  display_domain: 'onetime.dev',
  site_host: 'https://onetime.dev',
  canonical_domain: 'onetime.dev',
  domain_id: '',
  domain_branding: {},
};

/**
 * Authentication has one source (#4458): the bootstrap store's status, from
 * which authStore's accessors derive. Actions are stubbed under this testing
 * pinia, so the status (plain state) is set directly.
 */
function setAuthStatus(status: ClientAuthStatus): void {
  useBootstrapStore().authStatus = status;
}

describe('useSecretContext', () => {
  beforeEach(() => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      initialState: {
        bootstrap: defaultBootstrapState,
      },
    });
    setActivePinia(pinia);
  });

  describe('Actor Role Computation', () => {
    it('returns CREATOR when isOwner is true', () => {
      setAuthStatus('authenticated');

      const { actorRole } = useSecretContext({ isOwner: true });

      expect(actorRole.value).toBe('CREATOR');
    });

    it('returns RECIPIENT_AUTH when authenticated but not owner', () => {
      setAuthStatus('authenticated');

      const { actorRole } = useSecretContext({ isOwner: false });

      expect(actorRole.value).toBe('RECIPIENT_AUTH');
    });

    it('returns RECIPIENT_ANON when not authenticated', () => {
      setAuthStatus('anonymous');

      const { actorRole } = useSecretContext({ isOwner: false });

      expect(actorRole.value).toBe('RECIPIENT_ANON');
    });

    it('defaults to RECIPIENT_ANON when no isOwner option provided', () => {
      setAuthStatus('anonymous');

      const { actorRole } = useSecretContext();

      expect(actorRole.value).toBe('RECIPIENT_ANON');
    });

    it('accepts reactive isOwner ref', () => {
      setAuthStatus('authenticated');

      const isOwnerRef = ref(false);
      const { actorRole } = useSecretContext({ isOwner: isOwnerRef });

      expect(actorRole.value).toBe('RECIPIENT_AUTH');

      isOwnerRef.value = true;
      expect(actorRole.value).toBe('CREATOR');
    });

    it('accepts isOwner getter function', async () => {
      setAuthStatus('authenticated');

      const ownerRef = ref(false);
      const { actorRole } = useSecretContext({ isOwner: () => ownerRef.value });

      expect(actorRole.value).toBe('RECIPIENT_AUTH');

      ownerRef.value = true;
      await nextTick();
      expect(actorRole.value).toBe('CREATOR');
    });
  });

  describe('UI Config for CREATOR', () => {
    it('shows burn control for creators', () => {
      setAuthStatus('authenticated');

      const { uiConfig } = useSecretContext({ isOwner: true });

      expect(uiConfig.value.showBurnControl).toBe(true);
    });

    it('does not show entitlements upgrade for creators', () => {
      setAuthStatus('authenticated');

      const { uiConfig } = useSecretContext({ isOwner: true });

      expect(uiConfig.value.showEntitlementsUpgrade).toBe(false);
    });

    it('shows dashboard link for creators', () => {
      setAuthStatus('authenticated');

      const { uiConfig } = useSecretContext({ isOwner: true });

      expect(uiConfig.value.headerAction).toBe('DASHBOARD_LINK');
    });
  });

  describe('UI Config for RECIPIENT_AUTH', () => {
    it('does not show burn control for authenticated recipients', () => {
      setAuthStatus('authenticated');

      const { uiConfig } = useSecretContext({ isOwner: false });

      expect(uiConfig.value.showBurnControl).toBe(false);
    });

    it('does not show entitlements upgrade for authenticated recipients', () => {
      setAuthStatus('authenticated');

      const { uiConfig } = useSecretContext({ isOwner: false });

      expect(uiConfig.value.showEntitlementsUpgrade).toBe(false);
    });

    it('shows dashboard link for authenticated recipients', () => {
      setAuthStatus('authenticated');

      const { uiConfig } = useSecretContext({ isOwner: false });

      expect(uiConfig.value.headerAction).toBe('DASHBOARD_LINK');
    });
  });

  describe('UI Config for RECIPIENT_ANON', () => {
    it('does not show burn control for anonymous recipients', () => {
      setAuthStatus('anonymous');

      const { uiConfig } = useSecretContext({ isOwner: false });

      expect(uiConfig.value.showBurnControl).toBe(false);
    });

    it('shows entitlements upgrade for anonymous recipients', () => {
      setAuthStatus('anonymous');

      const { uiConfig } = useSecretContext({ isOwner: false });

      expect(uiConfig.value.showEntitlementsUpgrade).toBe(true);
    });

    it('shows signup CTA for anonymous recipients', () => {
      setAuthStatus('anonymous');

      const { uiConfig } = useSecretContext({ isOwner: false });

      expect(uiConfig.value.headerAction).toBe('SIGNUP_CTA');
    });
  });

  describe('Reactive isOwner Changes', () => {
    it('updates uiConfig when isOwner changes from false to true', () => {
      setAuthStatus('authenticated');

      const isOwnerRef = ref(false);
      const { uiConfig, actorRole } = useSecretContext({ isOwner: isOwnerRef });

      // Initially RECIPIENT_AUTH
      expect(actorRole.value).toBe('RECIPIENT_AUTH');
      expect(uiConfig.value.showBurnControl).toBe(false);
      expect(uiConfig.value.headerAction).toBe('DASHBOARD_LINK');

      // Change to CREATOR
      isOwnerRef.value = true;
      expect(actorRole.value).toBe('CREATOR');
      expect(uiConfig.value.showBurnControl).toBe(true);
      expect(uiConfig.value.headerAction).toBe('DASHBOARD_LINK');
    });

    it('updates uiConfig when authentication state changes', () => {
      setAuthStatus('authenticated');

      const { uiConfig, actorRole } = useSecretContext({ isOwner: false });

      // Initially RECIPIENT_AUTH
      expect(actorRole.value).toBe('RECIPIENT_AUTH');
      expect(uiConfig.value.showEntitlementsUpgrade).toBe(false);

      // User logs out
      setAuthStatus('anonymous');
      expect(actorRole.value).toBe('RECIPIENT_ANON');
      expect(uiConfig.value.showEntitlementsUpgrade).toBe(true);
      expect(uiConfig.value.headerAction).toBe('SIGNUP_CTA');
    });
  });

  describe('Theme Computation', () => {
    it('returns canonical mode for canonical domain strategy', () => {
      const { theme } = useSecretContext();

      expect(theme.value.mode).toBe('canonical');
      expect(theme.value.colors).toBeNull();
    });

    it('returns branded mode for custom domain strategy', () => {
      // Re-create pinia with custom domain state
      const pinia = createTestingPinia({
        createSpy: vi.fn,
        initialState: {
          bootstrap: {
            domain_strategy: 'custom',
            domain_id: 'custom-123',
            domain_branding: { primary_color: '#3b82f6' },
            display_domain: 'custom.example.com',
            canonical_domain: 'onetime.dev',
          },
        },
      });
      setActivePinia(pinia);

      const _identity = useProductIdentity(); // Initialize store

      const { theme } = useSecretContext();

      expect(theme.value.mode).toBe('branded');
      expect(theme.value.colors).toBeDefined();
    });
  });

  describe('Exposed Reactive Properties', () => {
    it('exposes isAuthenticated from authStore', () => {
      setAuthStatus('authenticated');

      const { isAuthenticated } = useSecretContext();

      expect(isAuthenticated.value).toBe(true);

      setAuthStatus('anonymous');
      expect(isAuthenticated.value).toBe(false);
    });

    it('exposes isOwner from options', () => {
      const isOwnerRef = ref(true);
      const { isOwner } = useSecretContext({ isOwner: isOwnerRef });

      expect(isOwner.value).toBe(true);

      isOwnerRef.value = false;
      expect(isOwner.value).toBe(false);
    });
  });
});
