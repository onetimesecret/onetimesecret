// src/shared/composables/useEmailConfig.ts

/**
 * Composable for managing per-domain email configuration.
 *
 * Follows the useBranding lifecycle pattern:
 * - initialize: fetch current config (404 = unconfigured, not error)
 * - saveConfig: auto-selects PUT (new) vs PATCH (update)
 * - deleteConfig: removes config, domain reverts to global sender
 * - validateDomain: triggers DNS record verification
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * @param domainExtId - Domain external ID for API calls
 */

import type {
  PatchEmailConfigRequest,
  PutEmailConfigRequest,
} from '@/schemas/api/domains/requests/email-config';
import type { TestEmailConfigResponse } from '@/schemas/api/domains/responses/test-email-config';
import type { ApplicationError } from '@/schemas/errors';
import type { CustomDomainEmailConfig } from '@/schemas/shapes/domains/email-config';
import { useNotificationsStore } from '@/shared/stores';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useDomainsStore } from '@/shared/stores/domainsStore';
import { storeToRefs } from 'pinia';
import { computed, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';

export interface EmailConfigFormState {
  from_name: string;
  from_address: string;
  reply_to: string;
  enabled: boolean;
}

function createDefaultFormState(): EmailConfigFormState {
  return {
    from_name: '',
    from_address: '',
    reply_to: '',
    enabled: false,
  };
}

function configToFormState(config: CustomDomainEmailConfig): EmailConfigFormState {
  return {
    from_name: config.from_name,
    from_address: config.from_address,
    reply_to: config.reply_to ?? '',
    enabled: config.enabled,
  };
}

/* eslint max-lines-per-function: off */
export function useEmailConfig(domainExtId: string) {
  const domainsStore = useDomainsStore();
  const bootstrapStore = useBootstrapStore();
  const { cust } = storeToRefs(bootstrapStore);
  const notifications = useNotificationsStore();
  const { t } = useI18n();
  const router = useRouter();

  /** Whether the email validation endpoint is deployed and stable. */
  const isValidateEndpointStable = computed(
    () => cust.value?.feature_flags?.email_validate_endpoint ?? false
  );

  /** Whether the initial config fetch is in progress. */
  const isLoading = ref(false);
  /** Whether `initialize` has completed at least once. */
  const isInitialized = ref(false);
  /** Whether a save (PUT/PATCH) request is in flight. */
  const isSaving = ref(false);
  /** Whether a DNS validation request is in flight. */
  const isValidating = ref(false);
  /** Whether a delete request is in flight. */
  const isDeleting = ref(false);
  /** Whether a test email request is in flight. */
  const isTesting = ref(false);
  /** Result from the last test email attempt. */
  const testResult = ref<TestEmailConfigResponse | null>(null);
  /** Error message from the last failed test email attempt. */
  const testError = ref<string>('');
  /** The most recent API error, or null. */
  const error = ref<ApplicationError | null>(null);
  /** Set on unmount to cancel any in-flight polling loop. */
  const pollingCancelled = ref(false);

  onUnmounted(() => {
    pollingCancelled.value = true;
  });

  /** The full config object from the API. Null = unconfigured (404). */
  const emailConfig = ref<CustomDomainEmailConfig | null>(null);

  /** Current form state (editable). */
  const formState = ref<EmailConfigFormState>(createDefaultFormState());

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<EmailConfigFormState | null>(null);

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

  // A second handler for save/delete actions that should NOT toggle
  // isLoading (which controls the full-page loading state). These actions
  // manage their own loading flags (isSaving, isDeleting).
  const { wrap: wrapAction } = useAsyncHandler({
    ...defaultAsyncHandlerOptions,
    setLoading: undefined,
  });

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /** Whether an email config exists for this domain. */
  const isConfigured = computed(() => emailConfig.value !== null);

  /** Whether the config is verified (DNS records confirmed). */
  const isVerified = computed(() => emailConfig.value?.validation_status === 'verified');

  /** Whether emails are using the fallback global sender. */
  const usesFallbackSender = computed(
    () => !isConfigured.value || !isVerified.value || emailConfig.value?.enabled === false
  );

  /** DNS records from the current config. */
  const dnsRecords = computed(() => emailConfig.value?.dns_records ?? []);

  /** Validation status from the current config. */
  const validationStatus = computed(() => emailConfig.value?.validation_status ?? 'pending');

  /** Last validated timestamp. */
  const lastValidatedAt = computed(() => emailConfig.value?.last_validated_at ?? null);

  /** Timestamp when DNS record check completed. */
  const dnsCheckCompletedAt = computed(() => emailConfig.value?.dns_check_completed_at ?? null);

  /** Timestamp when provider verification check completed. */
  const providerCheckCompletedAt = computed(() => emailConfig.value?.provider_check_completed_at ?? null);

  /** Last error from verification (e.g., "Provider status: not_found"). */
  const lastError = computed(() => emailConfig.value?.last_error ?? null);

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    const current = formState.value;
    const saved = savedFormState.value;
    return (
      current.from_name !== saved.from_name ||
      current.from_address !== saved.from_address ||
      current.reply_to !== saved.reply_to ||
      current.enabled !== saved.enabled
    );
  });

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /**
   * Load the current email config for this domain.
   * 404 is treated as "unconfigured" (emailConfig = null), not an error.
   */
  const initialize = () =>
    wrap(async () => {
      const config = await domainsStore.getEmailConfig(domainExtId);
      emailConfig.value = config;

      if (config) {
        formState.value = configToFormState(config);
      } else {
        formState.value = createDefaultFormState();
      }
      savedFormState.value = { ...formState.value };
      isInitialized.value = true;
    });

  /**
   * Save the current form state.
   * Auto-selects PUT (new config) vs PATCH (update existing).
   */
  const saveConfig = async () => {
    isSaving.value = true;
    error.value = null;

    try {
      const result = await wrapAction(async () => {
        // Sender identity payload (no provider or api_key - uses installation defaults)
        const payload: PatchEmailConfigRequest = {
          from_name: formState.value.from_name.trim(),
          from_address: formState.value.from_address.trim(),
          reply_to: formState.value.reply_to.trim(),
          enabled: formState.value.enabled,
        };

        if (isConfigured.value) {
          return await domainsStore.patchEmailConfig(domainExtId, payload);
        } else {
          return await domainsStore.putEmailConfig(domainExtId, payload as PutEmailConfigRequest);
        }
      });

      if (result) {
        emailConfig.value = result;
        formState.value = configToFormState(result);
        savedFormState.value = { ...formState.value };
        notifications.show(t('web.domains.email.update_success'), 'success', 'top');
      }
    } finally {
      isSaving.value = false;
    }
  };

  /**
   * Delete the email config, reverting to the global sender.
   */
  const deleteConfig = async () => {
    isDeleting.value = true;
    error.value = null;

    try {
      await wrapAction(async () => {
        await domainsStore.deleteEmailConfig(domainExtId);
        emailConfig.value = null;
        formState.value = createDefaultFormState();
        savedFormState.value = { ...formState.value };
        notifications.show(t('web.domains.email.delete_success'), 'success', 'top');
      });
    } finally {
      isDeleting.value = false;
    }
  };

  /**
   * Trigger DNS record validation for the domain's email config.
   * Updates the local config with refreshed validation status.
   *
   * When the `email_validate_endpoint` feature flag is enabled, uses the
   * standard `wrap` error handler. Otherwise falls back to direct error
   * handling because the validate endpoint may not exist yet (backend #2803)
   * and a 404 here means "endpoint missing", not "domain not found".
   */
  const validateDomain = async () => {
    if (isValidating.value) return;
    isValidating.value = true;
    pollingCancelled.value = false;
    error.value = null;

    const applyResult = (response: { record?: CustomDomainEmailConfig | null }) => {
      if (response.record) {
        emailConfig.value = response.record;
        formState.value = configToFormState(response.record);
        savedFormState.value = { ...formState.value };
      }
    };

    if (isValidateEndpointStable.value) {
      try {
        const response = await wrap(
          async () => await domainsStore.validateEmailConfig(domainExtId)
        );
        if (response) applyResult(response);
      } finally {
        // Poll for result — the POST returns 'pending' immediately while
        // a background worker performs DNS lookups. Without polling the UI
        // stays stuck on 'pending' until the user manually refreshes.
        await pollForValidationResult();
        isValidating.value = false;
      }
    } else {
      try {
        const response = await domainsStore.validateEmailConfig(domainExtId);
        applyResult(response);
      } catch {
        notifications.show(t('web.domains.email.validation_failed'), 'error', 'top');
      } finally {
        await pollForValidationResult();
        isValidating.value = false;
      }
    }
  };

  /**
   * Check if validation has completed (not pending).
   */
  const isValidationComplete = (config: CustomDomainEmailConfig): boolean => config.validation_status !== 'pending'
      && config.dns_check_completed_at != null
      && config.provider_check_completed_at != null;

  /**
   * Fetch and update email config from the store.
   */
  const updateEmailConfig = async (): Promise<boolean> => {
    try {
      const config = await domainsStore.getEmailConfig(domainExtId);
      if (!config) return false;
      emailConfig.value = config;
      formState.value = configToFormState(config);
      savedFormState.value = { ...formState.value };
      return isValidationComplete(config);
    } catch (err: unknown) {
      // Break on non-retriable auth errors; retry transient failures
      const status = (err as { code?: number })?.code;
      if (status === 401 || status === 403) return true; // Signal to stop polling
      return false;
    }
  };

  /**
   * Poll the GET email-config endpoint until verification_status leaves
   * 'pending' or the maximum number of attempts is reached. The background
   * worker typically completes within 1-3 seconds, so 3s intervals for
   * up to 30s covers even degraded-DNS scenarios.
   */
  const pollForValidationResult = async (intervalMs = 3000, maxAttempts = 10): Promise<void> => {
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
      if (pollingCancelled.value) return;
      const shouldStop = await updateEmailConfig();
      if (shouldStop) return;
    }
  };

  /**
   * Send a test email using the currently saved configuration.
   * Works even when enabled=false — lets users verify delivery before enabling.
   */
  const sendTestEmail = async () => {
    isTesting.value = true;
    testResult.value = null;
    testError.value = '';

    try {
      const result = await wrapAction(async () => await domainsStore.testEmailConfig(domainExtId));

      if (result) {
        testResult.value = result;
        if (result.success) {
          notifications.show(t('web.domains.email.test_email_sent'), 'success', 'top');
        } else {
          testError.value = result.message || t('web.domains.email.test_email_failed');
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
      formState.value = { ...savedFormState.value };
    }
  };

  return {
    // State
    isLoading,
    isInitialized,
    isSaving,
    isValidating,
    isDeleting,
    isTesting,
    testResult,
    testError,
    error,
    emailConfig,
    formState,

    // Computed
    isConfigured,
    isVerified,
    usesFallbackSender,
    dnsRecords,
    validationStatus,
    lastValidatedAt,
    dnsCheckCompletedAt,
    providerCheckCompletedAt,
    lastError,
    hasUnsavedChanges,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    validateDomain,
    sendTestEmail,
    discardChanges,
  };
}
