// src/shared/composables/useIncomingConfig.ts

/**
 * Composable for managing per-domain incoming secrets recipients configuration.
 *
 * Follows the useSsoConfig lifecycle pattern:
 * - initialize: fetch current recipients (404 = domain not found, error)
 * - saveConfig: PUT to replace entire recipients list
 * - deleteConfig: DELETE to clear all recipients
 * - addRecipient/removeRecipient: local form mutations
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * Data asymmetry note:
 * - Form state uses { email, name } (user input, plaintext)
 * - Server responses use { digest, display_name } (hashed for privacy)
 * - After save, we cannot recover original emails from digests
 * - Form tracks local edits; server state is authoritative after save
 *
 * @param domainExtId - Domain external ID for API calls (string or ref)
 */

import type { ApplicationError } from '@/schemas/errors';
import type { DomainRecipientInput } from '@/schemas/api/domains/requests/domain-recipients';
import type { DomainRecipientResponse } from '@/schemas/api/domains/responses/domain-recipients';
import { RecipientsService } from '@/services/recipients.service';
import { useNotificationsStore } from '@/shared/stores';
import { computed, ref, unref, type MaybeRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { type AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Maximum number of recipients allowed per domain.
 * Enforced client-side; server may have its own limit.
 */
const MAX_RECIPIENTS = 20;

/**
 * Form state for incoming secrets recipients configuration.
 *
 * Uses email (plaintext) for user input. Server returns hashed digests
 * after save, so we track form state separately from server state.
 */
export interface IncomingConfigFormState {
  /** Whether incoming secrets are enabled for this domain. */
  enabled: boolean;
  /** Array of recipients with email and optional display name. */
  recipients: DomainRecipientInput[];
}

/**
 * Server state for recipients (read-only, from API responses).
 *
 * Uses digest (hash) instead of email for privacy.
 */
export interface IncomingConfigServerState {
  /** Array of recipients as returned by server (hashed). */
  recipients: DomainRecipientResponse[];
}

function createDefaultFormState(): IncomingConfigFormState {
  return {
    enabled: false,
    recipients: [],
  };
}

function createDefaultServerState(): IncomingConfigServerState {
  return {
    recipients: [],
  };
}

/**
 * Deep clone a form state to avoid reference issues.
 */
function cloneFormState(state: IncomingConfigFormState): IncomingConfigFormState {
  return {
    enabled: state.enabled,
    recipients: state.recipients.map((r) => ({ ...r })),
  };
}

/**
 * Compare two recipient arrays for equality.
 * Order-sensitive comparison since recipient order may matter.
 */
function recipientsEqual(
  a: DomainRecipientInput[],
  b: DomainRecipientInput[]
): boolean {
  if (a.length !== b.length) return false;
  return a.every((recipient, idx) => {
    const other = b[idx];
    return recipient.email === other.email && (recipient.name ?? '') === (other.name ?? '');
  });
}

/**
 * Compare two form states for equality.
 */
function formStatesEqual(
  a: IncomingConfigFormState,
  b: IncomingConfigFormState
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

  /** Server state (hashed recipients from API). Read-only reference. */
  const serverState = ref<IncomingConfigServerState>(createDefaultServerState());

  /** Current form state (editable, plaintext emails). */
  const formState = ref<IncomingConfigFormState>(createDefaultFormState());

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<IncomingConfigFormState | null>(null);

  /** Maximum recipients allowed (from server details or default). */
  const maxRecipients = ref<number>(MAX_RECIPIENTS);

  /** Whether current user can manage recipients (from server details). */
  const canManage = ref<boolean>(true);

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

  /** Whether any recipients are configured (based on server state). */
  const isConfigured = computed(() => serverState.value.recipients.length > 0);

  /** Number of recipients in the form. */
  const recipientCount = computed(() => formState.value.recipients.length);

  /** Total recipients across server and form state (for limit enforcement). */
  const totalRecipientCount = computed(() =>
    serverState.value.recipients.length + formState.value.recipients.length
  );

  /** Whether more recipients can be added. */
  const canAddMore = computed(() => totalRecipientCount.value < maxRecipients.value);

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    return !formStatesEqual(formState.value, savedFormState.value);
  });

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /**
   * Load the current recipients for this domain.
   *
   * Note: After loading, formState is empty since we can't recover
   * plaintext emails from server's hashed digests. The UI should
   * display serverState.recipients (with display_name) as read-only,
   * and formState for pending additions.
   */
  const initialize = () =>
    wrap(async () => {
      const extid = unref(domainExtId);
      const response = await RecipientsService.getRecipientsForDomain(extid);

      serverState.value = { recipients: response.recipients };
      maxRecipients.value = response.maxRecipients ?? MAX_RECIPIENTS;
      canManage.value = response.canManage ?? true;

      // Reset form state - we cannot populate emails from digests
      // Set enabled = true if recipients exist (backend doesn't yet return enabled flag)
      formState.value = {
        enabled: response.recipients.length > 0,
        recipients: [],
      };
      savedFormState.value = cloneFormState(formState.value);
      isInitialized.value = true;
    });

  /**
   * Save the current form state (replaces all recipients).
   *
   * After successful save:
   * - serverState is updated with new hashed recipients
   * - formState is cleared (emails are now hashed on server)
   * - savedFormState is synced
   */
  const saveConfig = async (): Promise<boolean> => {
    isSaving.value = true;
    error.value = null;

    try {
      const result = await wrap(async () => {
        const extid = unref(domainExtId);
        return await RecipientsService.setRecipientsForDomain(
          extid,
          formState.value.recipients
        );
      });

      if (result) {
        serverState.value = { recipients: result.recipients };
        // Clear form after successful save - emails are now hashed on server
        formState.value = createDefaultFormState();
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
   * Delete all recipients for this domain.
   */
  const deleteConfig = async (): Promise<boolean> => {
    isDeleting.value = true;
    error.value = null;

    try {
      const result = await wrap(async () => {
        const extid = unref(domainExtId);
        await RecipientsService.deleteRecipientsForDomain(extid);
        return true;
      });

      if (result) {
        serverState.value = createDefaultServerState();
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
   * @param email - Email address of the recipient
   * @param name - Optional display name
   * @returns true if added, false if at max capacity or duplicate
   */
  function addRecipient(email: string, name?: string): boolean {
    if (!canAddMore.value) {
      notifications.show(
        t('web.domains.incoming.max_recipients_reached', { max: maxRecipients.value }),
        'warning',
        'top'
      );
      return false;
    }

    // Check for duplicate email in form state
    const normalizedEmail = email.trim().toLowerCase();
    const isDuplicate = formState.value.recipients.some(
      (r) => r.email.toLowerCase() === normalizedEmail
    );

    if (isDuplicate) {
      notifications.show(t('web.domains.incoming.duplicate_recipient'), 'warning', 'top');
      return false;
    }

    formState.value.recipients.push({
      email: email.trim(),
      name: name?.trim() || undefined,
    });
    return true;
  }

  /**
   * Remove a recipient from the form state by index.
   *
   * @param index - Index of recipient to remove
   */
  function removeRecipient(index: number): void {
    if (index >= 0 && index < formState.value.recipients.length) {
      formState.value.recipients.splice(index, 1);
    }
  }

  /**
   * Reset form to last-saved state.
   */
  function discardChanges(): void {
    if (savedFormState.value) {
      formState.value = cloneFormState(savedFormState.value);
    }
  }

  /**
   * Clear all recipients from the form state (local only, not saved).
   */
  function clearForm(): void {
    formState.value = createDefaultFormState();
  }

  /**
   * Update the enabled state in the form.
   *
   * @param enabled - Whether incoming secrets should be enabled
   */
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
    serverState,

    // Computed
    isConfigured,
    recipientCount,
    canAddMore,
    hasUnsavedChanges,
    maxRecipients,
    canManage,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    addRecipient,
    removeRecipient,
    discardChanges,
    clearForm,
    updateEnabled,
  };
}
