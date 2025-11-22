// src/composables/useIncomingSecret.ts

import { ref, computed } from 'vue';
import { useIncomingStore } from '@/stores/incomingStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import {
  AsyncHandlerOptions,
  createError,
  useAsyncHandler,
} from '@/composables/useAsyncHandler';
import { IncomingSecretPayload, IncomingSecretResponse } from '@/schemas/api/incoming';
import { useRouter } from 'vue-router';

interface IncomingSecretForm {
  title: string;
  secret: string;
  recipientId: string;
  passphrase?: string;
  ttl?: number;
  shareDomain?: string;
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
    title: '',
    secret: '',
    recipientId: '',
    passphrase: undefined,
    ttl: undefined,
    shareDomain: undefined,
  });

  const errors = ref<ValidationErrors>({});
  const isSubmitting = ref(false);

  // Computed
  const titleMaxLength = computed(() => incomingStore.titleMaxLength);
  const isFeatureEnabled = computed(() => incomingStore.isFeatureEnabled);
  const recipients = computed(() => incomingStore.recipients);

  // Validation
  const validateTitle = (): boolean => {
    if (!form.value.title.trim()) {
      errors.value.title = 'Title is required';
      return false;
    }

    if (form.value.title.length > titleMaxLength.value) {
      errors.value.title = `Title must be ${titleMaxLength.value} characters or less`;
      return false;
    }

    errors.value.title = undefined;
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
    const titleValid = validateTitle();
    const secretValid = validateSecret();
    const recipientValid = validateRecipient();

    return titleValid && secretValid && recipientValid;
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
  const createPayload = (): IncomingSecretPayload => {
    return {
      kind: 'incoming',
      secret: form.value.secret,
      title: form.value.title.trim(),
      recipient_id: form.value.recipientId,
      passphrase: form.value.passphrase || undefined,
      ttl: form.value.ttl || incomingStore.defaultTtl,
      share_domain: form.value.shareDomain || '',
    };
  };

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
      title: '',
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
    titleMaxLength,
    isFeatureEnabled,
    recipients,

    // Validation
    validateTitle,
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
