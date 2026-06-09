// src/tests/composables/useSigninConfig.spec.ts
//
// Tests for useSigninConfig composable covering:
// 1. initialize(): returns null config on 404, populates formState from config
// 2. saveConfig(): PUT full replacement with all 5 boolean/enum fields
// 3. deleteConfig(): resets to default state
// 4. hasUnsavedChanges: detects field modifications
// 5. discardChanges(): restores saved state
// 6. configToFormState: coerces nullable API fields to concrete defaults

import { useSigninConfig } from '@/shared/composables/useSigninConfig';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { CustomDomainSigninConfig } from '@/schemas/shapes/domains/signin-config';

// -----------------------------------------------------------------------------
// Mock Setup
// -----------------------------------------------------------------------------

const mockGetConfigForDomain = vi.fn();
const mockPutConfigForDomain = vi.fn();
const mockDeleteConfigForDomain = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/services/signin-config.service', () => ({
  SigninConfigService: {
    getConfigForDomain: (...args: unknown[]) => mockGetConfigForDomain(...args),
    putConfigForDomain: (...args: unknown[]) => mockPutConfigForDomain(...args),
    deleteConfigForDomain: (...args: unknown[]) => mockDeleteConfigForDomain(...args),
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
    t: (key: string) => {
      const translations: Record<string, string> = {
        'web.domains.signin.update_success': 'Signin configuration updated',
        'web.domains.signin.delete_success': 'Signin configuration removed',
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

// -----------------------------------------------------------------------------
// Test Fixtures
// -----------------------------------------------------------------------------

const mockSigninConfigData: CustomDomainSigninConfig = {
  domain_id: 'domain-123',
  enabled: true,
  signin_enabled: true,
  restrict_to: null,
  email_auth_enabled: true,
  sso_enabled: false,
  created_at: new Date('2025-01-01T00:00:00Z'),
  updated_at: new Date('2025-01-15T10:00:00Z'),
};

const mockRestrictedConfig: CustomDomainSigninConfig = {
  ...mockSigninConfigData,
  restrict_to: 'sso',
  sso_enabled: true,
};

const _mockDisabledConfig: CustomDomainSigninConfig = {
  ...mockSigninConfigData,
  enabled: false,
  signin_enabled: false,
  email_auth_enabled: false,
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

describe('useSigninConfig', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    // Default: no existing config (unconfigured)
    mockGetConfigForDomain.mockResolvedValue({ record: null });
    mockPutConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
    mockDeleteConfigForDomain.mockResolvedValue({ success: true });
  });

  // ---------------------------------------------------------------------------
  // initialize
  // ---------------------------------------------------------------------------

  describe('initialize', () => {
    it('sets signinConfig to null when domain is unconfigured (404)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.signinConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
      expect(composable.isInitialized.value).toBe(true);
    });

    it('populates formState from existing config', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.signinConfig.value).toEqual(mockSigninConfigData);
      expect(composable.formState.value).toEqual({
        enabled: true,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: true,
        sso_enabled: false,
      });
      expect(composable.isConfigured.value).toBe(true);
    });

    it('sets default formState when domain is unconfigured', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value).toEqual({
        enabled: false,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: false,
        sso_enabled: false,
      });
    });

    it('snapshots savedFormState on load', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('sets isInitialized to true after load', async () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.isInitialized.value).toBe(false);

      await composable.initialize();

      expect(composable.isInitialized.value).toBe(true);
    });

    it('calls SigninConfigService.getConfigForDomain with correct extid', async () => {
      const composable = useSigninConfig('dm-ext-456');
      await composable.initialize();

      expect(mockGetConfigForDomain).toHaveBeenCalledWith('dm-ext-456');
    });

    it('maps restrict_to from config to formState', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockRestrictedConfig });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.restrict_to).toBe('sso');
    });

    it('coerces null nullable fields to defaults', async () => {
      // Config where nullable fields are explicitly null
      const configWithNulls: CustomDomainSigninConfig = {
        ...mockSigninConfigData,
        restrict_to: null,
      };
      mockGetConfigForDomain.mockResolvedValue({ record: configWithNulls });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.restrict_to).toBeNull();
    });
  });

  // ---------------------------------------------------------------------------
  // saveConfig
  // ---------------------------------------------------------------------------

  describe('saveConfig', () => {
    it('sends all form fields in PUT payload', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        enabled: true,
        signin_enabled: true,
        restrict_to: 'email_auth',
        email_auth_enabled: true,
        sso_enabled: false,
      };

      await composable.saveConfig();

      expect(mockPutConfigForDomain).toHaveBeenCalledWith('dm-ext-123', {
        enabled: true,
        signin_enabled: true,
        restrict_to: 'email_auth',
        email_auth_enabled: true,
        sso_enabled: false,
      });
    });

    it('updates signinConfig after successful save', async () => {
      const updatedConfig: CustomDomainSigninConfig = {
        ...mockSigninConfigData,
        sso_enabled: true,
      };
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockPutConfigForDomain.mockResolvedValue({ record: updatedConfig });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        enabled: true,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: true,
        sso_enabled: true,
      };

      await composable.saveConfig();

      expect(composable.signinConfig.value).toEqual(updatedConfig);
    });

    it('updates savedFormState snapshot after successful save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockPutConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        enabled: true,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: true,
        sso_enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);

      await composable.saveConfig();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('shows success notification after save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        enabled: true,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: false,
        sso_enabled: false,
      };

      await composable.saveConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Signin configuration updated',
        'success',
        'top'
      );
    });

    it('sets isSaving during operation', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      let resolveSave: (value: unknown) => void;
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveSave = resolve;
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        enabled: true,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: false,
        sso_enabled: false,
      };

      const savePromise = composable.saveConfig();
      expect(composable.isSaving.value).toBe(true);

      resolveSave!({ record: mockSigninConfigData });
      await savePromise;

      expect(composable.isSaving.value).toBe(false);
    });

    it('resets isSaving even when save fails', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      mockPutConfigForDomain.mockRejectedValue(new Error('Network error'));

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        enabled: true,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: false,
        sso_enabled: false,
      };

      await composable.saveConfig();

      expect(composable.isSaving.value).toBe(false);
    });

    it('does not update state when wrapAction returns undefined (error)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      mockPutConfigForDomain.mockRejectedValue(new Error('Server error'));

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const originalConfig = composable.signinConfig.value;

      composable.formState.value = {
        ...composable.formState.value,
        sso_enabled: true,
      };

      await composable.saveConfig();

      // signinConfig should not have changed since wrapAction returned undefined
      expect(composable.signinConfig.value).toEqual(originalConfig);
    });

    it('sends restrict_to: null when clearing restriction', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockRestrictedConfig });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        restrict_to: null,
      };

      await composable.saveConfig();

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ restrict_to: null })
      );
    });
  });

  // ---------------------------------------------------------------------------
  // deleteConfig
  // ---------------------------------------------------------------------------

  describe('deleteConfig', () => {
    it('resets signinConfig to null after deletion', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(true);

      await composable.deleteConfig();

      expect(composable.signinConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
    });

    it('resets formState to defaults after deletion', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(composable.formState.value).toEqual({
        enabled: false,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: false,
        sso_enabled: false,
      });
    });

    it('resets savedFormState so hasUnsavedChanges is false', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('calls SigninConfigService.deleteConfigForDomain with correct extid', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-456');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockDeleteConfigForDomain).toHaveBeenCalledWith('dm-ext-456');
    });

    it('shows success notification after deletion', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Signin configuration removed',
        'success',
        'top'
      );
    });

    it('sets isDeleting during operation', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      let resolveDelete: (value: unknown) => void;
      mockDeleteConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveDelete = resolve;
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const deletePromise = composable.deleteConfig();
      expect(composable.isDeleting.value).toBe(true);

      resolveDelete!({ success: true });
      await deletePromise;

      expect(composable.isDeleting.value).toBe(false);
    });

    it('preserves state when delete throws (error inside wrapAction)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      mockDeleteConfigForDomain.mockRejectedValue(new Error('Permission denied'));

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const originalConfig = composable.signinConfig.value;

      await composable.deleteConfig();

      // wrapAction swallows the error, but the state reset happens inside
      // the callback before the throw, so signinConfig is actually reset.
      // However, since deleteConfig throws inside wrapAction callback and
      // wrap returns undefined, the code after deleteConfigForDomain doesn't run.
      // The service call throws, so signinConfig.value remains unchanged.
      expect(composable.signinConfig.value).toEqual(originalConfig);
      expect(composable.isDeleting.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // hasUnsavedChanges
  // ---------------------------------------------------------------------------

  describe('hasUnsavedChanges', () => {
    it('returns false immediately after initialization', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns true when enabled is toggled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when signin_enabled is toggled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        signin_enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when restrict_to is changed from null to a value', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        restrict_to: 'password',
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when email_auth_enabled is toggled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        email_auth_enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns true when sso_enabled is toggled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        sso_enabled: true,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns false when changes are reverted to original values', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      // Modify
      composable.formState.value = {
        ...composable.formState.value,
        sso_enabled: true,
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      // Revert
      composable.formState.value = {
        ...composable.formState.value,
        sso_enabled: false,
      };
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns false before initialization (no savedFormState)', () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns false after discardChanges', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        enabled: false,
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // discardChanges
  // ---------------------------------------------------------------------------

  describe('discardChanges', () => {
    it('restores all fields from savedFormState', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const originalFormData = { ...composable.formState.value };

      // Modify multiple fields
      composable.formState.value = {
        enabled: false,
        signin_enabled: false,
        restrict_to: 'webauthn',
        email_auth_enabled: false,
        sso_enabled: true,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.formState.value).toEqual(originalFormData);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('is a no-op when savedFormState is null (before init)', () => {
      const composable = useSigninConfig('dm-ext-123');

      // Should not throw
      composable.discardChanges();

      // formState should remain at defaults
      expect(composable.formState.value).toEqual({
        enabled: false,
        signin_enabled: true,
        restrict_to: null,
        email_auth_enabled: false,
        sso_enabled: false,
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------

  describe('initial state', () => {
    it('starts with isLoading true', () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.isLoading.value).toBe(true);
    });

    it('starts with isInitialized false', () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.isInitialized.value).toBe(false);
    });

    it('starts with isSaving false', () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.isSaving.value).toBe(false);
    });

    it('starts with isDeleting false', () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.isDeleting.value).toBe(false);
    });

    it('starts with error null', () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.error.value).toBeNull();
    });

    it('starts with signinConfig null', () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.signinConfig.value).toBeNull();
    });
  });

  // ---------------------------------------------------------------------------
  // Computed properties
  // ---------------------------------------------------------------------------

  describe('computed properties', () => {
    it('isConfigured returns true when signinConfig is not null', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(true);
    });

    it('isConfigured returns false when signinConfig is null', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(false);
    });
  });
});
