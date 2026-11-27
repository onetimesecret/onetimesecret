// src/tests/apps/secret/components/receipt/ReceiptFAQ.spec.ts

import ReceiptFAQ from '@/apps/secret/components/receipt/ReceiptFAQ.vue';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

const burnKeys = [
  'web.receipt.what_happens_when_i_burn_a_secret',
  'web.receipt.whats_the_burn_feature',
];

const mountFaq = (showSecret: boolean, capabilities: Record<string, boolean>) =>
  mount(ReceiptFAQ, {
    props: {
      record: { natural_expiration: '7 days' } as never,
      details: { show_secret: showSecret, show_secret_link: true } as never,
    },
    global: {
      plugins: [
        createTestI18n(),
        createTestingPinia({
          createSpy: vi.fn,
          initialState: { bootstrap: { ui: { capabilities } } },
        }),
      ],
      stubs: { RouterLink: true },
    },
  });

describe('ReceiptFAQ burn entries', () => {
  it.each([true, false])('explains burning when burn is enabled (show_secret=%s)', (showSecret) => {
    const html = mountFaq(showSecret, {}).html();
    expect(burnKeys.some((key) => html.includes(key))).toBe(true);
  });

  it.each([true, false])('says nothing about burning when burn is off (show_secret=%s)', (showSecret) => {
    const html = mountFaq(showSecret, { burn: false }).html();
    burnKeys.forEach((key) => expect(html).not.toContain(key));
  });
});
