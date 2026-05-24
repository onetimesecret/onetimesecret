// src/shared/composables/useIncomingConfig.ts

/**
 * Composable for managing per-domain incoming-secrets recipients
 * configuration.
 *
 * Follows the useSsoConfig lifecycle pattern:
 * - initialize: fetch current config (always returns a record; empty
 *   recipients + enabled=false means no IncomingConfig exists yet)
 * - saveConfig: PUT the full intended state (enabled + recipients)
 * - deleteConfig: DELETE the IncomingConfig record entirely
 * - addRecipient / removeRecipient: local form mutations (no server call)
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * The admin endpoint returns plaintext `{email, name}` recipients so the
 * client can round-trip the existing list on save without the legacy
 * dual-state architecture. Anonymous-sender flows continue to use hashed
 * digests on a different endpoint.
 *
 * @param domainExtId - Domain external ID for API calls (string or ref)
 */

import type { ApplicationError } from '@/schemas/errors';
import type { PutDomainIncomingConfigRequest } from '@/schemas/api/domains/requests/incoming-config';
import type { DomainIncomingRecipient } from '@/schemas/shapes/domains/incoming-config';
import { IncomingConfigService } from '@/services/incomingConfig.service';
import { useNotificationsStore } from '@/shared/stores';
import { computed, ref, unref, type MaybeRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { type AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Default maximum number of recipients allowed per domain. The backend
 * authoritative value is reported in the response and used at runtime;
 * this constant only seeds the ref before initialize() completes.
 */
const DEFAULT_MAX_RECIPIENTS = 20;

/**
 * Form state for incoming secrets recipients configuration.
 *
 * Recipients carry plaintext email + name. The admin endpoint round-trips
 * this shape; the anonymous-sender endpoint uses a separate hashed shape.
 */
export interface IncomingConfigFormState {
  /** Whether incoming secrets are enabled for this domain. */
  enabled: boolean;
  /** Array of recipients (plaintext email + display name). */
  recipients: DomainIncomingRecipient[];
}

function createDefaultFormState(): IncomingConfigFormState {
  return {
    enabled: false,
    recipients: [],
  };
}

/** Deep clone form state so snapshots stay independent of live mutations. */
function cloneFormState(state: IncomingConfigFormState): IncomingConfigFormState {
  return {
    enabled: state.enabled,
    recipients: state.recipients.map((r) => ({ ...r })),
  };
}

/** Order-sensitive recipient equality. Order may matter for display. */
function recipientsEqual(
  a: DomainIncomingRecipient[],
  b: DomainIncomingRecipient[],
): boolean {
  if (a.length !== b.length) return false;
  return a.every((recipient, idx) => {
    const other = b[idx];
    return recipient.email === other.email && recipient.name === other.name;
  });
}

function formStatesEqual(
  a: IncomingConfigFormState,
  b: IncomingConfigFormState,
): boolean {
  if (a.enabled !== b.enabled) return false;
  return recipientsEqual(a.recipients, b.recipients);
}

/* eslint max-lines-per-function: off */
export function useIncomingConfig(domainExtId: MaybeRef<string>) {
  const notifications = useNotificationsStore();
  const { t } = useI18n();
  const router = useRouter();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /** Whether the initial config fetch is in progress. */
  const isLoading = ref(false);
  /** Whether `initialize` has completed at least once. */
  const isInitialized = ref(false);
  /** Whether a save (PUT) request is in flight. */
  const isSaving = ref(false);
  /** Whether a delete request is in flight. */
  const isDeleting = ref(false);
  /** The most recent API error, or null. */
  const error = ref<ApplicationError | null>(null);

  /** Current form state (editable, plaintext recipients). */
  const formState = ref<IncomingConfigFormState>(createDefaultFormState());

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<IncomingConfigFormState | null>(null);

  /** Maximum recipients allowed (from server response or default). */
  const maxRecipients = ref<number>(DEFAULT_MAX_RECIPIENTS);

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

  // Action wrapper that does not toggle isLoading; saveConfig/deleteConfig
  // own their own loading flags (isSaving/isDeleting).
  const { wrap: wrapAction } = useAsyncHandler({
    ...defaultAsyncHandlerOptions,
    setLoading: undefined,
  });

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /** Whether any recipients are configured in the saved server state. */
  const isConfigured = computed(
    () => (savedFormState.value?.recipients.length ?? 0) > 0,
  );

  /** Number of recipients in the form. */
  const recipientCount = computed(() => formState.value.recipients.length);

  /** Whether more recipients can be added. */
  const canAddMore = computed(
    () => formState.value.recipients.length < maxRecipients.value,
  );

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    return !formStatesEqual(formState.value, savedFormState.value);
  });

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /**
   * Load the current incoming config for this domain.
   *
   * The admin endpoint returns plaintext recipients so we populate
   * formState directly from the response. An empty record (no
   * IncomingConfig persisted yet) is a valid unconfigured state, not an
   * error.
   */
  const initialize = () =>
    wrap(async () => {
      const extid = unref(domainExtId);
      const { record } = await IncomingConfigService.getConfigForDomain(extid);

      maxRecipients.value = record.max_recipients;
      formState.value = {
        enabled: record.enabled,
        recipients: record.recipients.map((r) => ({ ...r })),
      };
      savedFormState.value = cloneFormState(formState.value);
      isInitialized.value = true;
    });

  /**
   * Save the current form state.
   *
   * PUTs the full intended state (enabled + recipients). After success,
   * formState is rehydrated from the server response and snapshotted.
   */
  const saveConfig = async (): Promise<boolean> => {
    isSaving.value = true;
    error.value = null;

    try {
      const result = await wrapAction(async () => {
        const extid = unref(domainExtId);
        const payload: PutDomainIncomingConfigRequest = {
          enabled: formState.value.enabled,
          recipients: formState.value.recipients.map((r) => ({
            email: r.email,
            name: r.name,
          })),
        };
        return await IncomingConfigService.putConfigForDomain(extid, payload);
      });

      if (result) {
        maxRecipients.value = result.record.max_recipients;
        formState.value = {
          enabled: result.record.enabled,
          recipients: result.record.recipients.map((r) => ({ ...r })),
        };
        savedFormState.value = cloneFormState(formState.value);
        notifications.show(t('web.domains.incoming.update_success'), 'success', 'top');
        return true;
      }
      return false;
    } finally {
      isSaving.value = false;
    }
  };

  /**
   * Delete the IncomingConfig record for this domain.
   *
   * Resets form state to the unconfigured default (disabled, no recipients).
   */
  const deleteConfig = async (): Promise<boolean> => {
    isDeleting.value = true;
    error.value = null;

    try {
      const result = await wrapAction(async () => {
        const extid = unref(domainExtId);
        await IncomingConfigService.deleteConfigForDomain(extid);
        return true;
      });

      if (result) {
        formState.value = createDefaultFormState();
        savedFormState.value = cloneFormState(formState.value);
        notifications.show(t('web.domains.incoming.delete_success'), 'success', 'top');
        return true;
      }
      return false;
    } finally {
      isDeleting.value = false;
    }
  };

  /**
   * Add a recipient to the form state.
   *
   * Local mutation only — no server call. Returns false if at capacity
   * or if the email is already present.
   */
  function addRecipient(email: string, name?: string): boolean {
    if (!canAddMore.value) {
      notifications.show(
        t('web.domains.incoming.max_recipients_reached', { max: maxRecipients.value }),
        'warning',
        'top',
      );
      return false;
    }

    const trimmedEmail = email.trim();
    const normalizedEmail = trimmedEmail.toLowerCase();
    const isDuplicate = formState.value.recipients.some(
      (r) => r.email.toLowerCase() === normalizedEmail,
    );

    if (isDuplicate) {
      notifications.show(t('web.domains.incoming.duplicate_recipient'), 'warning', 'top');
      return false;
    }

    const trimmedName = name?.trim();
    formState.value.recipients.push({
      email: trimmedEmail,
      name: trimmedName && trimmedName.length > 0 ? trimmedName : trimmedEmail.split('@')[0],
    });
    return true;
  }

  /** Remove a recipient from the form state by index. */
  function removeRecipient(index: number): void {
    if (index >= 0 && index < formState.value.recipients.length) {
      formState.value.recipients.splice(index, 1);
    }
  }

  /** Reset form to last-saved snapshot. */
  function discardChanges(): void {
    if (savedFormState.value) {
      formState.value = cloneFormState(savedFormState.value);
    }
  }

  /** Update the enabled state in the form. */
  function updateEnabled(enabled: boolean): void {
    formState.value.enabled = enabled;
  }

  return {
    // State
    isLoading,
    isInitialized,
    isSaving,
    isDeleting,
    error,
    formState,
    savedFormState,

    // Computed
    isConfigured,
    recipientCount,
    canAddMore,
    hasUnsavedChanges,
    maxRecipients,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    addRecipient,
    removeRecipient,
    discardChanges,
    updateEnabled,
  };
}
