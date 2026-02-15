// src/tests/apps/secret/components/SecretReceiptTableItem.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

// Mock formatRelativeTime
vi.mock('@/utils/format', () => ({
  formatRelativeTime: vi.fn(() => '2 hours ago'),
}));

// Stub RouterLink to avoid router dependency
const RouterLinkStub = {
  name: 'RouterLink',
  template: '<a :href="to"><slot /></a>',
  props: ['to', 'class', 'title', 'aria-label'],
};

// Stub OIcon
const OIconStub = {
  name: 'OIcon',
  template: '<span class="icon-stub" />',
  props: ['collection', 'name', 'size'],
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
    is_viewed: false,
    is_received: false,
    is_burned: false,
    is_destroyed: false,
    is_expired: false,
    is_orphaned: false,
    ...overrides,
  };
}

describe('SecretReceiptTableItem', () => {
  let SecretReceiptTableItem: any;

  beforeEach(async () => {
    vi.resetModules();

    vi.doMock('vue-i18n', () => ({
      useI18n: vi.fn(() => ({
        t: vi.fn((key: string) => key),
      })),
    }));

    vi.doMock('@/utils/format', () => ({
      formatRelativeTime: vi.fn(() => '2 hours ago'),
    }));

    const mod = await import(
      '@/apps/secret/components/SecretReceiptTableItem.vue'
    );
    SecretReceiptTableItem = mod.default;
  });

  function mountComponent(receiptOverrides = {}) {
    return mount(SecretReceiptTableItem, {
      props: {
        secretReceipt: createMockReceipt(receiptOverrides),
      },
      global: {
        stubs: {
          RouterLink: RouterLinkStub,
          OIcon: OIconStub,
        },
      },
    });
  }

  it('displays secret_shortid when present', () => {
    const wrapper = mountComponent({ secret_shortid: 'abc123' });
    const identifier = wrapper.find('.font-mono');
    expect(identifier.text()).toBe('abc1');
  });

  it('displays em-dash when secret_shortid is undefined', () => {
    const wrapper = mountComponent({ secret_shortid: undefined });
    const identifier = wrapper.find('.font-mono');
    expect(identifier.text()).toBe('\u2014');
  });

  it('displays em-dash when secret_shortid is null', () => {
    const wrapper = mountComponent({ secret_shortid: null });
    const identifier = wrapper.find('.font-mono');
    expect(identifier.text()).toBe('\u2014');
  });

  it('does not display "undefined" string when secret_shortid is missing', () => {
    const receipt = createMockReceipt();
    delete (receipt as any).secret_shortid;
    const wrapper = mount(SecretReceiptTableItem, {
      props: { secretReceipt: receipt },
      global: {
        stubs: {
          RouterLink: RouterLinkStub,
          OIcon: OIconStub,
        },
      },
    });
    const identifier = wrapper.find('.font-mono');
    expect(identifier.text()).not.toBe('undefined');
    expect(identifier.text()).toBe('\u2014');
  });

  it('displays em-dash when secret_shortid is empty string', () => {
    // Empty string is falsy, so component returns em-dash
    const wrapper = mountComponent({ secret_shortid: '' });
    const identifier = wrapper.find('.font-mono');
    expect(identifier.text()).toBe('\u2014');
  });
});
