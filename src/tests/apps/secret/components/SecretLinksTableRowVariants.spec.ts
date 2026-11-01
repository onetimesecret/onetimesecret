// src/tests/apps/secret/components/SecretLinksTableRowVariants.spec.ts
//
// RISK-2026-08-14-M10 (QA): the Timeline, Ledger and SlotMachine row variants
// get the same in-memory-only secret identifier as the Console variant
// (covered in SecretLinksTableRowConsole.spec.ts). A guest record restored
// from sessionStorage has no secretExtid: the row must not build a
// /secret/undefined link or offer a copy that does nothing, and must still
// link to the receipt page, which shows the share link.

import SecretLinksTableRowLedger from '@/apps/secret/components/SecretLinksTableRowLedger.vue';
import SecretLinksTableRowSlotMachine from '@/apps/secret/components/SecretLinksTableRowSlotMachine.vue';
import SecretLinksTableRowTimeline from '@/apps/secret/components/SecretLinksTableRowTimeline.vue';
import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Component } from 'vue';

vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({ push: vi.fn() })),
}));

const RouterLinkStub = {
  name: 'RouterLink',
  props: ['to'],
  template: '<a :href="to" data-test-id="router-link"><slot /></a>',
};

const OIconStub = { name: 'OIcon', template: '<span class="icon-stub" />' };

function createRecord(overrides: Partial<RecentSecretRecord> = {}): RecentSecretRecord {
  return {
    id: 'rec-1',
    extid: 'receipt-extid-1',
    shortid: 'sec12345',
    secretExtid: 'secret-extid-1',
    hasPassphrase: false,
    ttl: 3600,
    createdAt: new Date(),
    shareDomain: undefined,
    isPreviewed: false,
    isRevealed: false,
    isBurned: false,
    isExpired: false,
    isDestroyed: false,
    source: 'local',
    originalRecord: {} as RecentSecretRecord['originalRecord'],
    ...overrides,
  };
}

const variants: Array<[string, Component]> = [
  ['Timeline', SecretLinksTableRowTimeline],
  ['Ledger', SecretLinksTableRowLedger],
  ['SlotMachine', SecretLinksTableRowSlotMachine],
];

describe.each(variants)('SecretLinksTableRow%s share link (M10)', (_name, Row) => {
  let writeText: ReturnType<typeof vi.fn>;

  function mountRow(record: RecentSecretRecord) {
    return mount(Row, {
      props: { record, index: 1, isLast: true },
      global: {
        plugins: [
          createTestI18n(),
          createTestingPinia({
            createSpy: vi.fn,
            initialState: { bootstrap: { site_host: 'onetimesecret.com' } },
          }),
        ],
        stubs: { RouterLink: RouterLinkStub, OIcon: OIconStub, Transition: false },
      },
    });
  }

  /** The copy-to-clipboard button, found by its i18n title (the test i18n renders keys). */
  function copyButton(wrapper: ReturnType<typeof mountRow>) {
    return wrapper
      .findAll('button')
      .find((b) => b.attributes('title') === 'web.LABELS.copy_to_clipboard');
  }

  beforeEach(() => {
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        observe() {}
        disconnect() {}
      }
    );
    writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('offers open and copy for a record created on this page', async () => {
    const wrapper = mountRow(createRecord());

    const open = wrapper.find('a[target="_blank"]');
    expect(open.attributes('href')).toBe('https://onetimesecret.com/secret/secret-extid-1');

    const copy = copyButton(wrapper);
    expect(copy).toBeDefined();
    await copy!.trigger('click');
    expect(writeText).toHaveBeenCalledWith('https://onetimesecret.com/secret/secret-extid-1');
  });

  it('builds the link on the share domain when there is one', () => {
    const wrapper = mountRow(createRecord({ shareDomain: 'secrets.example.com' }));

    expect(wrapper.find('a[target="_blank"]').attributes('href')).toBe(
      'https://secrets.example.com/secret/secret-extid-1'
    );
  });

  it('drops open and copy for a record restored without a secret identifier', () => {
    const wrapper = mountRow(createRecord({ secretExtid: undefined }));

    expect(wrapper.find('a[target="_blank"]').exists()).toBe(false);
    expect(copyButton(wrapper)).toBeUndefined();
    expect(wrapper.html()).not.toContain('/secret/');
    expect(writeText).not.toHaveBeenCalled();
  });

  it('still links to the receipt page for a restored record', () => {
    const wrapper = mountRow(createRecord({ secretExtid: undefined }));

    const receiptLinks = wrapper
      .findAll('[data-test-id="router-link"]')
      .map((link) => link.attributes('href'));
    expect(receiptLinks).toContain('/receipt/receipt-extid-1');
  });
});
