// src/tests/composables/useSignupConfig.spec.ts
//
// Tests for useSignupConfig composable covering:
// 1. initialize(): null record = unconfigured, populates formState from config
// 2. saveConfig(): PUT full replacement with strategy-conditional allowlist
// 3. deleteConfig(): unpins and reseeds from inherited state
// 4. hasUnsavedChanges / discardChanges: form lifecycle
// 5. ADR-024 / #3814: seeding signup_enabled from details.effective_enabled
//    (custom domains are default-off opt-in; null details fall back to false)
//    and the writes-materialize pinning (asExplicitOverride).
//
// Mirrors the structure of useSigninConfig.spec.ts for the paths the two
// composables share. Signup has no autoSaveField/autoSaveFields and no
// bootstrap-driven method flags, so those blocks have no equivalent here.

import { useSignupConfig } from '@/shared/composables/useSignupConfig';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { CustomDomainSignupConfig } from '@/schemas/shapes/domains/signup-config';

// -----------------------------------------------------------------------------
// Mock Setup
// -----------------------------------------------------------------------------

const mockGetConfigForDomain = vi.fn();
const mockPutConfigForDomain = vi.fn();
const mockDeleteConfigForDomain = vi.fn();
const mockNotificationsShow = vi.fn();
const mockRouterPush = vi.fn();

vi.mock('@/services/signup-config.service', () => ({
  SignupConfigService: {
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
        'web.domains.signup.update_success': 'Signup configuration updated',
        'web.domains.signup.delete_success': 'Signup configuration deleted',
        'web.COMMON.unexpected_error': 'An unexpected error occurred',
      };
      return translations[key] ?? key;
    },
  }),
}));

// Mirrors the real wrap error-boundary: catches, forwards to onError (which
// the composable uses to set error.value), returns undefined. Without the
// onError forwarding, the fail-loud initialize contract would be untestable.
vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: (options?: { onError?: (err: unknown) => void }) => ({
    wrap: vi.fn(async (fn: () => Promise<unknown>) => {
      try {
        return await fn();
      } catch (err) {
        options?.onError?.(err);
        return undefined;
      }
    }),
  }),
  createError: vi.fn(),
}));

// -----------------------------------------------------------------------------
// Test Fixtures
// -----------------------------------------------------------------------------

const mockSignupConfigData: CustomDomainSignupConfig = {
  domain_id: 'domain-123',
  validation_strategy: 'domain_allowlist',
  allowed_signup_domains: ['acme.com', 'partner.com'],
  enabled: true,
  signup_enabled: true,
  autoverify: false,
  requires_allowlist: true,
  network_validation: false,
  created_at: new Date('2025-01-01T00:00:00Z'),
  updated_at: new Date('2025-01-15T10:00:00Z'),
};

const mockPassthroughConfig: CustomDomainSignupConfig = {
  ...mockSignupConfigData,
  validation_strategy: 'passthrough',
  allowed_signup_domains: [],
  requires_allowlist: false,
};

// Resolution details for an unconfigured domain under an enabled global:
// default-off resolver output (#3814). `details` is required on GET/PUT
// responses — a response without it is a failed load, never a seedable
// state (PR #3817).
const mockUnconfiguredDetails = {
  global_enabled: true,
  effective_enabled: false,
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

describe('useSignupConfig', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    // Default: no existing config (unconfigured) with resolution details —
    // the modern backend always sends details; a details-less response is a
    // failed load (covered explicitly below).
    mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
    mockPutConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
    mockDeleteConfigForDomain.mockResolvedValue({ success: true });
  });

  // ---------------------------------------------------------------------------
  // initialize
  // ---------------------------------------------------------------------------

  describe('initialize', () => {
    it('sets signupConfig to null when domain is unconfigured', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.signupConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
      expect(composable.isInitialized.value).toBe(true);
    });

    it('populates formState from existing config', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.signupConfig.value).toEqual(mockSignupConfigData);
      expect(composable.formState.value).toEqual({
        validation_strategy: 'domain_allowlist',
        allowed_signup_domains: ['acme.com', 'partner.com'],
        enabled: true,
        signup_enabled: true,
        autoverify: false,
      });
      expect(composable.isConfigured.value).toBe(true);
    });

    it('fails initialization when the response has neither record nor details (older-backend 404 / failed parse)', async () => {
      // The seed is a guess about the inherited state; a save would
      // materialize it as an explicit override (PR #3817, mirroring
      // useSigninConfig). Fail loudly instead: error set, never initialized,
      // no saved snapshot to persist.
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: null });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.error.value?.message).toBe('An unexpected error occurred');
      expect(composable.isInitialized.value).toBe(false);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('snapshots savedFormState on load', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('calls SignupConfigService.getConfigForDomain with correct extid', async () => {
      const composable = useSignupConfig('dm-ext-456');
      await composable.initialize();

      expect(mockGetConfigForDomain).toHaveBeenCalledWith('dm-ext-456');
    });
  });

  // ---------------------------------------------------------------------------
  // saveConfig
  // ---------------------------------------------------------------------------

  describe('saveConfig', () => {
    it('sends strategy, signup_enabled, autoverify and allowlist in PUT payload (domain_allowlist)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        validation_strategy: 'domain_allowlist',
        allowed_signup_domains: ['acme.com'],
        enabled: true,
        signup_enabled: true,
        autoverify: true,
      };

      await composable.saveConfig();

      expect(mockPutConfigForDomain).toHaveBeenCalledWith('dm-ext-123', {
        validation_strategy: 'domain_allowlist',
        allowed_signup_domains: ['acme.com'],
        enabled: true,
        signup_enabled: true,
        autoverify: true,
      });
    });

    it('omits allowed_signup_domains when strategy does not use it (PUT semantics clear it server-side)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        validation_strategy: 'passthrough',
      };

      await composable.saveConfig();

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.not.objectContaining({ allowed_signup_domains: expect.anything() })
      );
    });

    it('updates signupConfig and snapshot after successful save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      mockPutConfigForDomain.mockResolvedValue({ record: mockPassthroughConfig });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        signup_enabled: true,
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      await composable.saveConfig();

      expect(composable.signupConfig.value).toEqual(mockPassthroughConfig);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('shows success notification after save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      await composable.saveConfig();

      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Signup configuration updated',
        'success',
        'top'
      );
    });

    it('sets isSaving during operation and clears it after', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      let resolveSave: (value: unknown) => void;
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveSave = resolve;
          })
      );

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      const savePromise = composable.saveConfig();
      expect(composable.isSaving.value).toBe(true);

      resolveSave!({ record: mockSignupConfigData });
      await savePromise;

      expect(composable.isSaving.value).toBe(false);
    });

    it('resets isSaving and preserves state when save fails', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      mockPutConfigForDomain.mockRejectedValue(new Error('Server error'));

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      const originalConfig = composable.signupConfig.value;
      composable.formState.value = {
        ...composable.formState.value,
        autoverify: true,
      };

      await composable.saveConfig();

      expect(composable.isSaving.value).toBe(false);
      expect(composable.signupConfig.value).toEqual(originalConfig);
    });
  });

  // ---------------------------------------------------------------------------
  // deleteConfig
  // ---------------------------------------------------------------------------

  describe('deleteConfig', () => {
    it('resets signupConfig to null after deletion', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(true);

      await composable.deleteConfig();

      expect(composable.signupConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
    });

    it('reseeds formState from inherited state after deletion (no details: default-off fallback)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      expect(composable.formState.value).toEqual({
        validation_strategy: 'passthrough',
        allowed_signup_domains: [],
        enabled: false,
        signup_enabled: false,
        autoverify: false,
      });
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('calls SignupConfigService.deleteConfigForDomain with correct extid and notifies', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-456');
      await composable.initialize();

      await composable.deleteConfig();

      expect(mockDeleteConfigForDomain).toHaveBeenCalledWith('dm-ext-456');
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Signup configuration deleted',
        'success',
        'top'
      );
    });

    it('sets isDeleting during operation and preserves state when delete throws', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      mockDeleteConfigForDomain.mockRejectedValue(new Error('Permission denied'));

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      const originalConfig = composable.signupConfig.value;

      await composable.deleteConfig();

      // The service call is the first statement in the wrapAction callback
      // and throws, so the state reset after it never runs.
      expect(composable.signupConfig.value).toEqual(originalConfig);
      expect(composable.isDeleting.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // hasUnsavedChanges / discardChanges
  // ---------------------------------------------------------------------------

  describe('hasUnsavedChanges', () => {
    it('returns true when signup_enabled is toggled', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        signup_enabled: false,
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('treats allowlist reordering as unchanged (order-insensitive compare)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        allowed_signup_domains: ['partner.com', 'acme.com'],
      };

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('returns true when allowlist membership changes', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      composable.formState.value = {
        ...composable.formState.value,
        allowed_signup_domains: ['acme.com', 'other.com'],
      };

      expect(composable.hasUnsavedChanges.value).toBe(true);
    });

    it('returns false before initialization (no savedFormState)', () => {
      const composable = useSignupConfig('dm-ext-123');
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });
  });

  describe('discardChanges', () => {
    it('restores all fields from savedFormState', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSignupConfigData });
      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      const originalFormData = {
        ...composable.formState.value,
        allowed_signup_domains: [...composable.formState.value.allowed_signup_domains],
      };

      composable.formState.value = {
        validation_strategy: 'mx',
        allowed_signup_domains: [],
        enabled: false,
        signup_enabled: false,
        autoverify: true,
      };
      expect(composable.hasUnsavedChanges.value).toBe(true);

      composable.discardChanges();

      expect(composable.formState.value).toEqual(originalFormData);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('is a no-op when savedFormState is null (before init)', () => {
      const composable = useSignupConfig('dm-ext-123');

      composable.discardChanges();

      expect(composable.formState.value).toEqual({
        validation_strategy: 'passthrough',
        allowed_signup_domains: [],
        enabled: false,
        signup_enabled: false,
        autoverify: false,
      });
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-024 / #3814: seeding from inherited state
  //
  // An UNCONFIGURED domain's form is seeded from the resolution details the
  // API returns (what actually runs), never from the canonical follows-global
  // resolver. Custom domains are default-off opt-in for signup (#3814).
  // ---------------------------------------------------------------------------

  describe('ADR-024: seeding from inherited state (#3814)', () => {
    it('seeds signup_enabled false from details.effective_enabled false (default-off custom domain, global on)', async () => {
      // The #3814 shape: global signup is enabled but the unconfigured custom
      // domain resolves OFF. Before the fix this seeded true.
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: { global_enabled: true, effective_enabled: false },
      });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.signup_enabled).toBe(false);
    });

    it('seeds signup_enabled true from details.effective_enabled true (resolver output passes through)', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: { global_enabled: true, effective_enabled: true },
      });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.signup_enabled).toBe(true);
    });

    it('an explicit record wins over seeding', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSignupConfigData, signup_enabled: false },
        details: { global_enabled: true, effective_enabled: false },
      });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.signup_enabled).toBe(false);
      expect(composable.formState.value.enabled).toBe(true);
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-024: writes materialize an explicit override (pinning)
  // ---------------------------------------------------------------------------

  describe('ADR-024: writes materialize an explicit override (pinning)', () => {
    it('saveConfig forces enabled: true in the PUT even while formState.enabled is false (saving = pinning)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();
      expect(composable.formState.value.enabled).toBe(false);

      await composable.saveConfig();

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: true })
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-024: override display state
  // ---------------------------------------------------------------------------

  describe('ADR-024: override display state', () => {
    it('no record → isWorkspaceDefault; badge driven by record.enabled, not effective_enabled', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: { global_enabled: true, effective_enabled: false },
      });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isWorkspaceDefault.value).toBe(true);
      expect(composable.isExplicitlyConfigured.value).toBe(false);
      expect(composable.globalEnabled.value).toBe(true);
      expect(composable.effectiveEnabled.value).toBe(false);
    });

    it('a record with enabled=true is explicitly configured (pinned)', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: mockSignupConfigData,
        details: { global_enabled: true, effective_enabled: true },
      });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isWorkspaceDefault.value).toBe(false);
      expect(composable.isExplicitlyConfigured.value).toBe(true);
    });

    it('PUT response details refresh the display state (effective flips with the save, no refetch)', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: { global_enabled: true, effective_enabled: false },
      });
      mockPutConfigForDomain.mockResolvedValue({
        record: mockPassthroughConfig,
        details: { global_enabled: true, effective_enabled: true },
      });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();
      expect(composable.effectiveEnabled.value).toBe(false);

      composable.formState.value = {
        ...composable.formState.value,
        signup_enabled: true,
      };
      await composable.saveConfig();

      expect(composable.effectiveEnabled.value).toBe(true);
      expect(composable.isWorkspaceDefault.value).toBe(false);
    });

    it('deleteConfig unpins: DELETE response details reseed the form to the inherited default-off state', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: mockSignupConfigData,
        details: { global_enabled: true, effective_enabled: true },
      });
      mockDeleteConfigForDomain.mockResolvedValue({
        success: true,
        details: { global_enabled: true, effective_enabled: false },
      });

      const composable = useSignupConfig('dm-ext-123');
      await composable.initialize();
      expect(composable.formState.value.signup_enabled).toBe(true);

      await composable.deleteConfig();

      expect(composable.isWorkspaceDefault.value).toBe(true);
      expect(composable.effectiveEnabled.value).toBe(false);
      expect(composable.formState.value.signup_enabled).toBe(false);
    });
  });
});
