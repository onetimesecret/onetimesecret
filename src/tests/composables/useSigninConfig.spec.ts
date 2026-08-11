// src/tests/composables/useSigninConfig.spec.ts
//
// Tests for useSigninConfig composable covering:
// 1. initialize(): null record = unconfigured, populates formState from config
// 2. saveConfig(): PUT full replacement with all 5 boolean/enum fields
// 3. deleteConfig(): unpins and reseeds from inherited state
// 4. hasUnsavedChanges: detects field modifications
// 5. discardChanges(): restores saved state
// 6. ADR-024: seeding from inherited state, writes-materialize pinning, and
//    the override display state (workspace-default vs explicitly-configured)

import { useSigninConfig } from '@/shared/composables/useSigninConfig';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

import type { EffectiveRestrictTo } from '@/schemas/api/domains/responses/signin-config';
import type {
  CustomDomainSigninConfig,
  SigninRestrictTo,
} from '@/schemas/shapes/domains/signin-config';

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

// Bootstrap features drive the SEEDED method-availability flags for
// unconfigured domains (ADR-024). undefined features = every method
// available (codebase convention: absent flag means enabled).
const mockFeatures = ref<Record<string, unknown> | undefined>(undefined);

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({ features: mockFeatures.value }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => {
      const translations: Record<string, string> = {
        'web.domains.signin.update_success': 'Signin configuration updated',
        // The "delete" flow was renamed to "reset to defaults"; the success
        // notification key moved delete_success → reset_success. The action
        // (deleteConfig / DELETE of the record) is unchanged.
        'web.domains.signin.reset_success': 'Signin configuration reset to defaults',
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

// Wire form of the server's restrict_to resolution (ADR-024 A4). The
// composable consumes this verbatim; nothing in the client re-derives it.
const unrestricted = (source: 'global' | 'domain' = 'global'): EffectiveRestrictTo => ({
  state: 'unrestricted',
  restrict_to: null,
  source,
});

const restricted = (
  method: SigninRestrictTo,
  source: 'global' | 'domain' = 'global'
): EffectiveRestrictTo => ({ state: 'restricted', restrict_to: method, source });

const unavailable = (
  method: SigninRestrictTo,
  source: 'global' | 'domain' | 'conflict' = 'domain'
): EffectiveRestrictTo => ({ state: 'unavailable', restrict_to: method, source });

// Resolution details for an unconfigured domain under an enabled global:
// default-off resolver output (#3814). `details` is required on GET/PUT
// responses — a response without it is a failed load, never a seedable
// state (PR #3817).
const mockUnconfiguredDetails = {
  global_enabled: true,
  effective_enabled: false,
  global_restrict_to: null,
  effective_restrict_to: unrestricted(),
};

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

describe('useSigninConfig', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mockFeatures.value = undefined; // all methods globally available

    // Default: no existing config (unconfigured) with resolution details —
    // the modern backend always sends details; a details-less response is a
    // failed load (covered explicitly below).
    mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
    mockPutConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
    mockDeleteConfigForDomain.mockResolvedValue({ success: true });
  });

  // ---------------------------------------------------------------------------
  // initialize
  // ---------------------------------------------------------------------------

  describe('initialize', () => {
    it('sets signinConfig to null when domain is unconfigured', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.signinConfig.value).toBeNull();
      expect(composable.isConfigured.value).toBe(false);
      expect(composable.isInitialized.value).toBe(true);
    });

    it('fails initialization when the response has neither record nor details (older-backend 404 / failed parse)', async () => {
      // The seed is a guess about the inherited state; an autosave would
      // materialize it as an explicit override — on an SSO-only domain that
      // would persist signin_enabled: false and disable sign-in (PR #3817).
      // Fail loudly instead: error set, never initialized.
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: null });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.error.value?.message).toBe('An unexpected error occurred');
      expect(composable.isInitialized.value).toBe(false);
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

    it('does not seed or snapshot on a details-less response (nothing to materialize)', async () => {
      // Companion to the fail-loud contract: the failed initialize must leave
      // no saved snapshot behind — savedFormState stays null, so there is no
      // materializable state for a later save to persist.
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: null });

      const composable = useSigninConfig('dm-ext-123');
      const placeholder = { ...composable.formState.value };
      await composable.initialize();

      expect(composable.formState.value).toEqual(placeholder);
      expect(composable.hasUnsavedChanges.value).toBe(false);
      expect(composable.details.value).toBeNull();
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

    it('defaults a null or missing signin_enabled to false (conservative default, #3814)', async () => {
      // The shape types signin_enabled as boolean, but the mocked service
      // bypasses Zod parsing, so a legacy/unparsed record can reach
      // configToFormState with signin_enabled null. The fallback must be OFF:
      // custom domains are default-off opt-in, matching useSignupConfig.
      const configWithNullSignin = {
        ...mockSigninConfigData,
        signin_enabled: null,
      } as unknown as CustomDomainSigninConfig;
      mockGetConfigForDomain.mockResolvedValue({ record: configWithNullSignin });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.signin_enabled).toBe(false);

      const { signin_enabled: _omit, ...configWithoutSignin } = mockSigninConfigData;
      mockGetConfigForDomain.mockResolvedValue({
        record: configWithoutSignin as unknown as CustomDomainSigninConfig,
      });

      const fresh = useSigninConfig('dm-ext-123');
      await fresh.initialize();

      expect(fresh.formState.value.signin_enabled).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // saveConfig
  // ---------------------------------------------------------------------------

  describe('saveConfig', () => {
    it('sends all form fields in PUT payload', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
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
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
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
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
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
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
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
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
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
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
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
  // autoSaveField (save-on-change toggles)
  // ---------------------------------------------------------------------------

  describe('autoSaveField', () => {
    it('updates the field then persists via PUT', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      mockPutConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, sso_enabled: true },
      });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.autoSaveField('sso_enabled', true);

      // PUT carries the optimistic value; form then reflects the saved record.
      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ sso_enabled: true })
      );
      expect(composable.formState.value.sso_enabled).toBe(true);
    });

    it('commits other pending edits in the same full-replacement PUT', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      // A pending radio change that has not been saved yet.
      composable.formState.value = {
        ...composable.formState.value,
        restrict_to: 'sso',
      };

      // Flipping a toggle auto-saves and carries the pending radio change.
      await composable.autoSaveField('sso_enabled', true);

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ restrict_to: 'sso', sso_enabled: true })
      );
    });

    it('exposes savingField while the save is in flight, clears it after', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      let resolveSave: (value: unknown) => void;
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveSave = resolve;
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.autoSaveField('email_auth_enabled', true);
      expect(composable.savingField.value).toBe('email_auth_enabled');

      resolveSave!({ record: mockSigninConfigData });
      await promise;

      expect(composable.savingField.value).toBeNull();
    });

    it('clears savingField even when the save fails', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      mockPutConfigForDomain.mockRejectedValue(new Error('Network error'));

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.autoSaveField('sso_enabled', true);

      expect(composable.savingField.value).toBeNull();
    });

    it('reverts formState to the saved snapshot when the PUT fails', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      mockPutConfigForDomain.mockRejectedValue(new Error('Network error'));

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();
      // Baseline: unconfigured -> seeded form state (sso_enabled true, all
      // methods globally available).

      await composable.autoSaveField('sso_enabled', false);

      // The optimistic flip is rolled back so the toggle matches server state
      // instead of silently desyncing.
      expect(composable.formState.value.sso_enabled).toBe(true);
      expect(composable.hasUnsavedChanges.value).toBe(false);
    });

    it('queues a call arriving while a save is in flight and drains it after', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      const resolvers: Array<(value: unknown) => void> = [];
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolvers.push(resolve);
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const first = composable.autoSaveField('sso_enabled', false);
      // Second call while the first is in flight queues — no second PUT yet,
      // and the queued patch is NOT merged into formState until its own save
      // runs (saveConfig's settle paths would clobber an early merge).
      await composable.autoSaveField('email_auth_enabled', false);

      expect(composable.formState.value.email_auth_enabled).toBe(true);
      expect(mockPutConfigForDomain).toHaveBeenCalledTimes(1);

      resolvers[0]!({ record: mockSigninConfigData });
      await vi.waitFor(() => expect(mockPutConfigForDomain).toHaveBeenCalledTimes(2));
      // The drained PUT carries the queued change.
      expect(mockPutConfigForDomain).toHaveBeenLastCalledWith(
        'dm-ext-123',
        expect.objectContaining({ email_auth_enabled: false })
      );

      resolvers[1]!({ record: { ...mockSigninConfigData, email_auth_enabled: false } });
      await first;
      expect(composable.formState.value.email_auth_enabled).toBe(false);
    });

    it('leaves hasUnsavedChanges false after a clean auto-save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      mockPutConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, sso_enabled: true },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.autoSaveField('sso_enabled', true);

      expect(composable.hasUnsavedChanges.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // autoSaveFields (multi-key partial save — invariants 5 & 6)
  //
  // autoSaveField (single key) is covered above; it delegates to autoSaveFields,
  // so the queue-while-saving and finally-clear behaviors are already exercised
  // transitively. This block covers the multi-key path the component uses for
  // the atomic restrict_to + availability-flag commit, plus the signin_enabled
  // passthrough no UI touches.
  // ---------------------------------------------------------------------------

  describe('autoSaveFields', () => {
    it('merges a multi-key partial and sends all of it in one full-replacement PUT', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      mockPutConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, restrict_to: 'sso', sso_enabled: true },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      // The Mode B pick: restrict_to + its availability flag, atomically.
      await composable.autoSaveFields({ restrict_to: 'sso', sso_enabled: true });

      expect(mockPutConfigForDomain).toHaveBeenCalledTimes(1);
      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ restrict_to: 'sso', sso_enabled: true })
      );
      // Both fields landed in formState via the merge.
      expect(composable.formState.value.restrict_to).toBe('sso');
      expect(composable.formState.value.sso_enabled).toBe(true);
    });

    it('attributes savingField to the explicit hint when provided', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      let resolveSave: (value: unknown) => void;
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveSave = resolve;
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      // restrict_to comes first in the partial, but the hint pins the spinner
      // to restrict_to anyway (the component passes 'restrict_to' as the hint).
      const promise = composable.autoSaveFields(
        { restrict_to: 'email_auth', email_auth_enabled: true },
        'restrict_to'
      );
      expect(composable.savingField.value).toBe('restrict_to');

      resolveSave!({ record: mockSigninConfigData });
      await promise;
      expect(composable.savingField.value).toBeNull();
    });

    it('defaults savingField to the first partial key when no hint is given', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      let resolveSave: (value: unknown) => void;
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveSave = resolve;
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const promise = composable.autoSaveFields({ email_auth_enabled: true, sso_enabled: true });
      // First key of the partial drives the spinner attribution.
      expect(composable.savingField.value).toBe('email_auth_enabled');

      resolveSave!({ record: mockSigninConfigData });
      await promise;
    });

    it('preserves signin_enabled untouched through an unrelated auto-save (passthrough)', async () => {
      // signin_enabled has no UI control on the form. A patch that changes
      // another field must spread-merge it through unchanged, and the PUT must
      // still carry it.
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, signin_enabled: true },
      });
      mockPutConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, signin_enabled: true, sso_enabled: true },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();
      expect(composable.formState.value.signin_enabled).toBe(true);

      await composable.autoSaveFields({ sso_enabled: true }, 'sso_enabled');

      // The PUT carried signin_enabled even though the patch never named it.
      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ signin_enabled: true, sso_enabled: true })
      );
    });

    it('queues a concurrent multi-key call and applies it after the in-flight save', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      const resolvers: Array<(value: unknown) => void> = [];
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolvers.push(resolve);
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const first = composable.autoSaveFields(
        { restrict_to: 'sso', sso_enabled: true },
        'restrict_to'
      );
      // Second concurrent multi-key call queues; mid-flight formState still
      // holds the first patch only.
      await composable.autoSaveFields({ restrict_to: 'password' }, 'restrict_to');

      expect(mockPutConfigForDomain).toHaveBeenCalledTimes(1);
      expect(composable.formState.value.restrict_to).toBe('sso');

      resolvers[0]!({ record: mockRestrictedConfig });
      await vi.waitFor(() => expect(mockPutConfigForDomain).toHaveBeenCalledTimes(2));
      expect(mockPutConfigForDomain).toHaveBeenLastCalledWith(
        'dm-ext-123',
        expect.objectContaining({ restrict_to: 'password' })
      );

      resolvers[1]!({ record: { ...mockSigninConfigData, restrict_to: 'password' } });
      await first;
      expect(composable.formState.value.restrict_to).toBe('password');
    });

    it('coalesces multiple queued patches into one follow-up PUT (later keys win)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      const resolvers: Array<(value: unknown) => void> = [];
      mockPutConfigForDomain.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolvers.push(resolve);
          })
      );

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      const first = composable.autoSaveFields({ sso_enabled: true }, 'sso_enabled');
      await composable.autoSaveFields({ restrict_to: 'sso' });
      await composable.autoSaveFields({ restrict_to: 'email_auth', email_auth_enabled: true });

      expect(mockPutConfigForDomain).toHaveBeenCalledTimes(1);

      resolvers[0]!({ record: mockSigninConfigData });
      // Both queued patches drain as ONE merged PUT, later restrict_to winning.
      await vi.waitFor(() => expect(mockPutConfigForDomain).toHaveBeenCalledTimes(2));
      expect(mockPutConfigForDomain).toHaveBeenLastCalledWith(
        'dm-ext-123',
        expect.objectContaining({ restrict_to: 'email_auth', email_auth_enabled: true })
      );

      resolvers[1]!({
        record: { ...mockSigninConfigData, restrict_to: 'email_auth', email_auth_enabled: true },
      });
      await first;
      expect(mockPutConfigForDomain).toHaveBeenCalledTimes(2);
      expect(composable.formState.value.restrict_to).toBe('email_auth');
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

    it('reseeds formState from inherited state after deletion (unpin returns to workspace defaults)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: mockSigninConfigData });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.deleteConfig();

      // No details on the DELETE response here, so the reseed uses the
      // default-off signin fallback (#3814) + bootstrap method availability
      // (all available).
      expect(composable.formState.value).toEqual({
        enabled: false,
        signin_enabled: false,
        restrict_to: null,
        email_auth_enabled: true,
        sso_enabled: true,
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

      // deleteConfig still performs the DELETE; only the success copy changed
      // (delete_success → reset_success) when the surface was renamed to "reset".
      expect(mockNotificationsShow).toHaveBeenCalledWith(
        'Signin configuration reset to defaults',
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

      // formState remains at the pre-init seed (no details yet: default-off
      // signin (#3814), method flags from bootstrap availability — all
      // available).
      expect(composable.formState.value).toEqual({
        enabled: false,
        signin_enabled: false,
        restrict_to: null,
        email_auth_enabled: true,
        sso_enabled: true,
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
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });
      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isConfigured.value).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-024: seeding from inherited state
  //
  // An UNCONFIGURED domain's form is seeded from the resolution details the
  // API returns (what actually runs), never from static defaults. The first
  // explicit save then materializes this snapshot plus the user's edit.
  // ---------------------------------------------------------------------------

  describe('ADR-024: seeding from inherited state', () => {
    it('seeds signin_enabled from details.effective_enabled (inherit: form shows the resolver output, not a static default)', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: false,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.signin_enabled).toBe(false);
    });

    it('seeds restrict_to from details.effective_restrict_to (the resolver output, not the raw global)', async () => {
      // Unconfigured non-SSO-tenant domain: default-off, so the resolver
      // reports effective_enabled false (#3814); restrict_to still seeds.
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: 'sso',
          effective_restrict_to: restricted('sso'),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.restrict_to).toBe('sso');
    });

    // ADR-024 A4 regression proof: the client used to seed from
    // global_restrict_to and re-derive what would actually run. Here the two
    // disagree — the install restricts to SSO, but the resolver says this
    // host resolves unrestricted. Seeding from the raw global would pin (and,
    // on the next autosave, persist) a restriction the server did not resolve.
    it('ignores global_restrict_to when the resolver disagrees with it', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: true,
          global_restrict_to: 'sso',
          effective_restrict_to: unrestricted('domain'),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.restrict_to).toBeNull();
    });

    // :unavailable keeps the named method. Seeding null would read as "no
    // restriction" and the next autosave would persist that widening — the
    // exact fail-open ADR-024 A3 closes.
    it('seeds the named method when the resolution is unavailable', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unavailable('webauthn'),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.restrict_to).toBe('webauthn');
      expect(composable.isRestrictionUnavailable.value).toBe(true);
    });

    // A conflict (global and domain naming different methods, ADR-024 A8)
    // resolves unavailable and names the GLOBAL method. The client cannot
    // derive this from global_restrict_to and the record; it reads the field.
    it('surfaces a conflict resolution as unavailable', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: 'password',
          effective_restrict_to: unavailable('password', 'conflict'),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.effectiveRestrictTo.value?.source).toBe('conflict');
      expect(composable.isRestrictionUnavailable.value).toBe(true);
    });

    it('exposes the resolver output verbatim, all three states included', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: restricted('email_auth', 'domain'),
          tenant_sso: { available: false, unavailable_reason: 'sso_config_disabled' },
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.effectiveRestrictTo.value).toEqual({
        state: 'restricted',
        restrict_to: 'email_auth',
        source: 'domain',
      });
      expect(composable.isRestrictionUnavailable.value).toBe(false);
      expect(composable.tenantSso.value).toEqual({
        available: false,
        unavailable_reason: 'sso_config_disabled',
      });
    });

    it('seeds email_auth from global availability (AND semantics: a globally-off method seeds as off, not on)', async () => {
      mockFeatures.value = { email_auth: false, webauthn: true, sso: { enabled: false } };
      // Unconfigured domain, SSO globally off → no carve-out: default-off
      // resolver output (#3814).
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.email_auth_enabled).toBe(false);
    });

    it('seeds sso_enabled true regardless of the PLATFORM sso feature flag', async () => {
      // sso_enabled is the TENANT-SSO activation gate consumed by
      // SigninConfig.sso_permitted_for?, which returns true unconditionally
      // while no config is enabled — so `true` is the inherited state for
      // every unconfigured domain. Bootstrap `features.sso` is the unrelated
      // PLATFORM switch (AUTH_SSO_ENABLED, resolved against the workspace
      // host); seeding from it is what let an autosave persist
      // sso_enabled: false and take a domain's live tenant SSO down.
      mockFeatures.value = { email_auth: true, webauthn: true, sso: { enabled: false } };
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.sso_enabled).toBe(true);
    });

    it('an unrelated autosave on an unconfigured domain never persists sso_enabled: false', async () => {
      // The regression proof for the data bug. Platform SSO off, domain
      // unconfigured; the user flips the email toggle — the first thing that
      // materializes an explicit override. The PUT must not carry
      // sso_enabled: false, which would flip sso_permitted_for? to false and
      // dark the domain's tenant SSO buttons. Same failure class as the
      // PR #3817 signin_enabled bug.
      mockFeatures.value = { email_auth: true, webauthn: true, sso: { enabled: false } };
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: true,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();
      await composable.autoSaveField('email_auth_enabled', false);

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: true, sso_enabled: true, email_auth_enabled: false })
      );
    });

    it('an explicit record wins over seeding (explicit: formState comes from the stored override, not the inherited state)', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, signin_enabled: false },
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.signin_enabled).toBe(false);
      expect(composable.formState.value.enabled).toBe(true);
    });

    it('SSO-only tenant carve-out: unconfigured domain with effective_enabled true seeds signin_enabled true (resolver output passes through)', async () => {
      // #3814: unconfigured custom domains are default-off (effective_enabled
      // false) EXCEPT when the tenant has SSO available and no SigninConfig —
      // the masthead SSO carve-out. The backend resolver reports true in that
      // case and the frontend does nothing special: it seeds whatever the
      // resolver reports.
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: true,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.formState.value.signin_enabled).toBe(true);
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-024: writes materialize an explicit override (pinning)
  //
  // Every save from the settings UI forces enabled: true through the
  // asExplicitOverride chokepoint. This is what pins a domain against future
  // changes to the workspace defaults — and what prevents the latent bug of
  // enabled=false records the resolver ignores.
  // ---------------------------------------------------------------------------

  describe('ADR-024: writes materialize an explicit override (pinning)', () => {
    it('saveConfig forces enabled: true in the PUT even while formState.enabled is false (saving = pinning)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();
      expect(composable.formState.value.enabled).toBe(false);

      await composable.saveConfig();

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: true })
      );
    });

    it('autoSave pins too: a single toggle flip on an unconfigured domain sends enabled: true (never an enabled=false record)', async () => {
      mockGetConfigForDomain.mockResolvedValue({ record: null, details: mockUnconfiguredDetails });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.autoSaveField('sso_enabled', false);

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: true, sso_enabled: false })
      );
    });

    it('an empty autoSaveFields patch still PUTs the full seeded snapshot with enabled: true (pin-without-value-change)', async () => {
      // The form emits an empty patch when a workspace-default domain's user
      // clicks the mode that already matches the inherited state. Unconfigured
      // domain: default-off resolver output (#3814), so the seeded snapshot
      // carries signin_enabled false.
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      await composable.autoSaveFields({}, 'restrict_to');

      expect(mockPutConfigForDomain).toHaveBeenCalledWith(
        'dm-ext-123',
        expect.objectContaining({ enabled: true, signin_enabled: false, restrict_to: null })
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-024: override display state
  //
  // The banner never re-derives availability from the raw flag pair; it
  // renders the resolver output (details) plus the workspace-default flag.
  // ---------------------------------------------------------------------------

  describe('ADR-024: override display state', () => {
    it('no record → isWorkspaceDefault (inherit), not explicitly configured', async () => {
      // Unconfigured domain: default-off resolver output (#3814). The badge
      // is driven by record.enabled, not effective_enabled.
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isWorkspaceDefault.value).toBe(true);
      expect(composable.isExplicitlyConfigured.value).toBe(false);
    });

    it('a legacy record with enabled=false still counts as workspace default (the resolver ignores it)', async () => {
      // The resolver treats an enabled=false record like no record at all,
      // so the domain resolves default-off (#3814).
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, enabled: false },
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isWorkspaceDefault.value).toBe(true);
      expect(composable.isExplicitlyConfigured.value).toBe(false);
    });

    it('a record with enabled=true is explicitly configured (pinned)', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: mockSigninConfigData,
        details: {
          global_enabled: true,
          effective_enabled: true,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isWorkspaceDefault.value).toBe(false);
      expect(composable.isExplicitlyConfigured.value).toBe(true);
    });

    it('globalEnabled/effectiveEnabled surface the details verbatim; null before any load', async () => {
      const composable = useSigninConfig('dm-ext-123');
      expect(composable.globalEnabled.value).toBeNull();
      expect(composable.effectiveEnabled.value).toBeNull();

      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });
      await composable.initialize();

      expect(composable.globalEnabled.value).toBe(true);
      expect(composable.effectiveEnabled.value).toBe(false);
    });

    it('isGloballyDisabled tracks the kill switch (global off ⇒ dormant), independent of per-domain flags', async () => {
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, signin_enabled: true },
        details: {
          global_enabled: false,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();

      expect(composable.isGloballyDisabled.value).toBe(true);
    });

    it('PUT response details refresh the display state (effective flips with the save, no refetch)', async () => {
      // Unconfigured domain starts default-off (#3814); explicitly enabling
      // signin flips the resolver output to true via the PUT response details.
      mockGetConfigForDomain.mockResolvedValue({
        record: null,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });
      mockPutConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, signin_enabled: true },
        details: {
          global_enabled: true,
          effective_enabled: true,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();
      expect(composable.effectiveEnabled.value).toBe(false);

      await composable.autoSaveField('signin_enabled', true);

      expect(composable.effectiveEnabled.value).toBe(true);
      expect(composable.isWorkspaceDefault.value).toBe(false);
    });

    it('deleteConfig unpins: DELETE response details reseed the form to the inherited state', async () => {
      // Explicitly-enabled record → effective true; deleting it returns the
      // domain to the unconfigured default-off state (#3814), and the reseed
      // reflects that resolution without a refetch.
      mockGetConfigForDomain.mockResolvedValue({
        record: { ...mockSigninConfigData, signin_enabled: true },
        details: {
          global_enabled: true,
          effective_enabled: true,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });
      mockDeleteConfigForDomain.mockResolvedValue({
        success: true,
        details: {
          global_enabled: true,
          effective_enabled: false,
          global_restrict_to: null,
          effective_restrict_to: unrestricted(),
        },
      });

      const composable = useSigninConfig('dm-ext-123');
      await composable.initialize();
      expect(composable.formState.value.signin_enabled).toBe(true);

      await composable.deleteConfig();

      // Back to workspace defaults: custom domains are default-off, so the
      // post-delete resolution reports signin unavailable and the form
      // reseeds to false.
      expect(composable.isWorkspaceDefault.value).toBe(true);
      expect(composable.effectiveEnabled.value).toBe(false);
      expect(composable.formState.value.signin_enabled).toBe(false);
    });
  });
});
