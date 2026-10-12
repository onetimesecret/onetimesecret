// src/tests/stores/localReceiptStore.spec.ts

import { useLocalReceiptStore } from '@/shared/stores/localReceiptStore';
import type { LocalReceipt } from '@/types/ui/local-receipt';
import { createTestingPinia } from '@pinia/testing';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp, nextTick } from 'vue';

// Signed-in state is the only thing this store reads from authStore. Reactive,
// so the store's sign-in watch sees changes.
const authState = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  return reactive({ isFullyAuthenticated: false });
});
vi.mock('@/shared/stores/authStore', () => ({ useAuthStore: () => authState }));

/**
 * Creates a mock LocalReceipt with required minimal fields.
 * Follows the data minimization pattern - only essential fields for guest users.
 */
function createMockMessage(overrides: Partial<LocalReceipt> = {}): LocalReceipt {
  const id = overrides.id ?? `msg-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  return {
    id,
    receiptExtid: overrides.receiptExtid ?? `receipt-extid-${id}`,
    receiptShortid: overrides.receiptShortid ?? id.slice(0, 8),
    secretExtid: overrides.secretExtid ?? `secret-extid-${id}`,
    secretShortid: overrides.secretShortid ?? `sec-${id.slice(0, 5)}`,
    shareDomain: overrides.shareDomain ?? null,
    hasPassphrase: overrides.hasPassphrase ?? false,
    ttl: overrides.ttl ?? 3600, // 1 hour default
    createdAt: overrides.createdAt ?? Date.now(),
  };
}

describe('localReceiptStore', () => {
  let store: ReturnType<typeof useLocalReceiptStore>;
  let mockSessionStorage: Record<string, string>;

  beforeEach(() => {
    authState.isFullyAuthenticated = false;

    // Create a mock sessionStorage
    mockSessionStorage = {};

    vi.stubGlobal('sessionStorage', {
      getItem: vi.fn((key: string) => mockSessionStorage[key] ?? null),
      setItem: vi.fn((key: string, value: string) => {
        mockSessionStorage[key] = value;
      }),
      removeItem: vi.fn((key: string) => {
        delete mockSessionStorage[key];
      }),
      clear: vi.fn(() => {
        mockSessionStorage = {};
      }),
    });

    // Mock localStorage for workspace mode preference
    vi.stubGlobal('localStorage', {
      getItem: vi.fn(() => null),
      setItem: vi.fn(),
      removeItem: vi.fn(),
    });

    const app = createApp({});
    const pinia = createTestingPinia({ stubActions: false });
    app.use(pinia);
    store = useLocalReceiptStore();
  });

  afterEach(() => {
    store.$reset();
    vi.clearAllMocks();
    vi.unstubAllGlobals();
  });

  describe('initialization', () => {
    it('initializes with empty messages when sessionStorage is empty', () => {
      expect(store.localReceipts).toEqual([]);
      expect(store.hasReceipts).toBe(false);
      expect(store.isInitialized).toBe(false);
    });

    it('marks store as initialized after init() call', () => {
      store.init();
      expect(store.isInitialized).toBe(true);
    });

    it('init() is idempotent - subsequent calls have no effect', () => {
      const result1 = store.init();
      const result2 = store.init();

      expect(result1.isInitialized).toBe(result2.isInitialized);
    });
  });

  describe('storage limits (MAX_STORED_RECEIPTS = 25)', () => {
    it('enforces maximum of 25 stored messages', async () => {
      // Add 30 messages
      for (let i = 0; i < 30; i++) {
        store.addReceipt(createMockMessage({ id: `msg-${i}` }));
      }

      await nextTick();

      // Should only keep 25 messages
      expect(store.localReceipts.length).toBe(25);
    });

    it('keeps most recent messages when limit is exceeded', async () => {
      // Add 30 messages with sequential IDs
      for (let i = 0; i < 30; i++) {
        store.addReceipt(createMockMessage({ id: `msg-${i}` }));
      }

      await nextTick();

      // Most recent message (msg-29) should be first
      expect(store.localReceipts[0].id).toBe('msg-29');
      // Oldest retained message should be msg-5 (30 - 25 = 5)
      expect(store.localReceipts[24].id).toBe('msg-5');
      // msg-0 through msg-4 should have been dropped
      const ids = store.localReceipts.map((m) => m.id);
      expect(ids).not.toContain('msg-0');
      expect(ids).not.toContain('msg-4');
    });

    it('new messages are added to the beginning of the list', async () => {
      store.addReceipt(createMockMessage({ id: 'first' }));
      store.addReceipt(createMockMessage({ id: 'second' }));
      store.addReceipt(createMockMessage({ id: 'third' }));

      await nextTick();

      expect(store.localReceipts[0].id).toBe('third');
      expect(store.localReceipts[1].id).toBe('second');
      expect(store.localReceipts[2].id).toBe('first');
    });
  });

  describe('expired entry filtering on load', () => {
    it('filters out expired entries when loading from sessionStorage', () => {
      const now = Date.now();
      const oneHourAgo = now - 3600 * 1000;
      const twoHoursAgo = now - 7200 * 1000;

      // Pre-populate sessionStorage with mixed expired/valid entries
      const storedMessages: LocalReceipt[] = [
        // Valid: created 1 hour ago, TTL 2 hours (1 hour remaining)
        createMockMessage({
          id: 'valid-1',
          createdAt: oneHourAgo,
          ttl: 7200,
        }),
        // Expired: created 2 hours ago, TTL 1 hour (expired 1 hour ago)
        createMockMessage({
          id: 'expired-1',
          createdAt: twoHoursAgo,
          ttl: 3600,
        }),
        // Valid: created just now, TTL 1 hour
        createMockMessage({
          id: 'valid-2',
          createdAt: now,
          ttl: 3600,
        }),
        // Expired: created 2 hours ago, TTL 30 minutes
        createMockMessage({
          id: 'expired-2',
          createdAt: twoHoursAgo,
          ttl: 1800,
        }),
      ];

      mockSessionStorage['onetimeReceiptCache'] = JSON.stringify(storedMessages);

      // Create a fresh store to trigger loadFromStorage
      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      const freshStore = useLocalReceiptStore();

      // Should only have the 2 valid entries
      expect(freshStore.localReceipts.length).toBe(2);
      const ids = freshStore.localReceipts.map((m) => m.id);
      expect(ids).toContain('valid-1');
      expect(ids).toContain('valid-2');
      expect(ids).not.toContain('expired-1');
      expect(ids).not.toContain('expired-2');
    });

    it('handles empty sessionStorage gracefully', () => {
      mockSessionStorage['onetimeReceiptCache'] = '';

      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      const freshStore = useLocalReceiptStore();

      expect(freshStore.localReceipts).toEqual([]);
    });

    it('handles malformed JSON in sessionStorage gracefully', () => {
      mockSessionStorage['onetimeReceiptCache'] = 'not valid json{{{';

      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      const freshStore = useLocalReceiptStore();

      // Should fallback to empty array
      expect(freshStore.localReceipts).toEqual([]);
    });

    // SEC-F4: an unreadable cache may be a previous release's entries,
    // secret identifiers included; it is removed rather than left in place.
    it('removes a cache that is not valid JSON', () => {
      const truncated = JSON.stringify([
        createMockMessage({ id: 'old', secretExtid: 'pre-upgrade-bearer' }),
      ]).slice(0, -1);
      mockSessionStorage['onetimeReceiptCache'] = truncated;

      const app = createApp({});
      app.use(createTestingPinia({ stubActions: false }));
      const freshStore = useLocalReceiptStore();

      expect(freshStore.localReceipts).toEqual([]);
      expect(sessionStorage.removeItem).toHaveBeenCalledWith('onetimeReceiptCache');
      expect(mockSessionStorage['onetimeReceiptCache']).toBeUndefined();
    });
  });

  describe('deduplication', () => {
    it('replaces existing message with same ID instead of duplicating', async () => {
      const originalMessage = createMockMessage({
        id: 'duplicate-test',
        hasPassphrase: false,
        ttl: 3600,
      });

      const updatedMessage = createMockMessage({
        id: 'duplicate-test',
        hasPassphrase: true,
        ttl: 7200,
      });

      store.addReceipt(originalMessage);
      await nextTick();
      expect(store.localReceipts.length).toBe(1);
      expect(store.localReceipts[0].hasPassphrase).toBe(false);

      store.addReceipt(updatedMessage);
      await nextTick();

      // Should still only have 1 message
      expect(store.localReceipts.length).toBe(1);
      // Should be the updated version
      expect(store.localReceipts[0].hasPassphrase).toBe(true);
      expect(store.localReceipts[0].ttl).toBe(7200);
    });

    it('moves updated message to front of list', async () => {
      store.addReceipt(createMockMessage({ id: 'first' }));
      store.addReceipt(createMockMessage({ id: 'second' }));
      store.addReceipt(createMockMessage({ id: 'third' }));

      await nextTick();
      expect(store.localReceipts[0].id).toBe('third');

      // Update 'first' message - it should move to front
      store.addReceipt(createMockMessage({ id: 'first', hasPassphrase: true }));

      await nextTick();
      expect(store.localReceipts[0].id).toBe('first');
      expect(store.localReceipts[0].hasPassphrase).toBe(true);
      expect(store.localReceipts.length).toBe(3);
    });
  });

  describe('clear functionality', () => {
    it('clearReceipts() empties the store', async () => {
      store.addReceipt(createMockMessage({ id: 'msg-1' }));
      store.addReceipt(createMockMessage({ id: 'msg-2' }));

      await nextTick();
      expect(store.localReceipts.length).toBe(2);
      expect(store.hasReceipts).toBe(true);

      store.clearReceipts();

      await nextTick();
      expect(store.localReceipts.length).toBe(0);
      expect(store.hasReceipts).toBe(false);
    });

    it('clearReceipts() removes data from sessionStorage', async () => {
      store.addReceipt(createMockMessage({ id: 'msg-1' }));
      await nextTick();

      store.clearReceipts();
      await nextTick();

      expect(sessionStorage.removeItem).toHaveBeenCalledWith('onetimeReceiptCache');
    });

    it('$reset() clears messages and resets initialization state', async () => {
      store.init();
      store.addReceipt(createMockMessage({ id: 'msg-1' }));
      store.setWorkspaceMode(true);

      await nextTick();
      expect(store.isInitialized).toBe(true);
      expect(store.workspaceMode).toBe(true);
      expect(store.hasReceipts).toBe(true);

      store.$reset();

      await nextTick();
      expect(store.isInitialized).toBe(false);
      expect(store.workspaceMode).toBe(false);
      expect(store.hasReceipts).toBe(false);
    });
  });

  describe('sessionStorage persistence', () => {
    it('persists messages to sessionStorage when added', async () => {
      const message = createMockMessage({ id: 'persist-test' });
      store.addReceipt(message);

      await nextTick();

      expect(sessionStorage.setItem).toHaveBeenCalledWith(
        'onetimeReceiptCache',
        expect.stringContaining('persist-test')
      );
    });

    it('persists the correct JSON structure', async () => {
      const STRUCTURE_CREATED_AT = Date.now();
      const message = createMockMessage({
        id: 'structure-test',
        receiptExtid: 'receipt-ext-123',
        receiptShortid: 'rcpt1234',
        secretExtid: 'secret-ext-456',
        secretShortid: 'sec12345',
        shareDomain: 'custom.example.com',
        hasPassphrase: true,
        ttl: 7200,
        createdAt: STRUCTURE_CREATED_AT,
      });

      store.addReceipt(message);
      await nextTick();

      const setItemCall = vi.mocked(sessionStorage.setItem).mock.calls.find(
        (call) => call[0] === 'onetimeReceiptCache'
      );

      expect(setItemCall).toBeDefined();
      const savedData = JSON.parse(setItemCall![1]);

      expect(savedData[0]).toEqual({
        id: 'structure-test',
        receiptExtid: 'receipt-ext-123',
        receiptShortid: 'rcpt1234',
        secretShortid: 'sec12345',
        shareDomain: 'custom.example.com',
        hasPassphrase: true,
        ttl: 7200,
        createdAt: STRUCTURE_CREATED_AT,
      });
    });
  });

  describe('workspace mode', () => {
    it('defaults to false', () => {
      expect(store.workspaceMode).toBe(false);
    });

    it('setWorkspaceMode updates the preference', () => {
      store.setWorkspaceMode(true);
      expect(store.workspaceMode).toBe(true);

      store.setWorkspaceMode(false);
      expect(store.workspaceMode).toBe(false);
    });

    it('toggleWorkspaceMode toggles the preference', () => {
      expect(store.workspaceMode).toBe(false);

      store.toggleWorkspaceMode();
      expect(store.workspaceMode).toBe(true);

      store.toggleWorkspaceMode();
      expect(store.workspaceMode).toBe(false);
    });

    it('persists workspace mode to localStorage', async () => {
      store.setWorkspaceMode(true);
      await nextTick();

      expect(localStorage.setItem).toHaveBeenCalledWith('onetimeWorkspaceMode', 'true');
    });
  });

  describe('preferred TTL', () => {
    it('defaults to null when unset', () => {
      expect(store.preferredTtl).toBeNull();
    });

    it('setPreferredTtl updates the preference', () => {
      store.setPreferredTtl(3600);
      expect(store.preferredTtl).toBe(3600);
    });

    it('persists preferred TTL to localStorage', async () => {
      store.setPreferredTtl(86400);
      await nextTick();

      expect(localStorage.setItem).toHaveBeenCalledWith('onetimePreferredTtl', '86400');
    });

    it('removes preferred TTL from localStorage on $reset', async () => {
      store.setPreferredTtl(86400);
      await nextTick();

      store.$reset();
      await nextTick();

      expect(store.preferredTtl).toBeNull();
      expect(localStorage.removeItem).toHaveBeenCalledWith('onetimePreferredTtl');
    });
  });

  describe('LocalReceipt minimal data structure', () => {
    it('only stores essential fields as defined in the interface', async () => {
      const message = createMockMessage({
        id: 'minimal-test',
        receiptExtid: 'receipt-extid-minimal',
        receiptShortid: 'rcpt1234',
        secretExtid: 'secret-extid-minimal',
        secretShortid: 'sec12345',
        shareDomain: null,
        hasPassphrase: false,
        ttl: 3600,
        createdAt: Date.now(),
      });

      store.addReceipt(message);
      await nextTick();

      const storedMessage = store.localReceipts[0];

      // Verify only the expected fields exist
      const allowedKeys = [
        'id',
        'receiptExtid',
        'receiptShortid',
        'secretExtid',
        'secretShortid',
        'shareDomain',
        'hasPassphrase',
        'ttl',
        'createdAt',
      ];

      const actualKeys = Object.keys(storedMessage);
      expect(actualKeys.sort()).toEqual(allowedKeys.sort());
    });

    it('does not store sensitive data like secret content', async () => {
      // Attempt to add a message with extra fields (simulating a bug or attack)
      const messageWithExtra = {
        ...createMockMessage({ id: 'no-sensitive-data' }),
        secretValue: 'THIS SHOULD NOT BE STORED',
        passphrase: 'SENSITIVE DATA',
        apiKey: 'secret-api-key',
      } as LocalReceipt;

      store.addReceipt(messageWithExtra);
      await nextTick();

      const setItemCall = vi.mocked(sessionStorage.setItem).mock.calls.find(
        (call) => call[0] === 'onetimeReceiptCache'
      );

      expect(setItemCall).toBeDefined();
      const savedJson = setItemCall![1];

      // Persistence goes through the stored schema, which drops every field
      // outside it.
      expect(savedJson).toContain('no-sensitive-data');
      expect(savedJson).not.toContain('THIS SHOULD NOT BE STORED');
      expect(savedJson).not.toContain('SENSITIVE DATA');
      expect(savedJson).not.toContain('secret-api-key');
    });
  });

  describe('edge cases', () => {
    it('handles storage errors gracefully', async () => {
      vi.mocked(sessionStorage.setItem).mockImplementation(() => {
        throw new Error('QuotaExceededError');
      });

      // Should not throw
      expect(() => {
        store.addReceipt(createMockMessage({ id: 'error-test' }));
      }).not.toThrow();

      await nextTick();

      // Message should still be added to memory
      expect(store.localReceipts.length).toBe(1);
    });

    it('handles null shareDomain correctly', async () => {
      const message = createMockMessage({
        id: 'null-domain',
        shareDomain: null,
      });

      store.addReceipt(message);
      await nextTick();

      expect(store.localReceipts[0].shareDomain).toBeNull();
    });

    it('handles custom shareDomain correctly', async () => {
      const message = createMockMessage({
        id: 'custom-domain',
        shareDomain: 'secrets.example.com',
      });

      store.addReceipt(message);
      await nextTick();

      expect(store.localReceipts[0].shareDomain).toBe('secrets.example.com');
    });

    it('handles zero TTL (immediate expiration)', () => {
      const now = Date.now();
      const storedMessages: LocalReceipt[] = [
        createMockMessage({
          id: 'zero-ttl',
          createdAt: now - 1000, // 1 second ago
          ttl: 0,
        }),
      ];

      mockSessionStorage['onetimeReceiptCache'] = JSON.stringify(storedMessages);

      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      const freshStore = useLocalReceiptStore();

      // Zero TTL message created in the past should be filtered out
      expect(freshStore.localReceipts.length).toBe(0);
    });
  });

  describe('status tracking (markAsPreviewed/markAsRevealed/markAsBurned)', () => {
    it('markAsPreviewed sets isPreviewed=true on matching message', async () => {
      const message = createMockMessage({
        id: 'previewed-test',
        secretExtid: 'secret-abc123',
      });

      store.addReceipt(message);
      await nextTick();

      expect(store.localReceipts[0].isPreviewed).toBeUndefined();

      store.markAsPreviewed('secret-abc123');
      await nextTick();

      expect(store.localReceipts[0].isPreviewed).toBe(true);
    });

    it('markAsRevealed sets isRevealed=true on matching message', async () => {
      const message = createMockMessage({
        id: 'revealed-test',
        secretExtid: 'secret-def456',
      });

      store.addReceipt(message);
      await nextTick();

      expect(store.localReceipts[0].isRevealed).toBeUndefined();

      store.markAsRevealed('secret-def456');
      await nextTick();

      expect(store.localReceipts[0].isRevealed).toBe(true);
    });

    it('markAsRevealed does nothing when secretExtid not found', async () => {
      const message = createMockMessage({
        id: 'no-match-test',
        secretExtid: 'secret-xyz789',
      });

      store.addReceipt(message);
      await nextTick();

      store.markAsRevealed('nonexistent-secret');
      await nextTick();

      expect(store.localReceipts[0].isRevealed).toBeUndefined();
    });

    it('markAsBurned sets isBurned=true on matching message', async () => {
      const message = createMockMessage({
        id: 'burn-test',
        secretExtid: 'secret-burn123',
      });

      store.addReceipt(message);
      await nextTick();

      expect(store.localReceipts[0].isBurned).toBeUndefined();

      store.markAsBurned('secret-burn123');
      await nextTick();

      expect(store.localReceipts[0].isBurned).toBe(true);
    });

    it('status changes are persisted to sessionStorage', async () => {
      const message = createMockMessage({
        id: 'persist-status',
        secretExtid: 'secret-persist',
      });

      store.addReceipt(message);
      await nextTick();

      store.markAsRevealed('secret-persist');
      await nextTick();

      const setItemCalls = vi.mocked(sessionStorage.setItem).mock.calls;
      const lastCall = setItemCalls[setItemCalls.length - 1];
      expect(lastCall[0]).toBe('onetimeReceiptCache');

      const savedData = JSON.parse(lastCall[1]);
      expect(savedData[0].isRevealed).toBe(true);
    });
  });

  // RISK-2026-08-14-M10: sessionStorage holds what is needed to list, refresh
  // and re-open receipts. The secret identifier (the share link's bearer key)
  // stays in memory for the page that created the secret.
  describe('capability persistence (M10)', () => {
    /** The receipts most recently written to sessionStorage. */
    function lastPersisted(): Record<string, unknown>[] {
      const calls = vi
        .mocked(sessionStorage.setItem)
        .mock.calls.filter((call) => call[0] === 'onetimeReceiptCache');
      expect(calls.length).toBeGreaterThan(0);
      return JSON.parse(calls[calls.length - 1][1]);
    }

    function freshStore() {
      const app = createApp({});
      const pinia = createTestingPinia({ stubActions: false });
      app.use(pinia);
      return useLocalReceiptStore();
    }

    it('keeps secretExtid in memory but never writes it to sessionStorage', async () => {
      store.addReceipt(createMockMessage({ id: 'mem-only', secretExtid: 'secret-bearer-key' }));
      await nextTick();

      expect(store.localReceipts[0].secretExtid).toBe('secret-bearer-key');
      expect(lastPersisted()[0]).not.toHaveProperty('secretExtid');
      expect(mockSessionStorage['onetimeReceiptCache']).not.toContain('secret-bearer-key');
    });

    it('loads entries written by older versions and drops their secretExtid', async () => {
      const legacy = createMockMessage({ id: 'legacy', secretExtid: 'legacy-bearer-key' });
      mockSessionStorage['onetimeReceiptCache'] = JSON.stringify([legacy]);

      const restored = freshStore();

      expect(restored.localReceipts).toHaveLength(1);
      expect(restored.localReceipts[0].id).toBe('legacy');
      expect(restored.localReceipts[0].receiptExtid).toBe(legacy.receiptExtid);
      expect(restored.localReceipts[0]).not.toHaveProperty('secretExtid');

      // Storage is scrubbed on load, not only on the next change.
      expect(mockSessionStorage['onetimeReceiptCache']).not.toContain('legacy-bearer-key');
      expect(lastPersisted()[0]).toMatchObject({ id: 'legacy' });

      // Later writes keep it out.
      restored.updateMemo('legacy', 'note');
      await nextTick();
      expect(mockSessionStorage['onetimeReceiptCache']).not.toContain('legacy-bearer-key');
      expect(lastPersisted()[0]).toMatchObject({ id: 'legacy', memo: 'note' });
    });

    it('does not match restored entries by secret identifier', () => {
      const legacy = createMockMessage({ id: 'restored', secretExtid: 'restored-key' });
      mockSessionStorage['onetimeReceiptCache'] = JSON.stringify([legacy]);

      const restored = freshStore();
      restored.markAsRevealed('restored-key');

      // Status for restored entries comes from refreshReceiptStatuses instead.
      expect(restored.localReceipts[0].isRevealed).toBeUndefined();
    });

    it('does not persist entries whose secret has expired', async () => {
      const now = Date.now();
      store.addReceipt(createMockMessage({ id: 'expired', createdAt: now - 7200 * 1000, ttl: 3600 }));
      store.addReceipt(createMockMessage({ id: 'live', createdAt: now, ttl: 3600 }));
      await nextTick();

      // Still listed (shown as expired) for this page...
      expect(store.localReceipts.map((r) => r.id)).toEqual(['live', 'expired']);
      // ...but not carried into sessionStorage.
      expect(lastPersisted().map((r) => r.id)).toEqual(['live']);
    });

    it('records nothing for a signed-in user, whose list comes from the API', async () => {
      authState.isFullyAuthenticated = true;

      store.addReceipt(createMockMessage({ id: 'signed-in' }));
      await nextTick();

      expect(store.localReceipts).toEqual([]);
      expect(mockSessionStorage['onetimeReceiptCache']).toBeUndefined();
    });

    // SEC-F3: sign-in is an in-app navigation. The store clears guest
    // receipts itself, with no recent-secrets list mounted.
    it('clears guest receipts and their in-memory secret identifiers on sign-in', async () => {
      store.addReceipt(createMockMessage({ id: 'guest', secretExtid: 'guest-bearer' }));
      await nextTick();
      expect(store.localReceipts[0].secretExtid).toBe('guest-bearer');
      expect(mockSessionStorage['onetimeReceiptCache']).toContain('guest');

      authState.isFullyAuthenticated = true;

      expect(store.localReceipts).toEqual([]);
      expect(mockSessionStorage['onetimeReceiptCache']).toBeUndefined();
      await nextTick();
      // The persistence watcher does not write an empty cache back.
      expect(mockSessionStorage['onetimeReceiptCache']).toBeUndefined();
    });

    it('clears stored guest receipts when a page loads signed in', () => {
      mockSessionStorage['onetimeReceiptCache'] = JSON.stringify([
        createMockMessage({ id: 'left-by-guest' }),
      ]);
      authState.isFullyAuthenticated = true;

      const signedIn = freshStore();

      expect(signedIn.localReceipts).toEqual([]);
      expect(mockSessionStorage['onetimeReceiptCache']).toBeUndefined();
    });

    it('keeps receipts while signed out, and sign-out has nothing to clear', async () => {
      store.addReceipt(createMockMessage({ id: 'kept' }));
      await nextTick();

      authState.isFullyAuthenticated = false;

      expect(store.localReceipts.map((r) => r.id)).toEqual(['kept']);
    });
  });

  // SEC-F3 against the real auth and bootstrap stores: MFA-pending is still
  // a guest list (as in useRecentSecrets); full authentication clears it.
  describe('sign-in through the real auth store', () => {
    it('keeps receipts while MFA is pending and clears them once fully authenticated', async () => {
      vi.resetModules();
      vi.doUnmock('@/shared/stores/authStore');
      const { setupTestPinia } = await import('@tests/setup');
      const { useBootstrapStore } = await import('@/shared/stores/bootstrapStore');
      const { useLocalReceiptStore: useRealLocalReceiptStore } = await import(
        '@/shared/stores/localReceiptStore'
      );
      await setupTestPinia({ autoInit: false });
      const bootstrap = useBootstrapStore();
      bootstrap.authStatus = 'mfa_pending';

      const real = useRealLocalReceiptStore();
      real.addReceipt(createMockMessage({ id: 'during-mfa', secretExtid: 'mfa-bearer' }));
      await nextTick();
      expect(real.localReceipts.map((r) => r.id)).toEqual(['during-mfa']);

      bootstrap.authStatus = 'authenticated';
      await nextTick();

      expect(real.localReceipts).toEqual([]);
      expect(mockSessionStorage['onetimeReceiptCache']).toBeUndefined();
    });
  });
});
