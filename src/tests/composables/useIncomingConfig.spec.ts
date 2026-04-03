// src/tests/composables/useIncomingConfig.spec.ts
//
// Tests for useIncomingConfig composable covering:
// 1. initialize(): fetches recipients, populates server and form state
// 2. saveConfig(): uses PUT to replace all recipients
// 3. deleteConfig(): clears all recipients
// 4. hasUnsavedChanges: detects form modifications
// 5. discardChanges(): restores saved state
// 6. addRecipient(): adds with validation (email, duplicate, limit)
// 7. removeRecipient(): removes by index
// 8. updateRecipient(): modifies existing
//
// Data asymmetry note: form uses email (plaintext), server returns digest (hash)

import { useIncomingConfig } from '@/shared/composables/useIncomingConfig';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  mockRecipientsResponse,
  mockEmptyRecipientsResponse,
  mockPutRecipientsResponse,
  mockDeleteRecipientsResponse,
} from '../fixtures/incomingConfig.fixture';

// ---------------------------------------------------------------------------
// Mock Setup
// ---------------------------------------------------------------------------

const mockGetRecipients = vi.fn();
const mockSetRecipients = vi.fn();
const mockDeleteRecipients = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/services/recipients.service', () => ({
  RecipientsService: {
    getRecipientsForDomain: (...args: unknown[]) => mockGetRecipients(...args),
    setRecipientsForDomain: (...args: unknown[]) => mockSetRecipients(...args),
    deleteRecipientsForDomain: (...args: unknown[]) => mockDeleteRecipients(...args),
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
        'web.COMMON.unexpected_error': 'An unexpected error occurred',
      };
      return translations[key] ?? key;
    },
  }),
}));

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('useIncomingConfig', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    // Default: existing recipients configured
    mockGetRecipients.mockResolvedValue(mockRecipientsResponse);
    mockSetRecipients.mockResolvedValue(mockPutRecipientsResponse);
    mockDeleteRecipients.mockResolvedValue(mockDeleteRecipientsResponse);
  });

  // ---------------------------------------------------------------------------
  // initialize
  // ---------------------------------------------------------------------------

  describe('initialize', () => {
    it('UC-INIT-001: populates serverState from API response', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.serverState.value.recipients).toEqual(mockRecipientsResponse.recipients);
      expect(composable.isConfigured.value).toBe(true);
    });

    it('UC-INIT-002: sets empty serverState when no recipients configured', async () => {
      mockGetRecipients.mockResolvedValue(mockEmptyRecipientsResponse);

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.serverState.value.recipients).toEqual([]);
      expect(composable.isConfigured.value).toBe(false);
    });

    it('UC-INIT-003: resets formState to empty on load (cannot recover emails from hashes)', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.recipients).toEqual([]);
    });

    it('UC-INIT-004: snapshots savedFormState on load', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      // hasUnsavedChanges should be false immediately after load
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('UC-INIT-005: sets isInitialized to true after load', async () => {
      const composable = useIncomingConfig('dm-ext-123');

      expect(composable.isInitialized.value).toBe(false);
      await composable.initialize();
      expect(composable.isInitialized.value).toBe(true);
    });

    it('UC-INIT-006: calls RecipientsService.getRecipientsForDomain with correct extid', async () => {
      const composable = useIncomingConfig('dm-ext-456');
      await composable.initialize();

      expect(mockGetRecipients).toHaveBeenCalledWith('dm-ext-456');
    });

    it('sets maxRecipients from API response', async () => {
      mockGetRecipients.mockResolvedValue({
        ...mockRecipientsResponse,
        maxRecipients: 15,
      });

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.maxRecipients.value).toBe(15);
    });

    it('sets canManage from API response', async () => {
      mockGetRecipients.mockResolvedValue({
        ...mockRecipientsResponse,
        canManage: false,
      });

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.canManage.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // saveConfig
  // ---------------------------------------------------------------------------

  describe('saveConfig', () => {
    it('UC-SAVE-001: uses PUT (setRecipientsForDomain) to replace all recipients', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      // Add a recipient to form
      composable.addRecipient('new@example.com', 'New User');
      await composable.saveConfig();

      expect(mockSetRecipients).toHaveBeenCalledWith('dm-ext-123', [
        { email: 'new@example.com', name: 'New User' },
      ]);
    });

    it('UC-SAVE-002: updates serverState after successful save', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      await composable.saveConfig();

      expect(composable.serverState.value.recipients).toEqual(mockPutRecipientsResponse.recipients);
    });

    it('UC-SAVE-003: clears formState after successful save', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      expect(composable.formState.value.recipients.length).toBe(1);

      await composable.saveConfig();

      // Form should be cleared after save (emails are now hashed on server)
      expect(composable.formState.value.recipients).toEqual([]);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('UC-SAVE-005: shows success notification after save', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      await composable.saveConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Recipients updated',
        'success',
        'top',
      );
    });

    it('UC-SAVE-006: sets isSaving during operation', async () => {
      let resolveSet: (value: unknown) => void;
      mockSetRecipients.mockImplementation(() => new Promise((resolve) => {
        resolveSet = resolve;
      }));

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      const savePromise = composable.saveConfig();
      expect(composable.isSaving.value).toBe(true);

      resolveSet!(mockPutRecipientsResponse);
      await savePromise;

      expect(composable.isSaving.value).toBe(false);
    });

    it('UC-SAVE-007: resets isSaving on error', async () => {
      mockSetRecipients.mockRejectedValue(new Error('Network error'));

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      await composable.saveConfig();

      expect(composable.isSaving.value).toBe(false);
    });

    it('returns true on successful save', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      const result = await composable.saveConfig();

      expect(result).toBe(true);
    });

    it('returns false on failed save', async () => {
      mockSetRecipients.mockRejectedValue(new Error('Network error'));

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      const result = await composable.saveConfig();

      expect(result).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // deleteConfig
  // ---------------------------------------------------------------------------

  describe('deleteConfig', () => {
    it('UC-DEL-001: resets serverState to empty after deletion', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(true);

      await composable.deleteConfig();

      expect(composable.serverState.value.recipients).toEqual([]);
      expect(composable.isConfigured.value).toBe(false);
    });

    it('UC-DEL-002: resets formState to defaults after deletion', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('pending@example.com');
      await composable.deleteConfig();

      expect(composable.formState.value.recipients).toEqual([]);
    });

    it('UC-DEL-003: resets savedFormState so hasUnsavedChanges is false', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('pending@example.com');
      expect(composable.hasUnsavedChanges.value).toBe(true);

      await composable.deleteConfig();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('UC-DEL-004: shows success notification after deletion', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Recipients cleared',
        'success',
        'top',
      );
    });

    it('UC-DEL-005: sets isDeleting during operation', async () => {
      let resolveDelete: (value: unknown) => void;
      mockDeleteRecipients.mockImplementation(() => new Promise((resolve) => {
        resolveDelete = resolve;
      }));

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      const deletePromise = composable.deleteConfig();
      expect(composable.isDeleting.value).toBe(true);

      resolveDelete!(mockDeleteRecipientsResponse);
      await deletePromise;

      expect(composable.isDeleting.value).toBe(false);
    });

    it('calls RecipientsService.deleteRecipientsForDomain with correct extid', async () => {
      const composable = useIncomingConfig('dm-ext-789');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockDeleteRecipients).toHaveBeenCalledWith('dm-ext-789');
    });
  });

  // ---------------------------------------------------------------------------
  // hasUnsavedChanges
  // ---------------------------------------------------------------------------

  describe('hasUnsavedChanges', () => {
    it('UC-DIRTY-001: returns false immediately after initialization', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('UC-DIRTY-002: returns true when recipient added', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('UC-DIRTY-003: returns true when recipient removed', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      // Save to baseline
      await composable.saveConfig();

      // Re-initialize (form is now empty)
      mockGetRecipients.mockResolvedValue({
        ...mockRecipientsResponse,
        recipients: [{ digest: 'sha256_new', display_name: 'New' }],
      });
      await composable.initialize();

      // Add and then remove
      composable.addRecipient('another@example.com');
      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.removeRecipient(0);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('UC-DIRTY-004: returns true when recipient email modified', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('original@example.com');

      // Manually snapshot the form state
      composable.formState.value.recipients[0].email = 'modified@example.com';

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('UC-DIRTY-006: returns false when changes reverted', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('new@example.com');
      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.removeRecipient(0);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('UC-DIRTY-007: returns false before initialization', () => {
      const composable = useIncomingConfig('dm-ext-123');
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // discardChanges
  // ---------------------------------------------------------------------------

  describe('discardChanges', () => {
    it('UC-DISCARD-001: restores formState to saved values', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      // Add multiple recipients
      composable.addRecipient('first@example.com');
      composable.addRecipient('second@example.com');
      expect(composable.formState.value.recipients.length).toBe(2);

      composable.discardChanges();

      expect(composable.formState.value.recipients).toEqual([]);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('UC-DISCARD-002: no-op when savedFormState is null (before init)', () => {
      const composable = useIncomingConfig('dm-ext-123');

      // Should not throw
      composable.discardChanges();

      expect(composable.formState.value.recipients).toEqual([]);
    });
  });

  // ---------------------------------------------------------------------------
  // addRecipient
  // ---------------------------------------------------------------------------

  describe('addRecipient', () => {
    it('UC-RECIP-001: adds recipient to form state', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      const result = composable.addRecipient('new@example.com', 'New User');

      expect(result).toBe(true);
      expect(composable.formState.value.recipients).toHaveLength(1);
      expect(composable.formState.value.recipients[0]).toEqual({
        email: 'new@example.com',
        name: 'New User',
      });
    });

    it('UC-RECIP-003: rejects duplicate email (case-insensitive)', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('test@example.com');
      const result = composable.addRecipient('TEST@EXAMPLE.COM');

      expect(result).toBe(false);
      expect(composable.formState.value.recipients).toHaveLength(1);
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'This email is already added',
        'warning',
        'top',
      );
    });

    it('UC-RECIP-004: enforces 20 recipient limit', async () => {
      mockGetRecipients.mockResolvedValue(mockEmptyRecipientsResponse);

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      // Add 20 recipients
      for (let i = 0; i < 20; i++) {
        composable.addRecipient(`user${i}@example.com`);
      }

      expect(composable.formState.value.recipients).toHaveLength(20);
      expect(composable.canAddMore.value).toBe(false);

      // Try to add 21st
      const result = composable.addRecipient('overflow@example.com');

      expect(result).toBe(false);
      expect(composable.formState.value.recipients).toHaveLength(20);
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Maximum 20 recipients allowed',
        'warning',
        'top',
      );
    });

    it('trims whitespace from email', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('  spaced@example.com  ', '  Spaced User  ');

      expect(composable.formState.value.recipients[0].email).toBe('spaced@example.com');
      expect(composable.formState.value.recipients[0].name).toBe('Spaced User');
    });

    it('handles optional name (undefined)', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('noname@example.com');

      expect(composable.formState.value.recipients[0].name).toBeUndefined();
    });
  });

  // ---------------------------------------------------------------------------
  // removeRecipient
  // ---------------------------------------------------------------------------

  describe('removeRecipient', () => {
    it('UC-RECIP-005: removes recipient by index', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('first@example.com');
      composable.addRecipient('second@example.com');
      composable.addRecipient('third@example.com');

      composable.removeRecipient(1);

      expect(composable.formState.value.recipients).toHaveLength(2);
      expect(composable.formState.value.recipients[0].email).toBe('first@example.com');
      expect(composable.formState.value.recipients[1].email).toBe('third@example.com');
    });

    it('ignores invalid index (negative)', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('test@example.com');
      composable.removeRecipient(-1);

      expect(composable.formState.value.recipients).toHaveLength(1);
    });

    it('ignores invalid index (out of bounds)', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('test@example.com');
      composable.removeRecipient(10);

      expect(composable.formState.value.recipients).toHaveLength(1);
    });
  });

  // ---------------------------------------------------------------------------
  // updateRecipient
  // ---------------------------------------------------------------------------

  describe('updateRecipient', () => {
    it('UC-RECIP-006: modifies existing recipient', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('original@example.com', 'Original Name');
      composable.updateRecipient(0, { email: 'updated@example.com', name: 'Updated Name' });

      expect(composable.formState.value.recipients[0]).toEqual({
        email: 'updated@example.com',
        name: 'Updated Name',
      });
    });

    it('trims whitespace on update', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('test@example.com');
      composable.updateRecipient(0, { email: '  updated@example.com  ' });

      expect(composable.formState.value.recipients[0].email).toBe('updated@example.com');
    });

    it('ignores invalid index', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('test@example.com');

      // Should not throw
      composable.updateRecipient(10, { email: 'updated@example.com' });

      expect(composable.formState.value.recipients[0].email).toBe('test@example.com');
    });
  });

  // ---------------------------------------------------------------------------
  // clearForm
  // ---------------------------------------------------------------------------

  describe('clearForm', () => {
    it('clears all recipients from form state (local only)', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      composable.addRecipient('first@example.com');
      composable.addRecipient('second@example.com');

      composable.clearForm();

      expect(composable.formState.value.recipients).toEqual([]);
      // Note: hasUnsavedChanges will be true if there was anything before clearing
    });
  });

  // ---------------------------------------------------------------------------
  // Computed properties
  // ---------------------------------------------------------------------------

  describe('computed properties', () => {
    it('recipientCount reflects current form state', async () => {
      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.recipientCount.value).toBe(0);

      composable.addRecipient('test@example.com');
      expect(composable.recipientCount.value).toBe(1);

      composable.addRecipient('another@example.com');
      expect(composable.recipientCount.value).toBe(2);
    });

    it('canAddMore is true when under limit', async () => {
      mockGetRecipients.mockResolvedValue(mockEmptyRecipientsResponse);

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.canAddMore.value).toBe(true);
    });

    it('canAddMore is false when at limit', async () => {
      mockGetRecipients.mockResolvedValue(mockEmptyRecipientsResponse);

      const composable = useIncomingConfig('dm-ext-123');
      await composable.initialize();

      for (let i = 0; i < 20; i++) {
        composable.addRecipient(`user${i}@example.com`);
      }

      expect(composable.canAddMore.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------

  describe('initial state', () => {
    it('UC-STATE-001: starts with isLoading false', () => {
      const composable = useIncomingConfig('dm-ext-123');
      expect(composable.isLoading.value).toBe(false);
    });

    it('UC-STATE-002: starts with isInitialized false', () => {
      const composable = useIncomingConfig('dm-ext-123');
      expect(composable.isInitialized.value).toBe(false);
    });

    it('UC-STATE-003: starts with isSaving false', () => {
      const composable = useIncomingConfig('dm-ext-123');
      expect(composable.isSaving.value).toBe(false);
    });

    it('UC-STATE-004: starts with error null', () => {
      const composable = useIncomingConfig('dm-ext-123');
      expect(composable.error.value).toBeNull();
    });

    it('UC-STATE-005: starts with serverState empty', () => {
      const composable = useIncomingConfig('dm-ext-123');
      expect(composable.serverState.value.recipients).toEqual([]);
    });

    it('starts with formState empty', () => {
      const composable = useIncomingConfig('dm-ext-123');
      expect(composable.formState.value.recipients).toEqual([]);
    });
  });
});
