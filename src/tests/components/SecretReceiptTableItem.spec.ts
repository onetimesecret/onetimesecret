// src/tests/components/SecretReceiptTableItem.spec.ts

/**
 * Tests for SecretReceiptTableItem component state priority.
 *
 * Regression test for burned vs expired status display bug:
 * When a secret is burned, the backend may also set is_expired=true or secret_ttl=0.
 * The UI must show "BURNED" (not "EXPIRED") because burned is the actual state.
 *
 * Priority: burned > expired > revealed > previewed > new
 */

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { createRouter, createMemoryHistory } from 'vue-router';
import SecretReceiptTableItem from '@/apps/secret/components/SecretReceiptTableItem.vue';
import type { ReceiptList } from '@/schemas/shapes/v3/receipt';

// Minimal i18n setup
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        STATUS: {
          expired: 'Expired',
          burned: 'Burned',
          revealed: 'Revealed',
          previewed: 'Previewed',
          new: 'New',
        },
        LABELS: {
          encrypted: 'Encrypted',
          passphrase_protected: 'Passphrase protected',
          copy_to_clipboard: 'Copy to clipboard',
        },
        COMMON: {
          view_secret: 'View secret',
          burn: 'Burn',
        },
        receipt: {
          view_receipt: 'View receipt',
        },
      },
    },
  },
});

// Minimal router
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { path: '/', name: 'Home', component: { template: '<div />' } },
    { path: '/receipt/:receiptIdentifier', name: 'Receipt link', component: { template: '<div />' } },
    { path: '/burn/:receiptIdentifier', name: 'Burn secret', component: { template: '<div />' } },
  ],
});

/**
 * Factory for creating receipt test data.
 * All boolean flags default to false; override as needed.
 */
function createReceipt(overrides: Partial<ReceiptList> = {}): ReceiptList {
  const now = new Date();
  return {
    identifier: 'receipt-abc123',
    key: 'test-key',
    shortid: 'abc123',
    state: 'new',
    custid: 'cust-123',
    owner_id: 'owner-123',
    created: now,
    updated: now,
    shared: null,
    previewed: null,
    revealed: null,
    burned: null,
    secret_ttl: 3600,
    receipt_ttl: 7200,
    lifespan: 3600,
    secret_shortid: 'sec-xyz',
    secret_identifier: 'secret-xyz789',
    recipients: null,
    recipient_name: null,
    share_domain: null,
    has_passphrase: false,
    is_previewed: false,
    is_revealed: false,
    is_burned: false,
    is_destroyed: false,
    is_expired: false,
    is_orphaned: false,
    memo: null,
    kind: 'conceal',
    show_recipients: false,
    ...overrides,
  };
}

function mountComponent(receipt: ReceiptList) {
  return mount(SecretReceiptTableItem, {
    props: {
      secretReceipt: receipt,
      index: 1,
      isLast: false,
    },
    global: {
      plugins: [
        i18n,
        router,
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            bootstrap: {
              site_host: 'onetimesecret.com',
            },
          },
        }),
      ],
      stubs: {
        OIcon: { template: '<span class="icon-stub" />' },
      },
    },
  });
}

describe('SecretReceiptTableItem', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('itemState priority', () => {
    it('shows BURNED when is_burned=true even if is_expired=true', () => {
      // This is the bug: a burned secret often has is_expired=true too
      const receipt = createReceipt({
        is_burned: true,
        is_expired: true,
        secret_ttl: 0,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('BURNED');
      expect(statusLabel.classes()).toContain('text-red-600');
    });

    it('shows BURNED when is_burned=true and secret_ttl=0', () => {
      const receipt = createReceipt({
        is_burned: true,
        secret_ttl: 0,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('BURNED');
    });

    it('shows BURNED when is_burned=true and is_destroyed=true', () => {
      const receipt = createReceipt({
        is_burned: true,
        is_destroyed: true,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('BURNED');
    });

    it('shows EXPIRED when is_expired=true but is_burned=false', () => {
      const receipt = createReceipt({
        is_expired: true,
        is_burned: false,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('EXPIRED');
    });

    it('shows EXPIRED when secret_ttl=0 and is_burned=false', () => {
      const receipt = createReceipt({
        secret_ttl: 0,
        is_burned: false,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('EXPIRED');
    });

    it('shows EXPIRED when is_destroyed=true but is_burned=false', () => {
      const receipt = createReceipt({
        is_destroyed: true,
        is_burned: false,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('EXPIRED');
    });

    it('shows REVEALED when is_revealed=true (not expired or burned)', () => {
      const receipt = createReceipt({
        is_revealed: true,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('REVEALED');
    });

    it('shows REVEALED when is_revealed=true even if is_destroyed=true and secret_ttl=-1', () => {
      // Real backend data: revealed secrets have is_destroyed=true and secret_ttl=-1
      const receipt = createReceipt({
        is_revealed: true,
        is_destroyed: true,
        secret_ttl: -1,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('REVEALED');
    });

    it('shows REVEALED when is_revealed=true even if is_expired=true', () => {
      const receipt = createReceipt({
        is_revealed: true,
        is_expired: true,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('REVEALED');
    });

    it('shows PREVIEWED when is_previewed=true (not expired, burned, or revealed)', () => {
      const receipt = createReceipt({
        is_previewed: true,
      });

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('PREVIEWED');
    });

    it('shows NEW when no state flags are set', () => {
      const receipt = createReceipt();

      const wrapper = mountComponent(receipt);
      const statusLabel = wrapper.find('.font-semibold.tracking-wide');

      expect(statusLabel.text()).toBe('NEW');
    });
  });

  describe('terminal state styling', () => {
    it('applies terminal opacity for burned state', () => {
      const receipt = createReceipt({ is_burned: true });

      const wrapper = mountComponent(receipt);
      const listItem = wrapper.find('li');

      expect(listItem.classes()).toContain('opacity-60');
    });

    it('applies terminal opacity for expired state', () => {
      const receipt = createReceipt({ is_expired: true });

      const wrapper = mountComponent(receipt);
      const listItem = wrapper.find('li');

      expect(listItem.classes()).toContain('opacity-60');
    });

    it('does not apply terminal opacity for new state', () => {
      const receipt = createReceipt();

      const wrapper = mountComponent(receipt);
      const listItem = wrapper.find('li');

      expect(listItem.classes()).not.toContain('opacity-60');
    });
  });

  describe('action buttons visibility', () => {
    it('shows action buttons for new state', () => {
      const receipt = createReceipt();

      const wrapper = mountComponent(receipt);
      // For active states, the actions div with buttons should exist
      const buttons = wrapper.findAll('button');

      expect(buttons.length).toBeGreaterThan(0);
    });

    it('hides action buttons for burned state', () => {
      const receipt = createReceipt({ is_burned: true });

      const wrapper = mountComponent(receipt);

      expect(wrapper.findAll('button').length).toBe(0);
    });

    it('hides action buttons for expired state', () => {
      const receipt = createReceipt({ is_expired: true });

      const wrapper = mountComponent(receipt);

      expect(wrapper.findAll('button').length).toBe(0);
    });
  });
});
