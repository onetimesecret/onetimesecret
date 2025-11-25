// src/composables/useIncomingSecret.ts

import {
  AsyncHandlerOptions,
  createError,
  useAsyncHandler,
} from '@/composables/useAsyncHandler';
import {
  type IncomingConfig,
  type IncomingRecipient,
  type IncomingSecretPayload,
  type IncomingSecretResponse,
} from '@/schemas/api/incoming';
import { useIncomingStore } from '@/stores/incomingStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { computed, onMounted, reactive, ref } from 'vue';

interface IncomingSecretOptions {
  onSuccess?: (response: IncomingSecretResponse) => Promise<void> | void;
  autoLoadConfig?: boolean;
}

interface IncomingFormState {
  memo: string;
  secret: string;
  recipientHash: string;
}

interface ValidationState {
  memo: string | null;
  secret: string | null;
  recipient: string | null;
}

/**
 * useIncomingSecret
 *
 * Orchestrates the incoming secrets workflow. Manages form state,
 * config loading, validation, and API submission.
 *
 * Responsibilities:
 * - Load incoming configuration on mount
 * - Manage form state (memo, secret, recipient)
 * - Validate form before submission
 * - Submit incoming secret to API
 * - Handle success/error states
 */
// eslint-disable-next-line max-lines-per-function -- Composable requires cohesive setup logic
export function useIncomingSecret(options: IncomingSecretOptions = {}) {
  const { autoLoadConfig = true, onSuccess } = options;

  const incomingStore = useIncomingStore();
  const notifications = useNotificationsStore();

  // Form state
  const form = reactive<IncomingFormState>({
    memo: '',
    secret: '',
    recipientHash: '',
  });

  // Validation errors
  const errors = reactive<ValidationState>({
    memo: null,
    secret: null,
    recipient: null,
  });

  // Loading/submitting states
  const isLoading = ref(false);
  const isSubmitting = ref(false);
  const configError = ref<string | null>(null);

  // Success state
  const lastResponse = ref<IncomingSecretResponse | null>(null);
  const isSuccess = computed(() => lastResponse.value?.success === true);

  // Config getters from store
  const config = computed(() => incomingStore.config);
  const recipients = computed(() => incomingStore.recipients);
  const isEnabled = computed(() => incomingStore.isEnabled);
  const memoMaxLength = computed(() => incomingStore.memoMaxLength);

  // Selected recipient info
  const selectedRecipient = computed<IncomingRecipient | null>(() => {
    if (!form.recipientHash) return null;
    return recipients.value.find((r) => r.hash === form.recipientHash) ?? null;
  });

  const asyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSubmitting.value = loading),
  };

  const { wrap } = useAsyncHandler(asyncHandlerOptions);

  /**
   * Loads the incoming configuration from the API
   */
  async function loadConfig(): Promise<IncomingConfig | null> {
    isLoading.value = true;
    configError.value = null;

    try {
      const config = await incomingStore.fetchConfig();
      return config;
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Failed to load configuration';
      configError.value = message;
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Validates the form and returns true if valid
   */
  function validate(): boolean {
    let isValid = true;

    // Reset errors
    errors.memo = null;
    errors.secret = null;
    errors.recipient = null;

    // Validate secret (required)
    if (!form.secret.trim()) {
      errors.secret = 'Secret content is required';
      isValid = false;
    }

    // Validate recipient (required)
    if (!form.recipientHash) {
      errors.recipient = 'Please select a recipient';
      isValid = false;
    }

    // Memo is optional, but validate length if provided
    if (form.memo && form.memo.length > memoMaxLength.value) {
      errors.memo = `Memo must be ${memoMaxLength.value} characters or less`;
      isValid = false;
    }

    return isValid;
  }

  /**
   * Creates the API payload from form state
   */
  function createPayload(): IncomingSecretPayload {
    return {
      memo: form.memo.trim(),
      secret: form.secret,
      recipient: form.recipientHash,
    };
  }

  /**
   * Submits the incoming secret to the API
   */
  async function submit(): Promise<IncomingSecretResponse | null> {
    const result = await wrap(async () => {
      if (!validate()) {
        throw createError('Please check the form for errors', 'human');
      }

      const payload = createPayload();
      const response = await incomingStore.createSecret(payload);

      lastResponse.value = response;

      if (response.success && onSuccess) {
        await onSuccess(response);
      }

      return response;
    });
    return result ?? null;
  }

  /**
   * Resets the form to its initial state
   */
  function reset() {
    form.memo = '';
    form.secret = '';
    form.recipientHash = '';
    errors.memo = null;
    errors.secret = null;
    errors.recipient = null;
    lastResponse.value = null;
  }

  /**
   * Sets the selected recipient by hash
   */
  function setRecipient(hash: string) {
    form.recipientHash = hash;
    errors.recipient = null;
  }

  // Auto-load config on mount if enabled
  onMounted(() => {
    if (autoLoadConfig) {
      loadConfig();
    }
  });

  return {
    // Form state
    form,
    errors,

    // Loading states
    isLoading,
    isSubmitting,
    configError,

    // Success state
    lastResponse,
    isSuccess,

    // Config (from store)
    config,
    recipients,
    isEnabled,
    memoMaxLength,
    selectedRecipient,

    // Actions
    loadConfig,
    validate,
    submit,
    reset,
    setRecipient,
  };
}
