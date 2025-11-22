// src/composables/useIncomingSecret.ts

import {
  AsyncHandlerOptions,
  createError,
  useAsyncHandler,
} from '@/composables/useAsyncHandler';
import { IncomingSecretPayload, IncomingSecretResponse } from '@/schemas/api/incoming';
import { useIncomingStore } from '@/stores/incomingStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { ref, computed } from 'vue';
import { useRouter } from 'vue-router';

interface IncomingSecretForm {
  memo: string;
  secret: string;
  recipientId: string;
}

interface IncomingSecretOptions {
  onSuccess?: (response: IncomingSecretResponse) => Promise<void> | void;
}

interface ValidationErrors {
  title?: string;
  secret?: string;
  recipientId?: string;
  passphrase?: string;
}

/**
 * useIncomingSecret
 *
 * Orchestrates incoming secret creation workflow. Manages form state,
 * validation, and submission for incoming secrets feature.
 *
 * Responsibilities:
 * - Form state management
 * - Client-side validation
 * - API payload creation
 * - Form submission
 * - Response handling
 * - Navigation after success
 */
/* eslint-disable max-lines-per-function */
export function useIncomingSecret(options?: IncomingSecretOptions) {
  const incomingStore = useIncomingStore();
  const notifications = useNotificationsStore();
  const router = useRouter();

  // Form state
  const form = ref<IncomingSecretForm>({
    memo: '',
    secret: '',
    recipientId: '',
  });

  const errors = ref<ValidationErrors>({});
  const isSubmitting = ref(false);

  // Computed
  const memoMaxLength = computed(() => incomingStore.memoMaxLength);
  const isFeatureEnabled = computed(() => incomingStore.isFeatureEnabled);
  const recipients = computed(() => incomingStore.recipients);

  // Validation
  const validateMemo = (): boolean => {
    if (!form.value.memo.trim()) {
      errors.value.memo = 'Subject is required';
      return false;
    }

    if (form.value.memo.length > memoMaxLength.value) {
      errors.value.memo = `Subject must be ${memoMaxLength.value} characters or less`;
      return false;
    }

    errors.value.memo = undefined;
    return true;
  };

  const validateSecret = (): boolean => {
    if (!form.value.secret.trim()) {
      errors.value.secret = 'Secret content is required';
      return false;
    }

    errors.value.secret = undefined;
    return true;
  };

  const validateRecipient = (): boolean => {
    if (!form.value.recipientId) {
      errors.value.recipientId = 'Please select a recipient';
      return false;
    }

    errors.value.recipientId = undefined;
    return true;
  };

  const validateForm = (): boolean => {
    const memoValid = validateMemo();
    const secretValid = validateSecret();
    const recipientValid = validateRecipient();

    return memoValid && secretValid && recipientValid;
  };

  const clearValidation = () => {
    errors.value = {};
  };

  const asyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSubmitting.value = loading),
  };

  const { wrap } = useAsyncHandler(asyncHandlerOptions);

  /**
   * Creates API payload from form data
   */
  const createPayload = (): IncomingSecretPayload => ({
      memo: form.value.memo.trim(),
      secret: form.value.secret,
      recipient: form.value.recipientId,
    });

  /**
   * Handles form submission
   */
  const submit = async () =>
    wrap(async () => {
      if (!isFeatureEnabled.value) {
        throw createError('Incoming secrets feature is not enabled', 'human');
      }

      if (!validateForm()) {
        throw createError('Please check the form for errors', 'human');
      }

      const payload = createPayload();
      const response = await incomingStore.createIncomingSecret(payload);

      if (options?.onSuccess) {
        await options.onSuccess(response);
      } else if (response.success && response.metadata_key) {
        // Default navigation to success view
        await router.push({
          name: 'IncomingSuccess',
          params: { metadataKey: response.metadata_key },
        });
      }

      return response;
    });

  /**
   * Resets form to initial state
   */
  const resetForm = () => {
    form.value = {
      memo: '',
      secret: '',
      recipientId: '',
      passphrase: undefined,
      ttl: undefined,
      shareDomain: undefined,
    };
    clearValidation();
  };

  /**
   * Loads configuration from API
   */
  const loadConfig = async () => {
    try {
      await incomingStore.loadConfig();
    } catch (error) {
      notifications.show('Failed to load configuration', 'error');
      throw error;
    }
  };

  return {
    // Form state
    form,
    errors,
    isSubmitting,

    // Computed
    memoMaxLength,
    isFeatureEnabled,
    recipients,

    // Validation
    validateMemo,
    validateSecret,
    validateRecipient,
    validateForm,
    clearValidation,

    // Operations
    submit,
    resetForm,
    loadConfig,
  };
}
