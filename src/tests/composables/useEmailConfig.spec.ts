// src/tests/composables/useEmailConfig.spec.ts
//
// Tests for useEmailConfig composable covering:
// 1. initialize(): returns null config on 404, populates formState from config
// 2. saveConfig(): uses PUT when not configured, PATCH when configured
// 3. deleteConfig(): resets to default state
// 4. hasUnsavedChanges: detects field modifications
// 5. discardChanges(): restores saved state
// 6. usesFallbackSender: true when not configured, not verified, or disabled
// 7. reply_to always included in payload (bug fix coverage)
// 8. validateDomain: triggers DNS record verification

import { useEmailConfig } from '@/shared/composables/useEmailConfig';
import { createPinia, setActivePinia } from 'pinia';
import { flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { CustomDomainEmailConfig } from '@/schemas/shapes/domains/email-config';

// ─────────────────────────────────────────────────────────────────────────────
// Mock Setup
// ─────────────────────────────────────────────────────────────────────────────

const mockGetEmailConfig = vi.fn();
const mockPutEmailConfig = vi.fn();
const mockPatchEmailConfig = vi.fn();
const mockDeleteEmailConfig = vi.fn();
const mockValidateEmailConfig = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => ({
    getEmailConfig: mockGetEmailConfig,
    putEmailConfig: mockPutEmailConfig,
    patchEmailConfig: mockPatchEmailConfig,
    deleteEmailConfig: mockDeleteEmailConfig,
    validateEmailConfig: mockValidateEmailConfig,
  }),
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
    t: (key: string) => {
      const translations: Record<string, string> = {
        'web.domains.email.update_success': 'Email configuration updated',
        'web.domains.email.delete_success': 'Email configuration removed',
        'web.domains.email.validation_failed': 'Validation failed',
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

// ─────────────────────────────────────────────────────────────────────────────
// Test Fixtures
// ─────────────────────────────────────────────────────────────────────────────

const mockEmailConfigData: CustomDomainEmailConfig = {
  domain_id: 'domain-123',
  provider: 'ses',
  enabled: true,
  from_address: 'noreply@example.com',
  from_name: 'Acme Corp',
  reply_to: 'support@example.com',
  validation_status: 'verified',
  dns_records: [
    { type: 'TXT', name: '_dmarc.example.com', value: 'v=DMARC1; p=none', status: 'verified' },
    { type: 'CNAME', name: 'em._domainkey.example.com', value: 'dkim.example.com', status: 'pending' },
  ],
  last_validated_at: new Date('2025-01-15T10:00:00Z'),
  provider_domain_id: null,
  created_at: new Date('2025-01-01T00:00:00Z'),
  updated_at: new Date('2025-01-15T10:00:00Z'),
};

const mockPendingConfig: CustomDomainEmailConfig = {
  ...mockEmailConfigData,
  validation_status: 'pending',
  enabled: false,
};

const mockDisabledConfig: CustomDomainEmailConfig = {
  ...mockEmailConfigData,
  enabled: false,
};

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('useEmailConfig', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    // Default: no existing config (unconfigured)
    mockGetEmailConfig.mockResolvedValue(null);
    mockPutEmailConfig.mockResolvedValue(mockEmailConfigData);
    mockPatchEmailConfig.mockResolvedValue(mockEmailConfigData);
    mockDeleteEmailConfig.mockResolvedValue({ success: true });
    mockValidateEmailConfig.mockResolvedValue({ record: mockEmailConfigData });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // initialize
  // ─────────────────────────────────────────────────────────────────────────

  describe('initialize', () => {
    it('sets emailConfig to null when domain is unconfigured (404)', async () => {
      mockGetEmailConfig.mockResolvedValue(null);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.emailConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
      expect(composable.isInitialized.value).toBe(true);
    });

    it('populates formState from existing config', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.emailConfig.value).toEqual(mockEmailConfigData);
      expect(composable.formState.value).toEqual({
        from_name: 'Acme Corp',
        from_address: 'noreply@example.com',
        reply_to: 'support@example.com',
        enabled: true,
      });
      expect(composable.isConfigured.value).toBe(true);
    });

    it('sets default formState when unconfigured', async () => {
      mockGetEmailConfig.mockResolvedValue(null);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value).toEqual({
        from_name: '',
        from_address: '',
        reply_to: '',
        enabled: false,
      });
    });

    it('snapshots savedFormState on load', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      // hasUnsavedChanges should be false immediately after load
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('handles null reply_to in config by converting to empty string', async () => {
      const configWithNullReplyTo: CustomDomainEmailConfig = {
        ...mockEmailConfigData,
        reply_to: null,
      };
      mockGetEmailConfig.mockResolvedValue(configWithNullReplyTo);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.reply_to).toBe('');
    });

    it('calls domainsStore.getEmailConfig with correct extid', async () => {
      const composable = useEmailConfig('dm-ext-456');
      await composable.initialize();

      expect(mockGetEmailConfig).toHaveBeenCalledWith('dm-ext-456');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // saveConfig
  // ─────────────────────────────────────────────────────────────────────────

  describe('saveConfig', () => {
    it('uses PUT when domain is not yet configured', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      // Fill in form
      composable.formState.value = {
        from_name: 'Test Corp',
        from_address: 'test@example.com',
        reply_to: '',
        enabled: true,
      };

      await composable.saveConfig();

      expect(mockPutEmailConfig).toHaveBeenCalledWith('dm-ext-123', expect.objectContaining({
        from_name: 'Test Corp',
        from_address: 'test@example.com',
        enabled: true,
      }));
      expect(mockPatchEmailConfig).not.toHaveBeenCalled();
    });

    it('uses PATCH when domain is already configured', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      // Modify form
      composable.formState.value = {
        ...composable.formState.value,
        from_name: 'Updated Corp',
      };

      await composable.saveConfig();

      expect(mockPatchEmailConfig).toHaveBeenCalledWith('dm-ext-123', expect.objectContaining({
        from_name: 'Updated Corp',
      }));
      expect(mockPutEmailConfig).not.toHaveBeenCalled();
    });

    it('trims whitespace from text fields', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        from_name: '  Test Corp  ',
        from_address: '  test@example.com  ',
        reply_to: '  reply@example.com  ',
        enabled: true,
      };

      await composable.saveConfig();

      expect(mockPutEmailConfig).toHaveBeenCalledWith('dm-ext-123', expect.objectContaining({
        from_name: 'Test Corp',
        from_address: 'test@example.com',
        reply_to: 'reply@example.com',
      }));
    });

    it('always includes reply_to in PUT payload', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        from_name: 'Test Corp',
        from_address: 'test@example.com',
        reply_to: '',
        enabled: true,
      };

      await composable.saveConfig();

      const putCall = mockPutEmailConfig.mock.calls[0];
      expect(putCall[1]).toHaveProperty('reply_to');
      expect(putCall[1].reply_to).toBe('');
    });

    it('always includes reply_to in PATCH payload', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      // Modify only the from_name
      composable.formState.value = {
        ...composable.formState.value,
        from_name: 'Updated Corp',
      };

      await composable.saveConfig();

      const patchCall = mockPatchEmailConfig.mock.calls[0];
      expect(patchCall[1]).toHaveProperty('reply_to');
    });

    it('updates emailConfig and formState after successful save', async () => {
      const updatedConfig: CustomDomainEmailConfig = {
        ...mockEmailConfigData,
        from_name: 'Updated Corp',
      };
      mockGetEmailConfig.mockResolvedValue(null);
      mockPutEmailConfig.mockResolvedValue(updatedConfig);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        from_name: 'Updated Corp',
        from_address: 'test@example.com',
        reply_to: '',
        enabled: true,
      };

      await composable.saveConfig();

      expect(composable.emailConfig.value).toEqual(updatedConfig);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('shows success notification after save', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        from_name: 'Test',
        from_address: 'test@example.com',
        reply_to: '',
        enabled: true,
      };

      await composable.saveConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Email configuration updated',
        'success',
        'top',
      );
    });

    it('sets isSaving during operation', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      let resolvePut: (value: unknown) => void;
      mockPutEmailConfig.mockImplementation(() => new Promise((resolve) => {
        resolvePut = resolve;
      }));

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        from_name: 'Test',
        from_address: 'test@example.com',
        reply_to: '',
        enabled: true,
      };

      const savePromise = composable.saveConfig();
      expect(composable.isSaving.value).toBe(true);

      resolvePut!(mockEmailConfigData);
      await savePromise;

      expect(composable.isSaving.value).toBe(false);
    });

    it('resets isSaving even when save fails', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      // wrap returns undefined on error, which means result is falsy
      // so no notification is shown, but isSaving should still reset
      mockPutEmailConfig.mockRejectedValue(new Error('Network error'));

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        from_name: 'Test',
        from_address: 'test@example.com',
        reply_to: '',
        enabled: true,
      };

      await composable.saveConfig();

      expect(composable.isSaving.value).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // deleteConfig
  // ─────────────────────────────────────────────────────────────────────────

  describe('deleteConfig', () => {
    it('resets emailConfig to null after deletion', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(true);

      await composable.deleteConfig();

      expect(composable.emailConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
    });

    it('resets formState to default after deletion', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(composable.formState.value).toEqual({
        from_name: '',
        from_address: '',
        reply_to: '',
        enabled: false,
      });
    });

    it('resets savedFormState so hasUnsavedChanges is false', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('calls domainsStore.deleteEmailConfig with correct extid', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-456');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockDeleteEmailConfig).toHaveBeenCalledWith('dm-ext-456');
    });

    it('shows success notification after deletion', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Email configuration removed',
        'success',
        'top',
      );
    });

    it('sets isDeleting during operation', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      let resolveDelete: (value: unknown) => void;
      mockDeleteEmailConfig.mockImplementation(() => new Promise((resolve) => {
        resolveDelete = resolve;
      }));

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const deletePromise = composable.deleteConfig();
      expect(composable.isDeleting.value).toBe(true);

      resolveDelete!({ success: true });
      await deletePromise;

      expect(composable.isDeleting.value).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // hasUnsavedChanges
  // ─────────────────────────────────────────────────────────────────────────

  describe('hasUnsavedChanges', () => {
    it('returns false immediately after initialization', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns true when from_name is modified', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        from_name: 'Changed Name',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when from_address is modified', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        from_address: 'changed@example.com',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when reply_to is modified', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        reply_to: 'newreply@example.com',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when enabled is toggled', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns false when changes are reverted to original values', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      // Modify
      composable.formState.value = {
        ...composable.formState.value,
        from_name: 'Changed',
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      // Revert
      composable.formState.value = {
        ...composable.formState.value,
        from_name: 'Acme Corp',
      };
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns false before initialization (no savedFormState)', () => {
      const composable = useEmailConfig('dm-ext-123');
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // discardChanges
  // ─────────────────────────────────────────────────────────────────────────

  describe('discardChanges', () => {
    it('restores formState to saved values', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const originalFormState = { ...composable.formState.value };

      // Modify multiple fields
      composable.formState.value = {
        from_name: 'Changed Corp',
        from_address: 'changed@example.com',
        reply_to: 'changed-reply@example.com',
        enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.formState.value).toEqual(originalFormState);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('is a no-op when savedFormState is null (before init)', () => {
      const composable = useEmailConfig('dm-ext-123');

      // Should not throw
      composable.discardChanges();

      // formState should remain at defaults
      expect(composable.formState.value).toEqual({
        from_name: '',
        from_address: '',
        reply_to: '',
        enabled: false,
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // usesFallbackSender
  // ─────────────────────────────────────────────────────────────────────────

  describe('usesFallbackSender', () => {
    it('returns true when domain is not configured', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.usesFallbackSender.value).toBe(true);
    });

    it('returns true when domain is configured but not verified', async () => {
      mockGetEmailConfig.mockResolvedValue(mockPendingConfig);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.usesFallbackSender.value).toBe(true);
    });

    it('returns true when domain is configured and verified but disabled', async () => {
      mockGetEmailConfig.mockResolvedValue(mockDisabledConfig);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.usesFallbackSender.value).toBe(true);
    });

    it('returns false when configured, verified, and enabled', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.usesFallbackSender.value).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Computed properties
  // ─────────────────────────────────────────────────────────────────────────

  describe('computed properties', () => {
    it('isVerified returns true when validation_status is verified', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isVerified.value).toBe(true);
    });

    it('isVerified returns false when validation_status is pending', async () => {
      mockGetEmailConfig.mockResolvedValue(mockPendingConfig);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isVerified.value).toBe(false);
    });

    it('dnsRecords returns records from config', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.dnsRecords.value).toHaveLength(2);
      expect(composable.dnsRecords.value[0].type).toBe('TXT');
    });

    it('dnsRecords returns empty array when unconfigured', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.dnsRecords.value).toEqual([]);
    });

    it('validationStatus defaults to pending when unconfigured', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.validationStatus.value).toBe('pending');
    });

    it('lastValidatedAt returns null when unconfigured', async () => {
      mockGetEmailConfig.mockResolvedValue(null);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.lastValidatedAt.value).toBeNull();
    });

    it('lastValidatedAt returns date from config', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.lastValidatedAt.value).toEqual(new Date('2025-01-15T10:00:00Z'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // validateDomain
  // ─────────────────────────────────────────────────────────────────────────

  describe('validateDomain', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    /** Advance fake timers through all polling iterations. */
    const drainPolling = async () => {
      for (let i = 0; i < 10; i++) {
        vi.advanceTimersByTime(3000);
        await flushPromises();
      }
    };

    it('calls domainsStore.validateEmailConfig with correct extid', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      const composable = useEmailConfig('dm-ext-789');
      await composable.initialize();

      const promise = composable.validateDomain();
      await drainPolling();
      await promise;

      expect(mockValidateEmailConfig).toHaveBeenCalledWith('dm-ext-789');
    });

    it('updates emailConfig and formState from validation response', async () => {
      const updatedConfig: CustomDomainEmailConfig = {
        ...mockEmailConfigData,
        validation_status: 'verified',
      };
      mockValidateEmailConfig.mockResolvedValue({ record: updatedConfig });
      mockGetEmailConfig.mockResolvedValue(updatedConfig);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();
      await drainPolling();
      await promise;

      expect(composable.emailConfig.value?.validation_status).toBe('verified');
    });

    it('shows error notification when validation fails', async () => {
      mockValidateEmailConfig.mockRejectedValue(new Error('DNS check failed'));
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();
      await drainPolling();
      await promise;

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Validation failed',
        'error',
        'top',
      );
    });

    it('sets isValidating during operation', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      mockValidateEmailConfig.mockResolvedValue({ record: mockEmailConfigData });

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const validatePromise = composable.validateDomain();
      expect(composable.isValidating.value).toBe(true);

      await drainPolling();
      await validatePromise;

      expect(composable.isValidating.value).toBe(false);
    });

    it('resets isValidating even when validation fails', async () => {
      mockValidateEmailConfig.mockRejectedValue(new Error('DNS check failed'));
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();
      await drainPolling();
      await promise;

      expect(composable.isValidating.value).toBe(false);
    });

    it('guards against concurrent calls', async () => {
      mockGetEmailConfig.mockResolvedValue(mockEmailConfigData);
      mockValidateEmailConfig.mockResolvedValue({ record: mockEmailConfigData });

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const p1 = composable.validateDomain();
      composable.validateDomain(); // should be a no-op

      await drainPolling();
      await p1;

      expect(mockValidateEmailConfig).toHaveBeenCalledTimes(1);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // pollForValidationResult (via validateDomain)
  // ─────────────────────────────────────────────────────────────────────────

  describe('pollForValidationResult (via validateDomain)', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('stops polling when status transitions from pending to verified', async () => {
      mockValidateEmailConfig.mockResolvedValue({ record: mockPendingConfig });
      // initialize returns pending, first poll returns pending, second returns verified
      mockGetEmailConfig
        .mockResolvedValueOnce(mockPendingConfig)  // initialize
        .mockResolvedValueOnce(mockPendingConfig)  // poll 1
        .mockResolvedValueOnce(mockEmailConfigData); // poll 2 (verified)

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();

      // Advance through 2 polls
      await vi.advanceTimersByTimeAsync(3000);
      await vi.advanceTimersByTimeAsync(3000);
      await promise;

      expect(composable.emailConfig.value?.validation_status).toBe('verified');
      // 1 (init) + 2 (polls)
      expect(mockGetEmailConfig).toHaveBeenCalledTimes(3);
    });

    it('stops polling when status transitions from pending to failed', async () => {
      const failedConfig: CustomDomainEmailConfig = {
        ...mockEmailConfigData,
        validation_status: 'failed',
      };
      mockValidateEmailConfig.mockResolvedValue({ record: mockPendingConfig });
      mockGetEmailConfig
        .mockResolvedValueOnce(mockPendingConfig)  // initialize
        .mockResolvedValueOnce(failedConfig);       // poll 1

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();
      await vi.advanceTimersByTimeAsync(3000);
      await promise;

      expect(composable.emailConfig.value?.validation_status).toBe('failed');
    });

    it('stops after maxAttempts if status stays pending', async () => {
      mockValidateEmailConfig.mockResolvedValue({ record: mockPendingConfig });
      mockGetEmailConfig.mockResolvedValue(mockPendingConfig);

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();

      // Drain all 10 polls
      for (let i = 0; i < 10; i++) {
        vi.advanceTimersByTime(3000);
        await flushPromises();
      }
      await promise;

      // 1 (init) + 10 (polls)
      expect(mockGetEmailConfig).toHaveBeenCalledTimes(11);
      expect(composable.emailConfig.value?.validation_status).toBe('pending');
    });

    it('keeps isValidating true during polling and sets false after', async () => {
      mockValidateEmailConfig.mockResolvedValue({ record: mockPendingConfig });
      mockGetEmailConfig
        .mockResolvedValueOnce(mockPendingConfig)    // initialize
        .mockResolvedValueOnce(mockPendingConfig)    // poll 1
        .mockResolvedValueOnce(mockEmailConfigData); // poll 2 (verified)

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();

      // After first poll, still validating
      await vi.advanceTimersByTimeAsync(3000);
      expect(composable.isValidating.value).toBe(true);

      // After second poll (verified), done
      await vi.advanceTimersByTimeAsync(3000);
      await promise;
      expect(composable.isValidating.value).toBe(false);
    });

    it('swallows network errors during polling', async () => {
      mockValidateEmailConfig.mockResolvedValue({ record: mockPendingConfig });
      mockGetEmailConfig
        .mockResolvedValueOnce(mockPendingConfig)    // initialize
        .mockRejectedValueOnce(new Error('Network'))  // poll 1 fails
        .mockResolvedValueOnce(mockEmailConfigData); // poll 2 succeeds

      const composable = useEmailConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.validateDomain();

      await vi.advanceTimersByTimeAsync(3000);
      await vi.advanceTimersByTimeAsync(3000);
      await promise;

      expect(composable.emailConfig.value?.validation_status).toBe('verified');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Initial state
  // ─────────────────────────────────────────────────────────────────────────

  describe('initial state', () => {
    it('starts with isLoading false', () => {
      const composable = useEmailConfig('dm-ext-123');
      expect(composable.isLoading.value).toBe(false);
    });

    it('starts with isInitialized false', () => {
      const composable = useEmailConfig('dm-ext-123');
      expect(composable.isInitialized.value).toBe(false);
    });

    it('starts with isSaving false', () => {
      const composable = useEmailConfig('dm-ext-123');
      expect(composable.isSaving.value).toBe(false);
    });

    it('starts with error null', () => {
      const composable = useEmailConfig('dm-ext-123');
      expect(composable.error.value).toBeNull();
    });

    it('starts with emailConfig null', () => {
      const composable = useEmailConfig('dm-ext-123');
      expect(composable.emailConfig.value).toBeNull();
    });
  });
});
