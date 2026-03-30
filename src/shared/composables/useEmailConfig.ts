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

import type { ApplicationError } from '@/schemas/errors';
import type {
  PutEmailConfigRequest,
  PatchEmailConfigRequest,
} from '@/schemas/api/domains/requests/email-config';
import type {
  CustomDomainEmailConfig,
  EmailProviderType,
} from '@/schemas/shapes/domains/email-config';
import { useDomainsStore } from '@/shared/stores/domainsStore';
import { useNotificationsStore } from '@/shared/stores';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { type AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

export interface EmailConfigFormState {
  provider: EmailProviderType;
  from_name: string;
  from_address: string;
  reply_to: string;
  enabled: boolean;
}

function createDefaultFormState(): EmailConfigFormState {
  return {
    provider: 'inherit',
    from_name: '',
    from_address: '',
    reply_to: '',
    enabled: false,
  };
}

function configToFormState(config: CustomDomainEmailConfig): EmailConfigFormState {
  return {
    provider: config.provider,
    from_name: config.from_name,
    from_address: config.from_address,
    reply_to: config.reply_to ?? '',
    enabled: config.enabled,
  };
}

/* eslint max-lines-per-function: off */
export function useEmailConfig(domainExtId: string) {
  const domainsStore = useDomainsStore();
  const notifications = useNotificationsStore();
  const { t } = useI18n();
  const router = useRouter();

  const isLoading = ref(false);
  const isInitialized = ref(false);
  const isSaving = ref(false);
  const isValidating = ref(false);
  const isDeleting = ref(false);
  const error = ref<ApplicationError | null>(null);

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

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /** Whether an email config exists for this domain. */
  const isConfigured = computed(() => emailConfig.value !== null);

  /** Whether the config is verified (DNS records confirmed). */
  const isVerified = computed(
    () => emailConfig.value?.validation_status === 'verified'
  );

  /** Whether emails are using the fallback global sender. */
  const usesFallbackSender = computed(
    () =>
      !isConfigured.value ||
      !isVerified.value ||
      emailConfig.value?.enabled === false
  );

  /** DNS records from the current config. */
  const dnsRecords = computed(() => emailConfig.value?.dns_records ?? []);

  /** Validation status from the current config. */
  const validationStatus = computed(
    () => emailConfig.value?.validation_status ?? 'pending'
  );

  /** Last validated timestamp. */
  const lastValidatedAt = computed(
    () => emailConfig.value?.last_validated_at ?? null
  );

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    const current = formState.value;
    const saved = savedFormState.value;
    return (
      current.provider !== saved.provider ||
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
      const result = await wrap(async () => {
        if (isConfigured.value) {
          // PATCH: update existing config
          const payload: PatchEmailConfigRequest = {
            provider: formState.value.provider,
            from_name: formState.value.from_name.trim(),
            from_address: formState.value.from_address.trim(),
            enabled: formState.value.enabled,
          };
          if (formState.value.reply_to.trim()) {
            payload.reply_to = formState.value.reply_to.trim();
          }
          return await domainsStore.patchEmailConfig(domainExtId, payload);
        } else {
          // PUT: create new config
          const payload: PutEmailConfigRequest = {
            provider: formState.value.provider,
            from_name: formState.value.from_name.trim(),
            from_address: formState.value.from_address.trim(),
            enabled: formState.value.enabled,
          };
          if (formState.value.reply_to.trim()) {
            payload.reply_to = formState.value.reply_to.trim();
          }
          return await domainsStore.putEmailConfig(domainExtId, payload);
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
      await wrap(async () => {
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
   * Uses direct error handling rather than `wrap` because the validate
   * endpoint may not exist yet (backend #2803). A 404 here means "endpoint
   * missing", not "domain not found", so we must not redirect to NotFound.
   */
  const validateDomain = async () => {
    isValidating.value = true;
    error.value = null;

    try {
      const response = await domainsStore.validateEmailConfig(domainExtId);
      if (response.record) {
        emailConfig.value = response.record;
        formState.value = configToFormState(response.record);
        savedFormState.value = { ...formState.value };
      }
    } catch {
      notifications.show(t('web.domains.email.validation_failed'), 'error', 'top');
    } finally {
      isValidating.value = false;
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
    hasUnsavedChanges,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    validateDomain,
    discardChanges,
  };
}
