// src/tests/composables/useRecentSecrets.spec.ts

import type { ReceiptRecords } from '@/schemas/api/account/endpoints/recent';
import type { LocalReceipt } from '@/types/ui/local-receipt';
import { createTestingPinia } from '@pinia/testing';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp, nextTick, ref } from 'vue';

// Mock useAsyncHandler before other mocks since it uses useI18n internally
vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: () => ({
    wrap: vi.fn(async <T>(fn: () => Promise<T>) => await fn()),
  }),
}));

// Mock the stores before importing the composable
vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: vi.fn(() => ({
    isFullyAuthenticated: false,
  })),
}));

vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: vi.fn(() => ({
    show: vi.fn(),
  })),
}));

// Create mock store states that we can control
const mockConcealedMessages = ref<LocalReceipt[]>([]);
const mockWorkspaceMode = ref(false);
const mockHasMessages = ref(false);
const mockIsInitialized = ref(false);

vi.mock('@/shared/stores/localReceiptStore', () => ({
  useLocalReceiptStore: vi.fn(() => ({
    localReceipts: mockConcealedMessages,
    workspaceMode: mockWorkspaceMode,
    hasReceipts: mockHasMessages,
    isInitialized: mockIsInitialized.value,
    init: vi.fn(() => {
      mockIsInitialized.value = true;
    }),
    clearReceipts: vi.fn(() => {
      mockConcealedMessages.value = [];
      mockHasMessages.value = false;
    }),
    toggleWorkspaceMode: vi.fn(() => {
      mockWorkspaceMode.value = !mockWorkspaceMode.value;
    }),
    refreshReceiptStatuses: vi.fn(),
  })),
}));

const mockApiRecords = ref<ReceiptRecords[]>([]);

vi.mock('@/shared/stores/receiptListStore', () => ({
  useReceiptListStore: vi.fn(() => ({
    records: mockApiRecords,
    fetchList: vi.fn(),
    $reset: vi.fn(() => {
      mockApiRecords.value = [];
    }),
  })),
}));

// Import the composable after mocks are set up
import { useRecentSecrets, type RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import { useAuthStore } from '@/shared/stores/authStore';

/**
 * Creates a mock LocalReceipt for local (guest) mode testing.
 */
function createMockLocalReceipt(
  overrides: Partial<LocalReceipt> = {}
): LocalReceipt {
  const id = overrides.id ?? `local-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  return {
    id,
    receiptExtid: overrides.receiptExtid ?? `receipt-${id}`,
    receiptShortid: overrides.receiptShortid ?? id.slice(0, 8),
    secretExtid: overrides.secretExtid ?? `secret-${id}`,
    secretShortid: overrides.secretShortid ?? `sec-${id.slice(0, 5)}`,
    shareDomain: overrides.shareDomain ?? null,
    hasPassphrase: overrides.hasPassphrase ?? false,
    ttl: overrides.ttl ?? 3600,
    createdAt: overrides.createdAt ?? Date.now(),
  };
}

/**
 * Creates a mock ReceiptRecords for API (authenticated) mode testing.
 */
function createMockApiRecord(overrides: Partial<ReceiptRecords> = {}): ReceiptRecords {
  const now = new Date();
  return {
    key: overrides.key ?? `api-key-${Date.now()}`,
    shortid: overrides.shortid ?? 'shortid1',
    identifier: overrides.identifier ?? `api-identifier-${Date.now()}`,
    secret_identifier: overrides.secret_identifier ?? `secret-identifier-${Date.now()}`,
    secret_shortid: overrides.secret_shortid ?? 'sec-short',
    state: overrides.state ?? 'new',
    created: overrides.created ?? now,
    updated: overrides.updated ?? now,
    is_previewed: overrides.is_previewed ?? false,
    is_revealed: overrides.is_revealed ?? false,
    is_burned: overrides.is_burned ?? false,
    is_destroyed: overrides.is_destroyed ?? false,
    is_expired: overrides.is_expired ?? false,
    is_orphaned: overrides.is_orphaned ?? false,
    has_passphrase: overrides.has_passphrase ?? false,
    secret_ttl: overrides.secret_ttl ?? 3600,
    share_domain: overrides.share_domain ?? undefined,
    receipt_ttl: overrides.receipt_ttl ?? 0,
    lifespan: overrides.lifespan ?? 0,
    show_recipients: overrides.show_recipients ?? false,
    custid: overrides.custid ?? 'test-customer',
    owner_id: overrides.owner_id ?? 'test-owner',
  } as ReceiptRecords;
}

describe('useRecentSecrets', () => {
  beforeEach(() => {
    // Reset mock states
    mockConcealedMessages.value = [];
    mockWorkspaceMode.value = false;
    mockHasMessages.value = false;
    mockIsInitialized.value = false;
    mockApiRecords.value = [];

    // Default to unauthenticated
    vi.mocked(useAuthStore).mockReturnValue({
      isFullyAuthenticated: false,
    } as any);

    const app = createApp({});
    const pinia = createTestingPinia({ stubActions: false });
    app.use(pinia);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('transformLocalRecord', () => {
    it('correctly transforms LocalReceipt to RecentSecretRecord', async () => {
      const now = Date.now();
      const localMessage = createMockLocalReceipt({
        id: 'local-123',
        receiptExtid: 'receipt-extid-abc',
        receiptShortid: 'rcpt1234',
        secretExtid: 'secret-extid-xyz',
        secretShortid: 'sec12345',
        shareDomain: 'custom.example.com',
        hasPassphrase: true,
        ttl: 7200,
        createdAt: now,
      });

      mockConcealedMessages.value = [localMessage];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      const record = records.value[0];

      expect(record).toBeDefined();
      expect(record.id).toBe('local-123');
      expect(record.extid).toBe('receipt-extid-abc');
      expect(record.shortid).toBe('sec12345'); // Uses secretShortid for display, not receiptShortid
      expect(record.secretExtid).toBe('secret-extid-xyz');
      expect(record.hasPassphrase).toBe(true);
      expect(record.ttl).toBe(7200);
      expect(record.shareDomain).toBe('custom.example.com');
      expect(record.createdAt).toBeInstanceOf(Date);
      expect(record.source).toBe('local');
    });

    it('handles null shareDomain correctly', async () => {
      const localMessage = createMockLocalReceipt({
        id: 'null-domain-test',
        shareDomain: null,
      });

      mockConcealedMessages.value = [localMessage];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      expect(records.value[0].shareDomain).toBeUndefined();
    });

    it('local records default to isPreviewed=false, isRevealed=false, isBurned=false', async () => {
      mockConcealedMessages.value = [createMockLocalReceipt()];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      const record = records.value[0];
      expect(record.isPreviewed).toBe(false);
      expect(record.isRevealed).toBe(false);
      expect(record.isBurned).toBe(false);
    });

    it('preserves original LocalReceipt in originalRecord field', async () => {
      const localMessage = createMockLocalReceipt({ id: 'original-test' });
      mockConcealedMessages.value = [localMessage];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      // Use toStrictEqual since the object is deeply copied via computed
      expect(records.value[0].originalRecord).toStrictEqual(localMessage);
    });
  });

  describe('expired detection for local records', () => {
    it('calculates isExpired=true when createdAt + ttl < now', async () => {
      const twoHoursAgo = Date.now() - 7200 * 1000;
      const expiredMessage = createMockLocalReceipt({
        id: 'expired-test',
        createdAt: twoHoursAgo,
        ttl: 3600, // 1 hour TTL, but created 2 hours ago
      });

      mockConcealedMessages.value = [expiredMessage];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      expect(records.value[0].isExpired).toBe(true);
    });

    it('calculates isExpired=false when createdAt + ttl > now', async () => {
      const now = Date.now();
      const validMessage = createMockLocalReceipt({
        id: 'valid-test',
        createdAt: now,
        ttl: 3600, // 1 hour TTL
      });

      mockConcealedMessages.value = [validMessage];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      expect(records.value[0].isExpired).toBe(false);
    });

    it('handles edge case where TTL just expired', async () => {
      const justExpired = Date.now() - 1000; // 1 second ago
      const message = createMockLocalReceipt({
        id: 'just-expired',
        createdAt: justExpired - 3600 * 1000, // Created 1 hour + 1 second ago
        ttl: 3600, // 1 hour TTL
      });

      mockConcealedMessages.value = [message];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      expect(records.value[0].isExpired).toBe(true);
    });
  });

  describe('transformApiRecord', () => {
    it('uses secret_identifier when available (preferred over secret_shortid)', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      const apiRecord = createMockApiRecord({
        secret_identifier: 'full-secret-identifier-abc123',
        secret_shortid: 'short-id',
      });

      mockApiRecords.value = [apiRecord];

      const { records } = useRecentSecrets();
      await nextTick();

      // secretExtid should use secret_identifier
      expect(records.value[0].secretExtid).toBe('full-secret-identifier-abc123');
    });

    it('falls back to secret_shortid when secret_identifier is missing', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      // Create a record without secret_identifier by setting it to null
      const apiRecord = createMockApiRecord({
        secret_shortid: 'fallback-shortid',
      });
      // Explicitly set to null/undefined to trigger fallback
      (apiRecord as any).secret_identifier = null;

      mockApiRecords.value = [apiRecord];

      const { records } = useRecentSecrets();
      await nextTick();

      expect(records.value[0].secretExtid).toBe('fallback-shortid');
    });

    it('correctly transforms API record boolean flags', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      const apiRecord = createMockApiRecord({
        is_previewed: true,
        is_revealed: true,
        is_burned: false,
        is_expired: true,
      });

      mockApiRecords.value = [apiRecord];

      const { records } = useRecentSecrets();
      await nextTick();

      const record = records.value[0];
      expect(record.isPreviewed).toBe(true);
      expect(record.isRevealed).toBe(true);
      expect(record.isBurned).toBe(false);
      expect(record.isExpired).toBe(true);
    });

    it('keeps isBurned and isDestroyed as separate states', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      const apiRecord = createMockApiRecord({
        is_burned: false,
        is_destroyed: true,
      });

      mockApiRecords.value = [apiRecord];

      const { records } = useRecentSecrets();
      await nextTick();

      // isBurned should only reflect is_burned, not is_destroyed
      // is_destroyed can be true for received, burned, expired, or orphaned states
      expect(records.value[0].isBurned).toBe(false);
      expect(records.value[0].isDestroyed).toBe(true);
    });

    it('filters out records with missing secret_shortid', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      const validRecord = createMockApiRecord({
        identifier: 'valid-record',
        secret_shortid: 'has-shortid',
      });

      const invalidRecord = createMockApiRecord({
        identifier: 'invalid-record',
      });
      // Explicitly remove secret_shortid to trigger filtering
      (invalidRecord as any).secret_shortid = '';

      mockApiRecords.value = [validRecord, invalidRecord];

      const { records } = useRecentSecrets();
      await nextTick();

      expect(records.value.length).toBe(1);
      expect(records.value[0].extid).toBe('valid-record');
    });
  });

  describe('mode switching (authenticated vs guest)', () => {
    it('uses local source when not authenticated', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: false,
      } as any);

      mockConcealedMessages.value = [createMockLocalReceipt({ id: 'local-1' })];
      mockHasMessages.value = true;
      mockApiRecords.value = [createMockApiRecord({ identifier: 'api-1' })];

      const { records, isAuthenticated } = useRecentSecrets();
      await nextTick();

      expect(isAuthenticated.value).toBe(false);
      expect(records.value.length).toBe(1);
      expect(records.value[0].source).toBe('local');
      expect(records.value[0].id).toBe('local-1');
    });

    it('uses API source when authenticated', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      mockConcealedMessages.value = [createMockLocalReceipt({ id: 'local-1' })];
      mockHasMessages.value = true;
      mockApiRecords.value = [
        createMockApiRecord({
          shortid: 'api-short-1',
          secret_shortid: 'sec-1',
        }),
      ];

      const { records, isAuthenticated } = useRecentSecrets();
      await nextTick();

      expect(isAuthenticated.value).toBe(true);
      expect(records.value.length).toBe(1);
      expect(records.value[0].source).toBe('api');
    });

    it('workspaceMode is available only in local mode', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: false,
      } as any);

      mockWorkspaceMode.value = true;

      const { workspaceMode } = useRecentSecrets();
      await nextTick();

      expect(workspaceMode.value).toBe(true);
    });

    it('workspaceMode is always false in API mode', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      mockWorkspaceMode.value = true; // This shouldn't matter in API mode

      const { workspaceMode } = useRecentSecrets();
      await nextTick();

      expect(workspaceMode.value).toBe(false);
    });
  });

  describe('hasRecords computed', () => {
    it('returns true when local records exist in guest mode', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: false,
      } as any);

      mockConcealedMessages.value = [createMockLocalReceipt()];
      mockHasMessages.value = true;

      const { hasRecords } = useRecentSecrets();
      await nextTick();

      expect(hasRecords.value).toBe(true);
    });

    it('returns false when no local records in guest mode', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: false,
      } as any);

      mockConcealedMessages.value = [];
      mockHasMessages.value = false;

      const { hasRecords } = useRecentSecrets();
      await nextTick();

      expect(hasRecords.value).toBe(false);
    });

    it('returns true when API records exist in authenticated mode', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      mockApiRecords.value = [
        createMockApiRecord({ secret_shortid: 'sec-1' }),
      ];

      const { hasRecords } = useRecentSecrets();
      await nextTick();

      expect(hasRecords.value).toBe(true);
    });

    it('returns false when API records exist but all lack secret_shortid', async () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isFullyAuthenticated: true,
      } as any);

      // Create records and explicitly remove secret_shortid
      const record1 = createMockApiRecord({});
      const record2 = createMockApiRecord({});
      (record1 as any).secret_shortid = '';
      (record2 as any).secret_shortid = '';

      mockApiRecords.value = [record1, record2];

      const { hasRecords } = useRecentSecrets();
      await nextTick();

      // Records without secret_shortid are filtered out
      expect(hasRecords.value).toBe(false);
    });
  });

  describe('RecentSecretRecord structure', () => {
    it('has all required fields for display', async () => {
      mockConcealedMessages.value = [createMockLocalReceipt()];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      const record: RecentSecretRecord = records.value[0];

      // All fields that UI components expect
      expect(record).toHaveProperty('id');
      expect(record).toHaveProperty('extid');
      expect(record).toHaveProperty('shortid');
      expect(record).toHaveProperty('secretExtid');
      expect(record).toHaveProperty('hasPassphrase');
      expect(record).toHaveProperty('ttl');
      expect(record).toHaveProperty('createdAt');
      expect(record).toHaveProperty('shareDomain');
      expect(record).toHaveProperty('isPreviewed');
      expect(record).toHaveProperty('isRevealed');
      expect(record).toHaveProperty('isBurned');
      expect(record).toHaveProperty('isExpired');
      expect(record).toHaveProperty('source');
      expect(record).toHaveProperty('originalRecord');
    });

    it('createdAt is always a Date object', async () => {
      const timestamp = Date.now();
      mockConcealedMessages.value = [
        createMockLocalReceipt({ createdAt: timestamp }),
      ];
      mockHasMessages.value = true;

      const { records } = useRecentSecrets();
      await nextTick();

      expect(records.value[0].createdAt).toBeInstanceOf(Date);
      expect(records.value[0].createdAt.getTime()).toBe(timestamp);
    });
  });

  describe('return type completeness', () => {
    it('returns all expected properties', async () => {
      const result = useRecentSecrets();

      expect(result).toHaveProperty('records');
      expect(result).toHaveProperty('isLoading');
      expect(result).toHaveProperty('error');
      expect(result).toHaveProperty('hasRecords');
      expect(result).toHaveProperty('fetch');
      expect(result).toHaveProperty('clear');
      expect(result).toHaveProperty('workspaceMode');
      expect(result).toHaveProperty('toggleWorkspaceMode');
      expect(result).toHaveProperty('isAuthenticated');
    });

    it('fetch is a callable function', async () => {
      const { fetch } = useRecentSecrets();
      expect(typeof fetch).toBe('function');
    });

    it('clear is a callable function', async () => {
      const { clear } = useRecentSecrets();
      expect(typeof clear).toBe('function');
    });

    it('toggleWorkspaceMode is a callable function', async () => {
      const { toggleWorkspaceMode } = useRecentSecrets();
      expect(typeof toggleWorkspaceMode).toBe('function');
    });
  });
});
