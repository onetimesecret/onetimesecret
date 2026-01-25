// src/tests/views/dashboard/DashboardBasic.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import DashboardBasic from '@/apps/workspace/dashboard/DashboardBasic.vue';

// Mock components
vi.mock('@/apps/secret/components/form/SecretForm.vue', () => ({
  default: {
    name: 'SecretForm',
    template: '<div data-testid="secret-form">Secret Form</div>',
  },
}));

vi.mock('@/apps/secret/components/RecentSecretsTable.vue', () => ({
  default: {
    name: 'RecentSecretsTable',
    template: '<div data-testid="recent-secrets">Recent Secrets</div>',
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {},
  },
});

describe('DashboardBasic', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  const mountComponent = (custOverrides = {}, billingEnabled = true) => {
    return mount(DashboardBasic, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: {
                cust: {
                  feature_flags: { beta: false },
                  ...custOverrides,
                },
                billing_enabled: billingEnabled,
              },
            },
          }),
        ],
      },
    });
  };

  describe('Rendering', () => {
    it('renders SecretForm component', () => {
      const wrapper = mountComponent();

      expect(wrapper.find('[data-testid="secret-form"]').exists()).toBe(true);
    });

    it('renders container with correct max-width', () => {
      const wrapper = mountComponent();

      const container = wrapper.find('.container');
      expect(container.exists()).toBe(true);
      expect(container.classes()).toContain('max-w-2xl');
      expect(container.classes()).toContain('mx-auto');
    });
  });

  describe('RecentSecretsTable display', () => {
    it('shows RecentSecretsTable when beta feature is enabled', () => {
      const wrapper = mountComponent({ feature_flags: { beta: true } });

      expect(wrapper.find('[data-testid="recent-secrets"]').exists()).toBe(true);
    });

    it('hides RecentSecretsTable when beta feature is disabled', () => {
      const wrapper = mountComponent({ feature_flags: { beta: false } });

      expect(wrapper.find('[data-testid="recent-secrets"]').exists()).toBe(false);
    });

    it('hides RecentSecretsTable when feature_flags is undefined', () => {
      const wrapper = mountComponent({ feature_flags: undefined });

      expect(wrapper.find('[data-testid="recent-secrets"]').exists()).toBe(false);
    });

    it('hides RecentSecretsTable when cust is undefined', () => {
      const wrapper = mount(DashboardBasic, {
        global: {
          plugins: [
            i18n,
            createTestingPinia({
              createSpy: vi.fn,
              initialState: {
                bootstrap: {
                  cust: null,
                  billing_enabled: true,
                },
              },
            }),
          ],
        },
      });

      expect(wrapper.find('[data-testid="recent-secrets"]').exists()).toBe(false);
    });
  });

  describe('SecretForm configuration', () => {
    it('enables generate feature on SecretForm', () => {
      const wrapper = mountComponent();

      const secretForm = wrapper.findComponent({ name: 'SecretForm' });
      expect(secretForm.attributes('with-generate')).toBe('true');
    });

    it('enables recipient feature on SecretForm', () => {
      const wrapper = mountComponent();

      const secretForm = wrapper.findComponent({ name: 'SecretForm' });
      expect(secretForm.attributes('with-recipient')).toBe('true');
    });

    it('applies margin bottom to SecretForm', () => {
      const wrapper = mountComponent();

      const secretForm = wrapper.findComponent({ name: 'SecretForm' });
      expect(secretForm.classes()).toContain('mb-10');
    });
  });

  describe('Layout and spacing', () => {
    it('sets minimum container width', () => {
      const wrapper = mountComponent();

      const container = wrapper.find('.container');
      expect(container.classes()).toContain('min-w-[320px]');
    });
  });

  describe('Dark mode support', () => {
    it('has structure compatible with dark mode classes', () => {
      const wrapper = mountComponent();

      // Verify container exists and can support dark mode
      const container = wrapper.find('.container');
      expect(container.exists()).toBe(true);
    });
  });

  describe('Responsive layout', () => {
    it('uses responsive container classes', () => {
      const wrapper = mountComponent();

      const container = wrapper.find('.container');
      expect(container.classes()).toContain('mx-auto');
      expect(container.classes()).toContain('min-w-[320px]');
      expect(container.classes()).toContain('max-w-2xl');
    });
  });

  describe('Component composition', () => {
    it('renders SecretForm and RecentSecretsTable when beta enabled', () => {
      const wrapper = mount(DashboardBasic, {
        global: {
          plugins: [
            i18n,
            createTestingPinia({
              createSpy: vi.fn,
              initialState: {
                bootstrap: {
                  cust: { feature_flags: { beta: true } },
                  billing_enabled: true,
                },
              },
            }),
          ],
        },
      });

      expect(wrapper.find('[data-testid="secret-form"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="recent-secrets"]').exists()).toBe(true);
    });

    it('renders only SecretForm when beta disabled', () => {
      const wrapper = mount(DashboardBasic, {
        global: {
          plugins: [
            i18n,
            createTestingPinia({
              createSpy: vi.fn,
              initialState: {
                bootstrap: {
                  cust: { feature_flags: { beta: false } },
                  billing_enabled: false,
                },
              },
            }),
          ],
        },
      });

      expect(wrapper.find('[data-testid="secret-form"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="recent-secrets"]').exists()).toBe(false);
    });
  });
});
