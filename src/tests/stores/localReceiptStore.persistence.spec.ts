// src/tests/stores/localReceiptStore.persistence.spec.ts
//
// RISK-2026-08-14-M10 (QA): sessionStorage round trips for the guest receipt
// cache, run against the real sessionStorage global (jsdom's on Node 22,
// Node's own on Node 25+; see sessionStoragePrototype) and the real
// auth/bootstrap stores (localReceiptStore.spec.ts mocks both).
//
// Covers what that spec does not:
// - a cache written by the previous release (secretExtid, an unknown field,
//   status flags, a memo, an expired entry) is scrubbed on load, before any
//   later write;
// - an already-normalized cache is not rewritten on load;
// - a failed rewrite keeps the loaded list and the next write scrubs storage;
// - a reload drops the in-memory secret identifier but keeps everything the
//   status refresh and the receipt link need;
// - addReceipt follows the real auth status, matching the source
//   useRecentSecrets lists from (local unless fully authenticated).

import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useLocalReceiptStore } from '@/shared/stores/localReceiptStore';
import type { LocalReceipt } from '@/types/ui/local-receipt';
import { setupTestPinia } from '@tests/setup';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick } from 'vue';

const STORAGE_KEY = 'onetimeReceiptCache';
const HOUR = 3600;

type AuthStatus = 'anonymous' | 'authenticated' | 'mfa_pending';

/** A fresh page: new pinia and stores, same sessionStorage. */
async function loadPage(authStatus: AuthStatus = 'anonymous') {
  const { axiosMock } = await setupTestPinia({ autoInit: false });
  useBootstrapStore().authStatus = authStatus;
  return { store: useLocalReceiptStore(), axiosMock: axiosMock as AxiosMockAdapter };
}

function receipt(id: string, overrides: Partial<LocalReceipt> = {}): LocalReceipt {
  return {
    id,
    receiptExtid: `receipt-${id}`,
    receiptShortid: `r-${id}`.slice(0, 8),
    secretExtid: `bearer-${id}`,
    secretShortid: `s-${id}`.slice(0, 8),
    shareDomain: null,
    hasPassphrase: false,
    ttl: HOUR,
    createdAt: Date.now(),
    ...overrides,
  };
}

function storedRaw(): string | null {
  return sessionStorage.getItem(STORAGE_KEY);
}

function storedEntries(): Record<string, unknown>[] {
  return JSON.parse(storedRaw() ?? '[]');
}

/**
 * The prototype that really serves `sessionStorage.setItem`.
 *
 * Not `Storage.prototype`: on Node 25+ (CI runs .node-version, 26) Node
 * defines its own `sessionStorage` global, and vitest's jsdom environment only
 * replaces globals Node already has when they are on its KEYS list, which has
 * `Storage` but not `sessionStorage`. `Storage` is then jsdom's class while
 * `sessionStorage` is Node's object, so a spy on `Storage.prototype` sees no
 * call at all (on Node 22 the two agree, which is why it passed locally).
 */
function sessionStoragePrototype(): Storage {
  return Object.getPrototypeOf(sessionStorage) as Storage;
}

/** Spy on sessionStorage writes, wherever its setItem lives. */
function spyOnSessionSetItem() {
  return vi.spyOn(sessionStoragePrototype(), 'setItem');
}

/**
 * Prove a setItem spy intercepts sessionStorage writes, so a "not called"
 * assertion cannot pass only because the spy is on the wrong object.
 */
function expectInterceptsSessionWrites(setItem: ReturnType<typeof spyOnSessionSetItem>) {
  sessionStorage.setItem('qa-spy-probe', '1');
  expect(setItem).toHaveBeenCalledWith('qa-spy-probe', '1');
  sessionStorage.removeItem('qa-spy-probe');
}

describe('localReceiptStore sessionStorage persistence (M10)', () => {
  beforeEach(() => {
    sessionStorage.clear();
  });

  afterEach(() => {
    sessionStorage.clear();
    vi.restoreAllMocks();
  });

  describe('a cache written by the previous release', () => {
    const now = Date.now();
    const legacyCache = [
      {
        ...receipt('live-a', { createdAt: now - 60_000, memo: 'for Sam' }),
        isPreviewed: true,
        // A field the stored schema does not know about.
        legacyNote: 'unknown-field-value',
      },
      { ...receipt('live-b', { shareDomain: 'secrets.example.com', hasPassphrase: true }) },
      // Expired an hour ago.
      { ...receipt('expired', { createdAt: now - 2 * HOUR * 1000, ttl: HOUR }) },
    ];

    beforeEach(() => {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(legacyCache));
    });

    it('lists the live entries without their secret identifiers', async () => {
      const { store } = await loadPage();

      expect(store.localReceipts.map((r) => r.id)).toEqual(['live-a', 'live-b']);
      for (const r of store.localReceipts) {
        expect(r).not.toHaveProperty('secretExtid');
        expect(r).not.toHaveProperty('legacyNote');
      }
      // What the list, the status refresh and the receipt link rely on survives.
      expect(store.localReceipts[0]).toMatchObject({
        receiptExtid: 'receipt-live-a',
        memo: 'for Sam',
        isPreviewed: true,
      });
      expect(store.localReceipts[1]).toMatchObject({
        shareDomain: 'secrets.example.com',
        hasPassphrase: true,
      });
    });

    it('rewrites storage on load, before any later write', async () => {
      await loadPage();

      const raw = storedRaw()!;
      expect(raw).not.toContain('secretExtid');
      expect(raw).not.toContain('bearer-');
      expect(raw).not.toContain('legacyNote');
      expect(storedEntries().map((r) => r.id)).toEqual(['live-a', 'live-b']);
    });
  });

  it('does not rewrite a cache that is already in the stored form', async () => {
    const { store: first } = await loadPage();
    first.addReceipt(receipt('one'));
    await nextTick();
    const normalized = storedRaw();
    expect(normalized).not.toBeNull();

    const setItem = spyOnSessionSetItem();
    const { store } = await loadPage();

    expect(store.localReceipts.map((r) => r.id)).toEqual(['one']);
    expect(setItem.mock.calls.filter(([key]) => key === STORAGE_KEY)).toEqual([]);
    expect(storedRaw()).toBe(normalized);
    expectInterceptsSessionWrites(setItem);
  });

  it('keeps the loaded list when the rewrite fails, and scrubs on the next write', async () => {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify([receipt('legacy')]));
    const logError = vi.spyOn(loggingService, 'error').mockImplementation(() => {});
    // Fail only the receipt cache's first write: setupTestPinia mounts an app
    // and waits a tick, and any other storage write in that window would
    // otherwise take a one-shot throw meant for the rewrite.
    const realSetItem = sessionStoragePrototype().setItem;
    let failed = false;
    const setItem = spyOnSessionSetItem().mockImplementation(function (
      this: Storage,
      key: string,
      value: string
    ) {
      if (key === STORAGE_KEY && !failed) {
        failed = true;
        throw new DOMException('quota', 'QuotaExceededError');
      }
      realSetItem.call(this, key, value);
    });

    const { store } = await loadPage();

    expect(store.localReceipts.map((r) => r.id)).toEqual(['legacy']);
    expect(store.localReceipts[0]).not.toHaveProperty('secretExtid');
    expect(logError).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining('Failed to rewrite local receipts'),
      })
    );
    // The failed rewrite left the old value in place.
    expect(storedRaw()).toContain('bearer-legacy');

    setItem.mockRestore();
    store.updateMemo('legacy', 'note');
    await nextTick();

    expect(storedRaw()).not.toContain('bearer-legacy');
    expect(storedEntries()[0]).toMatchObject({ id: 'legacy', memo: 'note' });
  });

  it('clears a cache whose entries do not match the stored schema', async () => {
    const { receiptExtid: _missing, ...broken } = receipt('broken');
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify([receipt('fine'), broken]));
    vi.spyOn(loggingService, 'warn').mockImplementation(() => {});

    const { store } = await loadPage();

    expect(store.localReceipts).toEqual([]);
    expect(storedRaw()).toBeNull();
  });

  describe('across a reload', () => {
    it('keeps the receipt side and refreshes status by receipt identifier', async () => {
      const { store: before } = await loadPage();
      before.addReceipt(receipt('made-here'));
      await nextTick();
      expect(before.localReceipts[0].secretExtid).toBe('bearer-made-here');
      expect(storedRaw()).not.toContain('bearer-made-here');

      const { store: after, axiosMock } = await loadPage();
      const restored = after.localReceipts[0];
      expect(restored.secretExtid).toBeUndefined();
      expect(restored.receiptExtid).toBe('receipt-made-here');

      axiosMock.onPost('/api/v3/guest/receipts').reply((config) => {
        expect(JSON.parse(config.data)).toEqual({ identifiers: ['receipt-made-here'] });
        return [
          200,
          {
            count: 1,
            records: [
              {
                identifier: 'receipt-made-here',
                shortid: 'r-made-h',
                secret_shortid: 's-made-h',
                is_burned: true,
              },
            ],
          },
        ];
      });

      await expect(after.refreshReceiptStatuses()).resolves.toBe(true);
      expect(after.localReceipts[0].isBurned).toBe(true);
      await nextTick();
      expect(storedEntries()[0]).toMatchObject({ id: 'made-here', isBurned: true });
      expect(storedRaw()).not.toContain('bearer-made-here');
    });

    it('drops an entry that expired while the page was open on the next write', async () => {
      const { store } = await loadPage();
      const createdAt = Date.now();
      store.addReceipt(receipt('short', { ttl: 60, createdAt }));
      await nextTick();
      expect(storedEntries().map((r) => r.id)).toEqual(['short']);

      vi.spyOn(Date, 'now').mockReturnValue(createdAt + 61_000);
      store.addReceipt(receipt('later', { createdAt: createdAt + 61_000 }));
      await nextTick();

      // Still listed on this page (shown as expired)...
      expect(store.localReceipts.map((r) => r.id)).toEqual(['later', 'short']);
      // ...but no longer carried in sessionStorage.
      expect(storedEntries().map((r) => r.id)).toEqual(['later']);
    });
  });

  describe('addReceipt and the real auth status', () => {
    it('records nothing when fully authenticated and leaves storage alone', async () => {
      const { store } = await loadPage('authenticated');
      const setItem = spyOnSessionSetItem();

      store.addReceipt(receipt('signed-in'));
      await nextTick();

      expect(store.localReceipts).toEqual([]);
      expect(setItem).not.toHaveBeenCalled();
      expect(storedRaw()).toBeNull();
      expectInterceptsSessionWrites(setItem);
    });

    it.each<AuthStatus>(['anonymous', 'mfa_pending'])(
      'records the receipt when the status is %s (the list is local then)',
      async (status) => {
        const { store } = await loadPage(status);

        store.addReceipt(receipt(`as-${status}`));
        await nextTick();

        expect(store.localReceipts.map((r) => r.id)).toEqual([`as-${status}`]);
        expect(storedEntries().map((r) => r.id)).toEqual([`as-${status}`]);
      }
    );
  });
});
