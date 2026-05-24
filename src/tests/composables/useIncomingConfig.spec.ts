// src/tests/composables/useIncomingConfig.spec.ts
//
// Tests for the rewritten useIncomingConfig composable. Single-state
// architecture: formState holds plaintext {email, name} recipients that
// round-trip through the admin /incoming-config endpoint.

import { useIncomingConfig } from '@/shared/composables/useIncomingConfig';
import { createPinia, setActivePinia } from 'pinia';
import { nextTick } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  mockEmptyConfigResponse,
  mockMultipleRecipientsConfigResponse,
  mockSingleRecipientConfigResponse,
} from '../fixtures/incomingConfig.fixture';

// ---------------------------------------------------------------------------
// Mock setup
// ---------------------------------------------------------------------------

const mockGetConfig = vi.fn();
const mockPutConfig = vi.fn();
const mockDeleteConfig = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/services/incomingConfig.service', () => ({
  IncomingConfigService: {
    getConfigForDomain: (...args: unknown[]) => mockGetConfig(...args),
    putConfigForDomain: (...args: unknown[]) => mockPutConfig(...args),
    deleteConfigForDomain: (...args: unknown[]) => mockDeleteConfig(...args),
  },
}));

vi.mock('@/shared/stores', () => ({
  useNotificationsStore: () => ({
    show: mockNotificationsShow,
  }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: mockRouterPush,
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, params?: Record<string, unknown>) => {
      const translations: Record<string, string> = {
        'web.domains.incoming.update_success': 'Recipients updated',
        'web.domains.incoming.delete_success': 'Recipients cleared',
        'web.domains.incoming.max_recipients_reached': `Maximum ${params?.max ?? 20} recipients allowed`,
        'web.domains.incoming.duplicate_recipient': 'This email is already added',
      };
      return translations[key] ?? key;
    },
  }),
}));

// Pass-through async wrapper so we can inspect underlying service calls
// directly. The composable does not need notification/loading orchestration
// in unit tests.
vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: () => ({
    wrap: vi.fn(async (fn: () => Promise<unknown>) => {
      try {
        return await fn();
      } catch {
        return undefined;
      }
    }),
  }),
  createError: vi.fn(),
}));

describe('useIncomingConfig (single-state, plaintext)', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  // -------------------------------------------------------------------------
  // initialize()
  // -------------------------------------------------------------------------

  describe('initialize()', () => {
    it('populates formState from the server response (plaintext recipients)', async () => {
      mockGetConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      expect(mockGetConfig).toHaveBeenCalledWith('dom_test_123');
      expect(composable.formState.value.enabled).toBe(true);
      expect(composable.formState.value.recipients).toEqual([
        { email: 'security@acme.com', name: 'Security Team' },
        { email: 'support@acme.com', name: 'Support' },
      ]);
    });

    it('snapshots savedFormState so hasUnsavedChanges is false right after load', async () => {
      mockGetConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      expect(composable.savedFormState.value).toEqual(composable.formState.value);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('handles the empty/unconfigured state (no IncomingConfig record yet)', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      expect(composable.formState.value).toEqual({
        enabled: false,
        recipients: [],
      });
      expect(composable.isConfigured.value).toBe(false);
    });

    it('reflects max_recipients from the server response', async () => {
      mockGetConfig.mockResolvedValue({
        record: {
          ...mockEmptyConfigResponse.record,
          max_recipients: 5,
        },
      });

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      expect(composable.maxRecipients.value).toBe(5);
    });

    it('sets isInitialized to true once complete', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      expect(composable.isInitialized.value).toBe(false);
      await composable.initialize();
      expect(composable.isInitialized.value).toBe(true);
    });

    it('decouples formState from the response object (defensive clone)', async () => {
      mockGetConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      // Mutating the form must not affect the original response array.
      composable.formState.value.recipients.push({ email: 'x@y.com', name: 'X' });
      expect(mockMultipleRecipientsConfigResponse.record.recipients).toHaveLength(2);
    });
  });

  // -------------------------------------------------------------------------
  // addRecipient()
  // -------------------------------------------------------------------------

  describe('addRecipient()', () => {
    it('appends to formState (no service call)', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      const ok = composable.addRecipient('new@example.com', 'New Person');

      expect(ok).toBe(true);
      expect(composable.formState.value.recipients).toEqual([
        { email: 'new@example.com', name: 'New Person' },
      ]);
      expect(mockPutConfig).not.toHaveBeenCalled();
    });

    it('flips hasUnsavedChanges to true after a successful add', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.addRecipient('new@example.com', 'New');
      await nextTick();

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('rejects a duplicate email (case-insensitive)', async () => {
      mockGetConfig.mockResolvedValue(mockSingleRecipientConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      const ok = composable.addRecipient('SECURITY@acme.com', 'Other');

      expect(ok).toBe(false);
      expect(composable.formState.value.recipients).toHaveLength(1);
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'This email is already added',
        'warning',
        'top',
      );
    });

    it('rejects when at max capacity', async () => {
      mockGetConfig.mockResolvedValue({
        record: {
          ...mockEmptyConfigResponse.record,
          enabled: true,
          recipients: Array.from({ length: 20 }, (_, i) => ({
            email: `r${i}@example.com`,
            name: `R${i}`,
          })),
          max_recipients: 20,
        },
      });
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      const ok = composable.addRecipient('overflow@example.com', 'Overflow');

      expect(ok).toBe(false);
      expect(composable.formState.value.recipients).toHaveLength(20);
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Maximum 20 recipients allowed',
        'warning',
        'top',
      );
    });

    it('defaults the name to the email local-part when not provided', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.addRecipient('nameless@example.com');

      expect(composable.formState.value.recipients[0]).toEqual({
        email: 'nameless@example.com',
        name: 'nameless',
      });
    });

    it('trims whitespace from email and name', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.addRecipient('  spaced@example.com  ', '  Name  ');

      expect(composable.formState.value.recipients[0]).toEqual({
        email: 'spaced@example.com',
        name: 'Name',
      });
    });
  });

  // -------------------------------------------------------------------------
  // removeRecipient()
  // -------------------------------------------------------------------------

  describe('removeRecipient()', () => {
    it('removes by index', async () => {
      mockGetConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.removeRecipient(0);

      expect(composable.formState.value.recipients).toEqual([
        { email: 'support@acme.com', name: 'Support' },
      ]);
    });

    it('flips hasUnsavedChanges to true', async () => {
      mockGetConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.removeRecipient(0);
      await nextTick();

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('is a no-op for an out-of-range index', async () => {
      mockGetConfig.mockResolvedValue(mockSingleRecipientConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.removeRecipient(99);
      composable.removeRecipient(-1);

      expect(composable.formState.value.recipients).toHaveLength(1);
    });
  });

  // -------------------------------------------------------------------------
  // discardChanges()
  // -------------------------------------------------------------------------

  describe('discardChanges()', () => {
    it('restores formState to the last saved snapshot', async () => {
      mockGetConfig.mockResolvedValue(mockSingleRecipientConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.addRecipient('extra@example.com', 'Extra');
      composable.updateEnabled(false);
      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.hasUnsavedChanges.value).toBe(false);
      expect(composable.formState.value).toEqual({
        enabled: true,
        recipients: [{ email: 'security@acme.com', name: 'Security Team' }],
      });
    });
  });

  // -------------------------------------------------------------------------
  // saveConfig()
  // -------------------------------------------------------------------------

  describe('saveConfig()', () => {
    it('PUTs the full intended state (enabled + recipients)', async () => {
      mockGetConfig.mockResolvedValue(mockSingleRecipientConfigResponse);
      mockPutConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();
      composable.addRecipient('support@acme.com', 'Support');

      await composable.saveConfig();

      expect(mockPutConfig).toHaveBeenCalledWith('dom_test_123', {
        enabled: true,
        recipients: [
          { email: 'security@acme.com', name: 'Security Team' },
          { email: 'support@acme.com', name: 'Support' },
        ],
      });
    });

    it('preserves existing recipients on save (regression for #3095)', async () => {
      mockGetConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);
      mockPutConfig.mockResolvedValue({
        record: {
          ...mockMultipleRecipientsConfigResponse.record,
          recipients: [
            ...mockMultipleRecipientsConfigResponse.record.recipients,
            { email: 'newcomer@acme.com', name: 'Newcomer' },
          ],
        },
      });

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      // Existing list is still in formState; add one more.
      composable.addRecipient('newcomer@acme.com', 'Newcomer');
      await composable.saveConfig();

      // The PUT body must include ALL three recipients, not just the
      // newly added one. This is the bug #3095 was about.
      const [, payload] = mockPutConfig.mock.calls[0];
      expect(payload.recipients).toHaveLength(3);
      expect(payload.recipients).toEqual(
        expect.arrayContaining([
          { email: 'security@acme.com', name: 'Security Team' },
          { email: 'support@acme.com', name: 'Support' },
          { email: 'newcomer@acme.com', name: 'Newcomer' },
        ]),
      );
    });

    it('updates formState and savedFormState from the server response', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);
      mockPutConfig.mockResolvedValue(mockSingleRecipientConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();
      composable.addRecipient('security@acme.com', 'Security Team');
      composable.updateEnabled(true);

      const success = await composable.saveConfig();

      expect(success).toBe(true);
      expect(composable.formState.value.recipients).toEqual([
        { email: 'security@acme.com', name: 'Security Team' },
      ]);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns false and leaves state untouched on service failure', async () => {
      mockGetConfig.mockResolvedValue(mockSingleRecipientConfigResponse);
      mockPutConfig.mockRejectedValue(new Error('500'));

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();
      composable.addRecipient('new@acme.com', 'New');

      const success = await composable.saveConfig();

      expect(success).toBe(false);
      // Pending change remains because the wrapped fn rejected.
      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('toggles isSaving around the request', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);
      mockPutConfig.mockResolvedValue(mockSingleRecipientConfigResponse);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();
      composable.addRecipient('security@acme.com', 'Security Team');

      expect(composable.isSaving.value).toBe(false);
      const savePromise = composable.saveConfig();
      expect(composable.isSaving.value).toBe(true);
      await savePromise;
      expect(composable.isSaving.value).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // deleteConfig()
  // -------------------------------------------------------------------------

  describe('deleteConfig()', () => {
    it('calls DELETE and resets formState to defaults', async () => {
      mockGetConfig.mockResolvedValue(mockMultipleRecipientsConfigResponse);
      mockDeleteConfig.mockResolvedValue(undefined);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockDeleteConfig).toHaveBeenCalledWith('dom_test_123');
      expect(composable.formState.value).toEqual({
        enabled: false,
        recipients: [],
      });
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('toggles isDeleting around the request', async () => {
      mockGetConfig.mockResolvedValue(mockSingleRecipientConfigResponse);
      mockDeleteConfig.mockResolvedValue(undefined);

      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      expect(composable.isDeleting.value).toBe(false);
      const promise = composable.deleteConfig();
      expect(composable.isDeleting.value).toBe(true);
      await promise;
      expect(composable.isDeleting.value).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // updateEnabled()
  // -------------------------------------------------------------------------

  describe('updateEnabled()', () => {
    it('mutates formState.enabled and flips hasUnsavedChanges', async () => {
      mockGetConfig.mockResolvedValue(mockEmptyConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      composable.updateEnabled(true);
      await nextTick();

      expect(composable.formState.value.enabled).toBe(true);
      expect(composable.hasUnsavedChanges.value).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // canAddMore
  // -------------------------------------------------------------------------

  describe('canAddMore', () => {
    it('is true when below the limit', async () => {
      mockGetConfig.mockResolvedValue(mockSingleRecipientConfigResponse);
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      expect(composable.canAddMore.value).toBe(true);
    });

    it('is false when at the limit', async () => {
      mockGetConfig.mockResolvedValue({
        record: {
          ...mockEmptyConfigResponse.record,
          recipients: Array.from({ length: 20 }, (_, i) => ({
            email: `r${i}@example.com`,
            name: `R${i}`,
          })),
        },
      });
      const composable = useIncomingConfig('dom_test_123');
      await composable.initialize();

      expect(composable.canAddMore.value).toBe(false);
    });
  });
});
