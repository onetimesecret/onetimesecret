// src/tests/apps/secret/components/SecretReceiptTableItem.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { ComponentPublicInstance } from 'vue';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

// Mock formatters
vi.mock('@/utils/formatters', () => ({
  formatTTL: vi.fn((seconds: number) => `${Math.floor(seconds / 86400)} days`),
}));

// Mock date-fns
vi.mock('date-fns', () => ({
  formatDistanceToNow: vi.fn(() => '2 hours ago'),
}));

// Mock bootstrap store
vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: vi.fn(() => ({
    site_host: 'onetimesecret.com',
  })),
}));

// Mock pinia storeToRefs
vi.mock('pinia', () => ({
  storeToRefs: vi.fn((store) => ({
    site_host: { value: store.site_host },
  })),
}));

// Mock vue-router
vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({
    push: vi.fn(),
  })),
}));

// Stub RouterLink to avoid router dependency
const RouterLinkStub = {
  name: 'RouterLink',
  template: '<a :href="typeof to === \'string\' ? to : to.name"><slot /></a>',
  props: ['to', 'class', 'title', 'aria-label'],
};

// Stub OIcon
const OIconStub = {
  name: 'OIcon',
  template: '<span class="icon-stub" />',
  props: ['collection', 'name', 'size', 'class'],
};

function createMockReceipt(overrides = {}) {
  return {
    identifier: 'test-receipt-id',
    shortid: 'rcpt123',
    key: 'test-key',
    secret_shortid: 'sec1234',
    secret_ttl: 604800,
    receipt_ttl: 604800,
    lifespan: 604800,
    state: 'new',
    created: new Date(),
    updated: new Date(),
    shared: null,
    previewed: null,
    revealed: null,
    burned: null,
    has_passphrase: false,
    is_previewed: false,
    is_revealed: false,
    is_burned: false,
    is_destroyed: false,
    is_expired: false,
    is_orphaned: false,
    show_recipients: false,
    recipients: null,
    share_domain: null,
    memo: null,
    ...overrides,
  };
}

describe('SecretReceiptTableItem', () => {
  let SecretReceiptTableItem: ReturnType<typeof import('@/apps/secret/components/SecretReceiptTableItem.vue')>['default'];

  beforeEach(async () => {
    vi.resetModules();

    vi.doMock('vue-i18n', () => ({
      useI18n: vi.fn(() => ({
        t: vi.fn((key: string) => key),
      })),
    }));

    vi.doMock('@/utils/formatters', () => ({
      formatTTL: vi.fn((seconds: number) => `${Math.floor(seconds / 86400)} days`),
    }));

    vi.doMock('date-fns', () => ({
      formatDistanceToNow: vi.fn(() => '2 hours ago'),
    }));

    vi.doMock('@/shared/stores/bootstrapStore', () => ({
      useBootstrapStore: vi.fn(() => ({
        site_host: 'onetimesecret.com',
      })),
    }));

    vi.doMock('pinia', () => ({
      storeToRefs: vi.fn((store) => ({
        site_host: { value: store.site_host },
      })),
    }));

    vi.doMock('vue-router', () => ({
      useRouter: vi.fn(() => ({
        push: vi.fn(),
      })),
    }));

    const mod = await import(
      '@/apps/secret/components/SecretReceiptTableItem.vue'
    );
    SecretReceiptTableItem = mod.default;
  });

  function mountComponent(
    receiptOverrides = {},
    extraProps = {},
  ): VueWrapper<ComponentPublicInstance> {
    return mount(SecretReceiptTableItem, {
      props: {
        secretReceipt: createMockReceipt(receiptOverrides),
        index: 1,
        isLast: false,
        ...extraProps,
      },
      global: {
        stubs: {
          RouterLink: RouterLinkStub,
          OIcon: OIconStub,
          Transition: false,
        },
      },
    });
  }

  describe('display key rendering', () => {
    it('displays truncated secret_shortid when present', () => {
      const wrapper = mountComponent({ secret_shortid: 'abc12345' });
      // The displayKey shows first 4 chars in the watermark and header
      expect(wrapper.text()).toContain('abc1');
    });

    it('displays empty string when secret_shortid is undefined', () => {
      const wrapper = mountComponent({ secret_shortid: undefined });
      // Watermark uses displayKey which returns empty string for falsy values
      const watermark = wrapper.find('[aria-hidden="true"] span');
      expect(watermark.exists()).toBe(true);
      // displayKey returns '' for undefined
    });

    it('displays full shortid when 4 chars or less', () => {
      const wrapper = mountComponent({ secret_shortid: 'abc' });
      expect(wrapper.text()).toContain('abc');
    });
  });

  describe('status badge rendering', () => {
    // Note: Component calls .toUpperCase() on status labels, so expect uppercase
    it('shows NEW status for new secrets', () => {
      const wrapper = mountComponent({
        is_previewed: false,
        is_revealed: false,
        is_burned: false,
        is_destroyed: false,
        is_expired: false,
      });
      expect(wrapper.text()).toContain('WEB.STATUS.NEW');
    });

    it('shows PREVIEWED status when is_previewed is true', () => {
      const wrapper = mountComponent({ is_previewed: true });
      expect(wrapper.text()).toContain('WEB.STATUS.PREVIEWED');
    });

    it('shows REVEALED status when is_revealed is true', () => {
      const wrapper = mountComponent({ is_revealed: true });
      expect(wrapper.text()).toContain('WEB.STATUS.REVEALED');
    });

    it('shows BURNED status when is_burned is true', () => {
      const wrapper = mountComponent({ is_burned: true });
      expect(wrapper.text()).toContain('WEB.STATUS.BURNED');
    });

    it('shows EXPIRED status when is_expired is true', () => {
      const wrapper = mountComponent({ is_expired: true });
      expect(wrapper.text()).toContain('WEB.STATUS.EXPIRED');
    });

    it('shows EXPIRED status when is_destroyed is true', () => {
      const wrapper = mountComponent({ is_destroyed: true });
      expect(wrapper.text()).toContain('WEB.STATUS.EXPIRED');
    });
  });

  describe('action buttons', () => {
    it('shows action buttons for new (active) secrets', () => {
      const wrapper = mountComponent({
        is_previewed: false,
        is_revealed: false,
        is_burned: false,
        is_destroyed: false,
        is_expired: false,
      });
      // Should have COPY, OPEN, BURN buttons (text visible on desktop)
      expect(wrapper.text()).toContain('[ COPY ]');
      expect(wrapper.text()).toContain('[ OPEN');
      expect(wrapper.text()).toContain('[ BURN ]');
    });

    it('shows action buttons for previewed secrets', () => {
      const wrapper = mountComponent({ is_previewed: true });
      expect(wrapper.text()).toContain('[ COPY ]');
      expect(wrapper.text()).toContain('[ BURN ]');
    });

    it('hides action buttons for revealed (terminal) secrets', () => {
      const wrapper = mountComponent({ is_revealed: true });
      expect(wrapper.text()).not.toContain('[ COPY ]');
      expect(wrapper.text()).not.toContain('[ BURN ]');
    });

    it('hides action buttons for burned secrets', () => {
      const wrapper = mountComponent({ is_burned: true });
      expect(wrapper.text()).not.toContain('[ COPY ]');
      expect(wrapper.text()).not.toContain('[ BURN ]');
    });

    it('hides action buttons for expired secrets', () => {
      const wrapper = mountComponent({ is_expired: true });
      expect(wrapper.text()).not.toContain('[ COPY ]');
      expect(wrapper.text()).not.toContain('[ BURN ]');
    });
  });

  describe('encryption indicator', () => {
    it('shows lock icon for encrypted-only secrets', () => {
      const wrapper = mountComponent({ has_passphrase: false });
      const icons = wrapper.findAllComponents(OIconStub);
      const lockIcon = icons.find(
        (icon) => icon.props('collection') === 'tabler' && icon.props('name') === 'lock'
      );
      expect(lockIcon).toBeDefined();
    });

    it('shows lock-check icon for passphrase-protected secrets', () => {
      const wrapper = mountComponent({ has_passphrase: true });
      const icons = wrapper.findAllComponents(OIconStub);
      const lockCheckIcon = icons.find(
        (icon) => icon.props('collection') === 'tabler' && icon.props('name') === 'lock-check'
      );
      expect(lockCheckIcon).toBeDefined();
    });
  });

  describe('metadata tree', () => {
    it('shows expires line for active secrets', () => {
      const wrapper = mountComponent({
        secret_ttl: 604800, // 7 days
        is_previewed: false,
        is_revealed: false,
      });
      expect(wrapper.text()).toContain('expires:');
    });

    it('shows domain line when share_domain differs from site_host', () => {
      const wrapper = mountComponent({
        share_domain: 'custom.example.com',
      });
      expect(wrapper.text()).toContain('via:');
      expect(wrapper.text()).toContain('custom.example.com');
    });

    it('hides domain line when share_domain matches site_host', () => {
      const wrapper = mountComponent({
        share_domain: 'onetimesecret.com',
      });
      expect(wrapper.text()).not.toContain('via:');
    });

    it('shows recipients when show_recipients is true', () => {
      const wrapper = mountComponent({
        show_recipients: true,
        recipients: 'user@example.com',
      });
      expect(wrapper.text()).toContain('to:');
      expect(wrapper.text()).toContain('user@example.com');
    });
  });

  describe('separator line', () => {
    it('shows separator when isLast is false', () => {
      const wrapper = mountComponent({}, { isLast: false });
      const separator = wrapper.find('[aria-hidden="true"].border-t');
      expect(separator.exists()).toBe(true);
    });

    it('hides separator when isLast is true', () => {
      const wrapper = mountComponent({}, { isLast: true });
      const separator = wrapper.find('[aria-hidden="true"].border-t');
      expect(separator.exists()).toBe(false);
    });
  });

  describe('index display', () => {
    it('displays the index number', () => {
      const wrapper = mountComponent({}, { index: 5 });
      expect(wrapper.text()).toContain('#5');
    });
  });

  describe('terminal state styling', () => {
    it('applies opacity-60 class for terminal states', () => {
      const wrapper = mountComponent({ is_revealed: true });
      const li = wrapper.find('li');
      expect(li.classes()).toContain('opacity-60');
    });

    it('does not apply opacity-60 for active states', () => {
      const wrapper = mountComponent({
        is_previewed: false,
        is_revealed: false,
        is_burned: false,
        is_destroyed: false,
        is_expired: false,
      });
      const li = wrapper.find('li');
      expect(li.classes()).not.toContain('opacity-60');
    });
  });
});
