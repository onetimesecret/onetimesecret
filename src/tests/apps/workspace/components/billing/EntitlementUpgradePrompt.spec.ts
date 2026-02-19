// src/tests/apps/workspace/components/billing/EntitlementUpgradePrompt.spec.ts
//
// Tests for EntitlementUpgradePrompt — the component that displays
// an upgrade prompt when an entitlement gate returns a 403 error.
// Verifies visibility rules: requires billing enabled, show prop true,
// and a non-null error. Also tests close/emit behavior.

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import type { Pinia } from 'pinia';
import type { ApplicationError } from '@/schemas/errors';

// Stub OIcon
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="icon-stub" />',
    props: ['collection', 'name'],
  },
}));

// Mock vue-router
vi.mock('vue-router', () => ({
  RouterLink: {
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
  useRoute: vi.fn(() => ({ path: '/', query: {}, params: {} })),
  useRouter: vi.fn(() => ({ push: vi.fn() })),
}));

import EntitlementUpgradePrompt from '@/apps/workspace/components/billing/EntitlementUpgradePrompt.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        billing: {
          upgrade: {
            required: 'Upgrade required',
            viewPlans: 'View Plans',
          },
        },
        LABELS: {
          dismiss: 'Dismiss',
        },
      },
    },
  },
});

function createError(overrides: Partial<ApplicationError> = {}): ApplicationError {
  return {
    code: 'entitlement_required',
    message: 'Homepage secrets require Identity Plus plan',
    status: 403,
    ...overrides,
  } as ApplicationError;
}

describe('EntitlementUpgradePrompt', () => {
  let pinia: Pinia;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  function mountPrompt(options: {
    billingEnabled?: boolean;
    error?: ApplicationError | null;
    show?: boolean;
    resourceType?: string;
  } = {}) {
    const {
      billingEnabled = true,
      error = createError(),
      show = true,
      resourceType = '',
    } = options;

    pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
      initialState: {
        bootstrap: {
          billing_enabled: billingEnabled,
        },
      },
    });

    return mount(EntitlementUpgradePrompt, {
      props: { error, show, resourceType },
      global: {
        plugins: [i18n, pinia],
      },
    });
  }

  describe('visibility conditions', () => {
    it('shows prompt when billing enabled, show=true, and error present', () => {
      const wrapper = mountPrompt();
      expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    });

    it('hides prompt when billing is disabled (self-hosted)', () => {
      const wrapper = mountPrompt({ billingEnabled: false });
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    });

    it('hides prompt when show prop is false', () => {
      const wrapper = mountPrompt({ show: false });
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    });

    it('hides prompt when error is null', () => {
      const wrapper = mountPrompt({ error: null });
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    });

    it('hides prompt when all conditions are unmet', () => {
      const wrapper = mountPrompt({
        billingEnabled: false,
        show: false,
        error: null,
      });
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    });
  });

  describe('content display', () => {
    it('shows the upgrade required heading', () => {
      const wrapper = mountPrompt();
      expect(wrapper.text()).toContain('Upgrade required');
    });

    it('displays the error message from the entitlement gate', () => {
      const wrapper = mountPrompt({
        error: createError({
          message: 'Homepage secrets require Identity Plus plan',
        }),
      });
      expect(wrapper.text()).toContain(
        'Homepage secrets require Identity Plus plan'
      );
    });

    it('falls back to i18n key when error has no message', () => {
      const wrapper = mountPrompt({
        error: createError({ message: '' }),
      });
      // displayMessage falls back to t('web.billing.upgrade.required')
      expect(wrapper.text()).toContain('Upgrade required');
    });

    it('includes a router-link to the billing plans page', () => {
      const wrapper = mountPrompt();
      // The router-link component should be present in the rendered output
      const routerLink = wrapper.findComponent({ name: 'RouterLink' });
      expect(routerLink.exists()).toBe(true);
      expect(routerLink.props('to')).toBe('/billing/plans');
    });
  });

  describe('close behavior', () => {
    it('emits close and update:show on dismiss click', async () => {
      const wrapper = mountPrompt();
      const button = wrapper.find('button');
      await button.trigger('click');

      expect(wrapper.emitted('close')).toHaveLength(1);
      expect(wrapper.emitted('update:show')).toEqual([[false]]);
    });
  });

  describe('homepage_secrets entitlement error scenario', () => {
    it('shows upgrade prompt for homepage_secrets 403 error', () => {
      const wrapper = mountPrompt({
        error: createError({
          code: 'entitlement_required',
          message:
            'Custom homepage secrets require an Identity Plus subscription',
          status: 403,
        }),
        resourceType: 'homepage_secrets',
      });

      expect(wrapper.find('[role="alert"]').exists()).toBe(true);
      expect(wrapper.text()).toContain(
        'Custom homepage secrets require an Identity Plus subscription'
      );
    });

    it('hides upgrade prompt for homepage_secrets when billing disabled', () => {
      const wrapper = mountPrompt({
        billingEnabled: false,
        error: createError({
          code: 'entitlement_required',
          message:
            'Custom homepage secrets require an Identity Plus subscription',
          status: 403,
        }),
        resourceType: 'homepage_secrets',
      });

      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    });
  });

  describe('accessibility', () => {
    it('has alert role with polite live region', () => {
      const wrapper = mountPrompt();
      const alert = wrapper.find('[role="alert"]');
      expect(alert.attributes('aria-live')).toBe('polite');
    });

    it('dismiss button has accessible label', () => {
      const wrapper = mountPrompt();
      const button = wrapper.find('button');
      expect(button.attributes('aria-label')).toBe('Dismiss');
    });
  });
});
