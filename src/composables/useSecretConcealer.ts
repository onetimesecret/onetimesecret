// src/composables/useSecretConcealer.ts

import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSecretForm } from './useSecretForm';
import { useSecretStore } from '@/stores/secretStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { loggingService } from '@/services/logging.service';
import {
  AsyncHandlerOptions,
  wrapError,
  useAsyncHandler,
} from '@/composables/useAsyncHandler';
import { ConcealPayload, GeneratePayload } from '@/schemas/api/payloads';
import { ConcealDataResponse } from '@/schemas/api';

interface SecretConcealerOptions {
  onSuccess?: (response: ConcealDataResponse) => Promise<void> | void;
}

type SubmitType = 'conceal' | 'generate';

/**
 * useSecretConcealer
 *
 * Orchestrates secret creation workflow. Transforms form data into API
 * payloads, handles submission, and manages async state. Coordinates
 * between form state and API operations.
 *
 * Responsibilities:
 * - API payload creation
 * - Form submission
 * - Response handling
 * - Navigation after success
 * - Error management
 */
/* eslint-disable max-lines-per-function */
export function useSecretConcealer(options?: SecretConcealerOptions) {
  const { t } = useI18n();
  const secretStore = useSecretStore();
  const notifications = useNotificationsStore();

  const isSubmitting = ref(false);

  const { form, validation, operations } = useSecretForm();

  const asyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSubmitting.value = loading),
    debug: true, // Enable debug mode
    onError: (error) => {
      // Log detailed context when errors occur
      if (error.message.includes('validation failed')) {
        // Convert Map entries to a plain object for better logging compatibility
        const validationErrors = Object.fromEntries(validation.errors.entries());
        loggingService.debug('Form validation errors:', validationErrors);
        loggingService.debug('Current form state:', form);
      }
    },
  };

  const { wrap } = useAsyncHandler(asyncHandlerOptions);

  /**
   * Creates API payload based on submission type
   */
  const createPayload = (
    type: SubmitType
  ): ConcealPayload | GeneratePayload => ({
    kind: type,
    secret: form.secret,
    ttl: form.ttl,
    passphrase: form.passphrase,
    recipient: form.recipient,
    share_domain: form.share_domain || '',
  });

  /**
   * Handles form submission for both conceal and generate operations
   */
   const submit = async (type: SubmitType = 'conceal') =>
     wrap(async () => {
       // Skip validation for "generate" operations since there is no user
       // input.
       if (type === 'conceal' && !validation.validate()) {
         const validationDetails = {
           errors: Object.fromEntries(validation.errors),
           formData: { ...form }
         };

         // Create a user-friendly error message for form validation
         const fieldCount = validation.errors.size;
         let errorMessage: string;

         if (fieldCount === 1) {
           // Single field error - show the specific field error
           const [fieldError] = validation.errors.values();
           errorMessage = fieldError;
         } else if (fieldCount > 1) {
           // Multiple field errors - show general message
           errorMessage = t('web.COMMON.form_validation.form_invalid');
         } else {
           // No specific errors found - fallback
           errorMessage = t('web.COMMON.form_validation.form_invalid');
         }

         throw wrapError(
           errorMessage,
           'human',
           'error',
           new Error('Form validation failed'),
           null,
           validationDetails
         );
       }

      const payload = createPayload(type);

      const response = await (type === 'conceal'
        ? secretStore.conceal(payload as ConcealPayload)
        : secretStore.generate(payload as GeneratePayload));

      if (response && typeof response === 'object' && options?.onSuccess) {
        await options.onSuccess(response);
      }

      return response;
    });
  return {
    form,
    validation,
    operations,
    isSubmitting,
    submit,
  };
}
