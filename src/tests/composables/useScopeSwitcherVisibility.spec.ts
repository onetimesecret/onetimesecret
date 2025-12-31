// src/tests/composables/useScopeSwitcherVisibility.spec.ts

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, nextTick } from 'vue';

// Create reactive mock route before vi.mock calls
// Using reactive() so that changes trigger computed re-evaluation
const mockRoute = reactive<{
  meta: {
    scopesAvailable?: {
      organization?: 'show' | 'locked' | 'hide';
      domain?: 'show' | 'locked' | 'hide';
    };
  };
}>({
  meta: {},
});

// Mock vue-router - return reactive object directly
vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
}));

describe('useScopeSwitcherVisibility', () => {
  beforeEach(async () => {
    // Reset mock route to default state
    mockRoute.meta = {};
    vi.resetModules();
    vi.clearAllMocks();
  });

  describe('default visibility', () => {
    it('returns organization: "show" when no meta defined', async () => {
      mockRoute.meta = {};

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { visibility } = useScopeSwitcherVisibility();

      expect(visibility.value.organization).toBe('show');
    });

    it('returns domain: "hide" when no meta defined', async () => {
      mockRoute.meta = {};

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { visibility } = useScopeSwitcherVisibility();

      expect(visibility.value.domain).toBe('hide');
    });

    it('returns defaults when scopesAvailable is empty object', async () => {
      mockRoute.meta = { scopesAvailable: {} };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { visibility } = useScopeSwitcherVisibility();

      expect(visibility.value.organization).toBe('show');
      expect(visibility.value.domain).toBe('hide');
    });
  });

  describe('organization switcher', () => {
    it('showOrgSwitcher is true when organization is "show"', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'show' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher } = useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(true);
    });

    it('showOrgSwitcher is true when organization is "locked"', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'locked' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher } = useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(true);
    });

    it('showOrgSwitcher is false when organization is "hide"', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'hide' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher } = useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(false);
    });

    it('lockOrgSwitcher is true only when organization is "locked"', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'locked' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { lockOrgSwitcher } = useScopeSwitcherVisibility();

      expect(lockOrgSwitcher.value).toBe(true);
    });

    it('lockOrgSwitcher is false when organization is "show"', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'show' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { lockOrgSwitcher } = useScopeSwitcherVisibility();

      expect(lockOrgSwitcher.value).toBe(false);
    });

    it('lockOrgSwitcher is false when organization is "hide"', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'hide' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { lockOrgSwitcher } = useScopeSwitcherVisibility();

      expect(lockOrgSwitcher.value).toBe(false);
    });
  });

  describe('domain switcher', () => {
    it('showDomainSwitcher is true when domain is "show"', async () => {
      mockRoute.meta = { scopesAvailable: { domain: 'show' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showDomainSwitcher } = useScopeSwitcherVisibility();

      expect(showDomainSwitcher.value).toBe(true);
    });

    it('showDomainSwitcher is true when domain is "locked"', async () => {
      mockRoute.meta = { scopesAvailable: { domain: 'locked' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showDomainSwitcher } = useScopeSwitcherVisibility();

      expect(showDomainSwitcher.value).toBe(true);
    });

    it('showDomainSwitcher is false when domain is "hide"', async () => {
      mockRoute.meta = { scopesAvailable: { domain: 'hide' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showDomainSwitcher } = useScopeSwitcherVisibility();

      expect(showDomainSwitcher.value).toBe(false);
    });

    it('showDomainSwitcher is false by default (domain defaults to "hide")', async () => {
      mockRoute.meta = {};

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showDomainSwitcher } = useScopeSwitcherVisibility();

      expect(showDomainSwitcher.value).toBe(false);
    });

    it('lockDomainSwitcher is true only when domain is "locked"', async () => {
      mockRoute.meta = { scopesAvailable: { domain: 'locked' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { lockDomainSwitcher } = useScopeSwitcherVisibility();

      expect(lockDomainSwitcher.value).toBe(true);
    });

    it('lockDomainSwitcher is false when domain is "show"', async () => {
      mockRoute.meta = { scopesAvailable: { domain: 'show' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { lockDomainSwitcher } = useScopeSwitcherVisibility();

      expect(lockDomainSwitcher.value).toBe(false);
    });

    it('lockDomainSwitcher is false when domain is "hide"', async () => {
      mockRoute.meta = { scopesAvailable: { domain: 'hide' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { lockDomainSwitcher } = useScopeSwitcherVisibility();

      expect(lockDomainSwitcher.value).toBe(false);
    });
  });

  describe('route meta reading', () => {
    it('reads scopesAvailable from route.meta', async () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'locked',
          domain: 'show',
        },
      };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { visibility } = useScopeSwitcherVisibility();

      expect(visibility.value.organization).toBe('locked');
      expect(visibility.value.domain).toBe('show');
    });

    it('updates when route changes', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'show' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { visibility, showOrgSwitcher } = useScopeSwitcherVisibility();

      expect(visibility.value.organization).toBe('show');
      expect(showOrgSwitcher.value).toBe(true);

      // Simulate route change
      mockRoute.meta = { scopesAvailable: { organization: 'hide' } };
      await nextTick();

      expect(visibility.value.organization).toBe('hide');
      expect(showOrgSwitcher.value).toBe(false);
    });

    it('handles partial scopesAvailable config', async () => {
      mockRoute.meta = { scopesAvailable: { organization: 'locked' } };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { visibility } = useScopeSwitcherVisibility();

      expect(visibility.value.organization).toBe('locked');
      expect(visibility.value.domain).toBe('hide'); // Default
    });
  });

  describe('visibility object', () => {
    it('returns complete visibility state object', async () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'show',
          domain: 'locked',
        },
      };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const {
        visibility,
        showOrgSwitcher,
        lockOrgSwitcher,
        showDomainSwitcher,
        lockDomainSwitcher,
      } = useScopeSwitcherVisibility();

      // Verify visibility object
      expect(visibility.value).toEqual({
        organization: 'show',
        domain: 'locked',
      });

      // Verify computed boolean helpers
      expect(showOrgSwitcher.value).toBe(true);
      expect(lockOrgSwitcher.value).toBe(false);
      expect(showDomainSwitcher.value).toBe(true);
      expect(lockDomainSwitcher.value).toBe(true);
    });

    it('returns all expected properties from composable', async () => {
      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const result = useScopeSwitcherVisibility();

      expect(result).toHaveProperty('visibility');
      expect(result).toHaveProperty('showOrgSwitcher');
      expect(result).toHaveProperty('lockOrgSwitcher');
      expect(result).toHaveProperty('showDomainSwitcher');
      expect(result).toHaveProperty('lockDomainSwitcher');
    });
  });

  describe('combined states', () => {
    it('handles both switchers shown', async () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'show',
          domain: 'show',
        },
      };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher, showDomainSwitcher, lockOrgSwitcher, lockDomainSwitcher } =
        useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(true);
      expect(showDomainSwitcher.value).toBe(true);
      expect(lockOrgSwitcher.value).toBe(false);
      expect(lockDomainSwitcher.value).toBe(false);
    });

    it('handles both switchers hidden', async () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'hide',
          domain: 'hide',
        },
      };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher, showDomainSwitcher } = useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(false);
      expect(showDomainSwitcher.value).toBe(false);
    });

    it('handles both switchers locked', async () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'locked',
          domain: 'locked',
        },
      };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher, showDomainSwitcher, lockOrgSwitcher, lockDomainSwitcher } =
        useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(true);
      expect(showDomainSwitcher.value).toBe(true);
      expect(lockOrgSwitcher.value).toBe(true);
      expect(lockDomainSwitcher.value).toBe(true);
    });

    it('handles mixed states (org shown, domain locked)', async () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'show',
          domain: 'locked',
        },
      };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher, showDomainSwitcher, lockOrgSwitcher, lockDomainSwitcher } =
        useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(true);
      expect(lockOrgSwitcher.value).toBe(false);
      expect(showDomainSwitcher.value).toBe(true);
      expect(lockDomainSwitcher.value).toBe(true);
    });

    it('handles mixed states (org locked, domain hidden)', async () => {
      mockRoute.meta = {
        scopesAvailable: {
          organization: 'locked',
          domain: 'hide',
        },
      };

      const { useScopeSwitcherVisibility } = await import(
        '@/shared/composables/useScopeSwitcherVisibility'
      );
      const { showOrgSwitcher, showDomainSwitcher, lockOrgSwitcher, lockDomainSwitcher } =
        useScopeSwitcherVisibility();

      expect(showOrgSwitcher.value).toBe(true);
      expect(lockOrgSwitcher.value).toBe(true);
      expect(showDomainSwitcher.value).toBe(false);
      expect(lockDomainSwitcher.value).toBe(false);
    });
  });
});
