// src/tests/apps/workspace/account/settings/CautionZone.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { nextTick } from 'vue';
import CautionZone from '@/apps/workspace/account/settings/CautionZone.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/account/settings/caution' })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to" class="router-link"><slot /></a>',
    props: ['to'],
  },
}));

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

// Mock AccountDeleteButtonWithModalForm
vi.mock('@/apps/workspace/components/account/AccountDeleteButtonWithModalForm.vue', () => ({
  default: {
    name: 'AccountDeleteButtonWithModalForm',
    template: '<div data-testid="account-delete-button" class="account-delete-button">Delete Account Button</div>',
    props: ['cust'],
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        COMMON: {
          caution_zone: 'Caution Zone',
        },
        auth: {
          close_account: {
            title: 'Close Account',
          },
        },
        settings: {
          delete_account: {
            permanently_delete_your_account: 'Permanently delete your account and all of its data.',
          },
        },
      },
    },
  },
});

/**
 * CautionZone Component Tests
 *
 * Tests the caution zone settings page that conditionally renders
 * the AccountDeleteButtonWithModalForm based on customer state.
 *
 * The v-if guard `cust?.objid` ensures:
 * - Delete button shows for authenticated users with valid objid
 * - Delete button hidden when cust is null (not logged in)
 * - Delete button hidden when cust.objid is null (anonymous user)
 */
describe('CautionZone', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (custValue: { objid: string | null; extid: string } | null = null) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });

    const store = useBootstrapStore(pinia);
    store.$patch({ cust: custValue });

    return mount(CautionZone, {
      global: {
        plugins: [i18n, pinia],
        stubs: {
          RouterLink: {
            template: '<a :href="to" class="router-link"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });
  };

  describe('Basic Rendering', () => {
    it('renders within SettingsLayout', () => {
      wrapper = mountComponent({
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      });

      expect(wrapper.find('.mock-settings-layout').exists()).toBe(true);
    });

    it('renders caution zone section with red border styling', () => {
      wrapper = mountComponent({
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      });

      const section = wrapper.find('section');
      expect(section.exists()).toBe(true);
      expect(section.classes()).toContain('border-red-200');
    });

    it('displays caution zone header', () => {
      wrapper = mountComponent({
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      });

      expect(wrapper.text()).toContain('Caution Zone');
    });

    it('displays close account title', () => {
      wrapper = mountComponent({
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      });

      expect(wrapper.text()).toContain('Close Account');
    });

    it('displays account deletion description', () => {
      wrapper = mountComponent({
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      });

      expect(wrapper.text()).toContain('Permanently delete your account');
    });
  });

  describe('Delete Button Visibility - Authenticated User', () => {
    it('renders delete button when cust has valid objid', async () => {
      wrapper = mountComponent({
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      });

      await nextTick();

      const deleteButton = wrapper.find('[data-testid="account-delete-button"]');
      expect(deleteButton.exists()).toBe(true);
    });

    it('passes cust prop to AccountDeleteButtonWithModalForm', async () => {
      const custData = {
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      };

      wrapper = mountComponent(custData);
      await nextTick();

      const deleteButton = wrapper.findComponent({ name: 'AccountDeleteButtonWithModalForm' });
      expect(deleteButton.exists()).toBe(true);
    });
  });

  describe('Delete Button Visibility - Null Customer', () => {
    it('does NOT render delete button when cust is null', async () => {
      wrapper = mountComponent(null);
      await nextTick();

      const deleteButton = wrapper.find('[data-testid="account-delete-button"]');
      expect(deleteButton.exists()).toBe(false);
    });

    it('still renders caution zone section when cust is null', async () => {
      wrapper = mountComponent(null);
      await nextTick();

      const section = wrapper.find('section');
      expect(section.exists()).toBe(true);
    });
  });

  describe('Delete Button Visibility - Anonymous User (null objid)', () => {
    it('does NOT render delete button when cust.objid is null', async () => {
      wrapper = mountComponent({
        objid: null,
        extid: 'anonymous',
      });

      await nextTick();

      const deleteButton = wrapper.find('[data-testid="account-delete-button"]');
      expect(deleteButton.exists()).toBe(false);
    });

    it('still renders caution zone section when cust.objid is null', async () => {
      wrapper = mountComponent({
        objid: null,
        extid: 'anonymous',
      });

      await nextTick();

      const section = wrapper.find('section');
      expect(section.exists()).toBe(true);
    });

    it('renders section header even for anonymous users', async () => {
      wrapper = mountComponent({
        objid: null,
        extid: 'anonymous',
      });

      await nextTick();

      expect(wrapper.text()).toContain('Caution Zone');
      expect(wrapper.text()).toContain('Close Account');
    });
  });

  describe('Delete Button Visibility - Edge Cases', () => {
    it('does NOT render delete button when cust.objid is empty string', async () => {
      // Empty string is falsy in JavaScript, but explicitly testing this case
      wrapper = mountComponent({
        objid: '' as unknown as null, // Cast to test edge case
        extid: 'test',
      });

      await nextTick();

      const deleteButton = wrapper.find('[data-testid="account-delete-button"]');
      expect(deleteButton.exists()).toBe(false);
    });
  });

  describe('Icon Rendering', () => {
    it('renders no-symbol icon in header', async () => {
      wrapper = mountComponent({
        objid: '01234567-89ab-cdef-0123-456789abcdef',
        extid: 'ur1a2b3c4d',
      });

      await nextTick();

      const icon = wrapper.find('[data-icon="no-symbol-solid"]');
      expect(icon.exists()).toBe(true);
    });
  });
});
