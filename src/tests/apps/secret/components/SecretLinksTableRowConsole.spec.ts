// src/tests/apps/secret/components/SecretLinksTableRowConsole.spec.ts
//
// RISK-2026-08-14-M10: a guest's secret identifier is kept in memory only, so
// a record restored from sessionStorage after a reload has none. The row then
// offers the receipt page (which shows the share link) instead of building a
// broken /secret/undefined link.

import SecretLinksTableRowConsole from '@/apps/secret/components/SecretLinksTableRowConsole.vue';
import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({ push: vi.fn() })),
}));

const RouterLinkStub = {
  name: 'RouterLink',
  props: ['to'],
  template: '<a :href="to"><slot /></a>',
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

function mountRow(record: RecentSecretRecord) {
  return mount(SecretLinksTableRowConsole, {
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

describe('SecretLinksTableRowConsole share link (M10)', () => {
  let writeText: ReturnType<typeof vi.fn>;

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

  it('offers copy and open when the secret identifier is in memory', async () => {
    const wrapper = mountRow(createRecord());

    const open = wrapper.find('a[target="_blank"]');
    expect(open.attributes('href')).toBe('https://onetimesecret.com/secret/secret-extid-1');
    expect(wrapper.find('[data-test-id="receipt-fallback"]').exists()).toBe(false);

    const copy = wrapper.findAll('button').find((b) => b.text().includes('COPY'));
    await copy!.trigger('click');
    expect(writeText).toHaveBeenCalledWith('https://onetimesecret.com/secret/secret-extid-1');
  });

  it('links to the receipt instead when the record has no secret identifier', () => {
    const wrapper = mountRow(createRecord({ secretExtid: undefined }));

    const fallback = wrapper.find('[data-test-id="receipt-fallback"]');
    expect(fallback.exists()).toBe(true);
    expect(fallback.attributes('href')).toBe('/receipt/receipt-extid-1');
    expect(wrapper.find('a[target="_blank"]').exists()).toBe(false);
    expect(wrapper.html()).not.toContain('/secret/undefined');
    expect(wrapper.findAll('button').some((b) => b.text().includes('COPY'))).toBe(false);
  });
});
