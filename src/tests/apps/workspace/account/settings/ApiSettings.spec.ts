// src/tests/apps/workspace/account/settings/ApiSettings.spec.ts

import ApiSettings from '@/apps/workspace/account/settings/ApiSettings.vue';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createTestI18n } from '@tests/setup';

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock SettingsLayout
vi.mock('@/apps/workspace/layouts/SettingsLayout.vue', () => ({
  default: {
    name: 'SettingsLayout',
    template: '<div class="mock-settings-layout"><slot /></div>',
  },
}));

// Mock APIKeyForm (owns its own submit flow; not under test here)
vi.mock('@/apps/workspace/components/account/APIKeyForm.vue', () => ({
  default: {
    name: 'APIKeyForm',
    template: '<div class="api-key-form" data-testid="api-key-form" />',
    props: ['apitoken'],
  },
}));

// Mock CopyButton to expose the copied text as an attribute
vi.mock('@/shared/components/ui/CopyButton.vue', () => ({
  default: {
    name: 'CopyButton',
    template: '<button type="button" :data-testid="testid" :data-copy-text="text" />',
    props: ['text', 'testid', 'tooltip'],
  },
}));

// i18n setup (pass-through: keys render as-is, see ADR-014)
const i18n = createTestI18n();

/**
 * Account fixture matching the shape ApiSettings reads:
 * account.apitoken (API token block) and account.cust.extid (Basic auth
 * username block). The extid (ur… prefix) — or the account email — is the
 * only identifier BasicAuthStrategy resolves as a username.
 */
const mockAccount = {
  apitoken: 'token-abc-123',
  cust: {
    extid: 'ur1a2b3c4d',
    email: 'user@example.com',
  },
};

describe('ApiSettings', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    wrapper?.unmount();
  });

  const mountComponent = async ({
    account = mockAccount as unknown,
    apiEnabled = true,
  }: { account?: unknown; apiEnabled?: boolean } = {}) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      // Actions are stubbed by default, so accountStore.fetch() in onMounted
      // is a no-op; state comes entirely from initialState below.
      initialState: {
        account: { account },
        bootstrap: { api: { enabled: apiEnabled } },
      },
    });

    wrapper = mount(ApiSettings, {
      global: {
        plugins: [i18n, pinia],
      },
    });
    await flushPromises();
    return wrapper;
  };

  describe('API Username block', () => {
    it('shows the customer extid as the API username', async () => {
      wrapper = await mountComponent();

      const section = wrapper.find('[data-testid="api-username-section"]');
      expect(section.exists()).toBe(true);
      expect(section.text()).toContain('web.settings.api.api_username');

      const field = section.find('[data-testid="api-username-field"]');
      expect(field.exists()).toBe(true);
      expect(field.text()).toContain('ur1a2b3c4d');
    });

    it('provides a copy button carrying the extid', async () => {
      wrapper = await mountComponent();

      const copyButton = wrapper.find('[data-testid="api-username-copy"]');
      expect(copyButton.exists()).toBe(true);
      expect(copyButton.attributes('data-copy-text')).toBe('ur1a2b3c4d');
    });

    it('explains the Basic auth username/password mapping', async () => {
      wrapper = await mountComponent();

      const section = wrapper.find('[data-testid="api-username-section"]');
      expect(section.text()).toContain('web.settings.api.basic_auth_hint');
    });

    it('omits the extid field while the account has not loaded', async () => {
      wrapper = await mountComponent({ account: null });

      // Section (with the hint) still renders; the copyable field does not.
      expect(wrapper.find('[data-testid="api-username-section"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="api-username-field"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="api-username-copy"]').exists()).toBe(false);
    });
  });

  describe('API disabled', () => {
    it('shows only the disabled notice — no token or username sections', async () => {
      wrapper = await mountComponent({ apiEnabled: false });

      expect(wrapper.text()).toContain('web.settings.api.api_disabled_notice');
      expect(wrapper.find('[data-testid="api-key-form"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="api-username-section"]').exists()).toBe(false);
    });
  });
});
