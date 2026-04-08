// src/shared/composables/useSsoConfig.ts

/**
 * Composable for managing per-domain SSO configuration.
 *
 * Follows the useEmailConfig lifecycle pattern:
 * - initialize: fetch current config (404 = unconfigured, not error)
 * - saveConfig: auto-selects PUT (new) vs PATCH (update) via SsoService
 * - deleteConfig: removes config
 * - testConnection: validates IdP connectivity before saving
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * @param domainExtId - Domain external ID for API calls
 */

import type { ApplicationError } from '@/schemas/errors';
import type {
  PutSsoConfigRequest,
  PatchSsoConfigRequest,
} from '@/schemas/api/domains/requests/sso-config';
import type {
  CustomDomainSsoConfig,
  SsoProviderType,
} from '@/schemas/shapes/sso-config';
import {
  SsoService,
  type TestSsoConnectionRequest,
  type TestSsoConnectionResponse,
} from '@/services/sso.service';
import { useNotificationsStore } from '@/shared/stores';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { type AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Form state for SSO configuration.
 *
 * Note: client_secret is write-only. It's never populated from API responses
 * (which return a masked value), only from user input.
 */
export interface SsoConfigFormState {
  provider_type: SsoProviderType;
  display_name: string;
  client_id: string;
  client_secret: string;
  tenant_id: string;
  issuer: string;
  allowed_domains: string[];
  enabled: boolean;
}

function createDefaultFormState(): SsoConfigFormState {
  return {
    provider_type: 'entra_id',
    display_name: '',
    client_id: '',
    client_secret: '',
    tenant_id: '',
    issuer: '',
    allowed_domains: [],
    enabled: false,
  };
}

/**
 * Order-insensitive array equality check for string arrays.
 */
function arraysEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const sortedA = [...a].sort();
  const sortedB = [...b].sort();
  return sortedA.every((val, idx) => val === sortedB[idx]);
}

/**
 * Convert API response to form state.
 *
 * CRITICAL: Never populate client_secret from API response.
 * The API returns a masked value (e.g., "********1234") which would
 * corrupt the credential if saved back.
 */
function configToFormState(config: CustomDomainSsoConfig): SsoConfigFormState {
  return {
    provider_type: config.provider_type,
    display_name: config.display_name,
    client_id: config.client_id,
    client_secret: '', // Never populate from API
    tenant_id: config.tenant_id ?? '',
    issuer: config.issuer ?? '',
    allowed_domains: config.allowed_domains ?? [],
    enabled: config.enabled,
  };
}

/* eslint max-lines-per-function: off */
export function useSsoConfig(domainExtId: string) {
  const notifications = useNotificationsStore();
  const { t } = useI18n();
  const router = useRouter();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /** Whether the initial config fetch is in progress. */
  const isLoading = ref(true);
  /** Whether `initialize` has completed at least once. */
  const isInitialized = ref(false);
  /** Whether a save (PUT/PATCH) request is in flight. */
  const isSaving = ref(false);
  /** Whether a delete request is in flight. */
  const isDeleting = ref(false);
  /** Whether a test connection request is in flight. */
  const isTesting = ref(false);
  /** The most recent API error, or null. */
  const error = ref<ApplicationError | null>(null);

  /** The full config object from the API. Null = unconfigured (404). */
  const ssoConfig = ref<CustomDomainSsoConfig | null>(null);

  /** Current form state (editable). */
  const formState = ref<SsoConfigFormState>(createDefaultFormState());

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<SsoConfigFormState | null>(null);

  /** Result from the last test connection attempt. */
  const testResult = ref<TestSsoConnectionResponse | null>(null);

  /** Error message from the last failed test connection attempt. */
  const testError = ref<string>('');

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity, 'top'),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      if (err.code === 404) {
        return router.push({ name: 'NotFound' });
      }
      error.value = err;
    },
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  // A second handler for save/delete/test actions that should NOT toggle
  // isLoading (which controls the full-page loading state). These actions
  // manage their own loading flags (isSaving, isDeleting, isTesting).
  const { wrap: wrapAction } = useAsyncHandler({
    ...defaultAsyncHandlerOptions,
    setLoading: undefined,
  });

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /** Whether an SSO config exists for this domain. */
  const isConfigured = computed(() => ssoConfig.value !== null);

  /** Whether SSO is both configured AND enabled. */
  const isEnabled = computed(() => ssoConfig.value?.enabled ?? false);

  /** The masked client secret from the existing config (for display purposes). */
  const clientSecretMasked = computed(() => ssoConfig.value?.client_secret_masked ?? null);

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    const current = formState.value;
    const saved = savedFormState.value;
    return (
      current.provider_type !== saved.provider_type ||
      current.display_name !== saved.display_name ||
      current.client_id !== saved.client_id ||
      current.client_secret !== saved.client_secret ||
      current.tenant_id !== saved.tenant_id ||
      current.issuer !== saved.issuer ||
      current.enabled !== saved.enabled ||
      !arraysEqual(current.allowed_domains, saved.allowed_domains)
    );
  });

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /**
   * Load the current SSO config for this domain.
   * 404 is treated as "unconfigured" (ssoConfig = null), not an error.
   */
  const initialize = () =>
    wrap(async () => {
      const response = await SsoService.getConfigForDomain(domainExtId);
      ssoConfig.value = response.record;

      if (response.record) {
        formState.value = configToFormState(response.record);
      } else {
        formState.value = createDefaultFormState();
      }
      savedFormState.value = { ...formState.value, allowed_domains: [...formState.value.allowed_domains] };
      isInitialized.value = true;
    });

  /**
   * Save the current form state.
   * Uses SsoService.saveConfigForDomain which auto-selects PUT vs PATCH
   * based on whether client_secret is provided.
   */
  const saveConfig = async () => {
    isSaving.value = true;
    error.value = null;

    try {
      const result = await wrapAction(async () => {
        const payload: PutSsoConfigRequest | PatchSsoConfigRequest = {
          provider_type: formState.value.provider_type,
          display_name: formState.value.display_name.trim(),
          client_id: formState.value.client_id.trim(),
          tenant_id: formState.value.tenant_id.trim() || undefined,
          issuer: formState.value.issuer.trim() || undefined,
          allowed_domains: formState.value.allowed_domains,
          enabled: formState.value.enabled,
        };

        // Only include client_secret if provided (non-empty)
        if (formState.value.client_secret.trim()) {
          (payload as PutSsoConfigRequest).client_secret = formState.value.client_secret.trim();
        }

        return await SsoService.saveConfigForDomain(domainExtId, payload);
      });

      if (result?.record) {
        ssoConfig.value = result.record;
        formState.value = configToFormState(result.record);
        savedFormState.value = { ...formState.value, allowed_domains: [...formState.value.allowed_domains] };
        notifications.show(t('web.domains.sso.update_success'), 'success', 'top');
      }
    } finally {
      isSaving.value = false;
    }
  };

  /**
   * Delete the SSO config for this domain.
   */
  const deleteConfig = async () => {
    isDeleting.value = true;
    error.value = null;

    try {
      await wrapAction(async () => {
        await SsoService.deleteConfigForDomain(domainExtId);
        ssoConfig.value = null;
        formState.value = createDefaultFormState();
        savedFormState.value = { ...formState.value, allowed_domains: [...formState.value.allowed_domains] };
        notifications.show(t('web.domains.sso.delete_success'), 'success', 'top');
      });
    } finally {
      isDeleting.value = false;
    }
  };

  /**
   * Test the SSO connection using current form credentials.
   * Tests against the IdP without saving the configuration.
   */
  const testConnection = async () => {
    isTesting.value = true;
    testResult.value = null;
    testError.value = '';

    try {
      const result = await wrapAction(async () => {
        const payload: TestSsoConnectionRequest = {
          provider_type: formState.value.provider_type,
          client_id: formState.value.client_id.trim(),
        };

        // Add provider-specific fields
        if (formState.value.tenant_id.trim()) {
          payload.tenant_id = formState.value.tenant_id.trim();
        }
        if (formState.value.issuer.trim()) {
          payload.issuer = formState.value.issuer.trim();
        }

        return await SsoService.testConnectionForDomain(domainExtId, payload);
      });

      if (result) {
        testResult.value = result;
        if (result.success) {
          notifications.show(t('web.domains.sso.test_success'), 'success', 'top');
        } else {
          testError.value = result.message || t('web.domains.sso.test_failed');
          notifications.show(testError.value, 'error', 'top');
        }
      }
    } finally {
      isTesting.value = false;
    }
  };

  /**
   * Reset form to last-saved state.
   */
  const discardChanges = () => {
    if (savedFormState.value) {
      formState.value = {
        ...savedFormState.value,
        allowed_domains: [...savedFormState.value.allowed_domains],
      };
    }
  };

  return {
    // State
    isLoading,
    isInitialized,
    isSaving,
    isDeleting,
    isTesting,
    error,
    ssoConfig,
    formState,
    testResult,
    testError,

    // Computed
    isConfigured,
    isEnabled,
    clientSecretMasked,
    hasUnsavedChanges,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    testConnection,
    discardChanges,
  };
}
