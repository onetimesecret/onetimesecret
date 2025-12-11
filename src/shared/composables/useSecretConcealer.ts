// src/shared/composables/useSecretConcealer.ts

import {
  AsyncHandlerOptions,
  createError,
  useAsyncHandler,
} from '@/shared/composables/useAsyncHandler';
import { ConcealDataResponse } from '@/schemas/api/v3';
import { ConcealPayload, GeneratePayload } from '@/schemas/api/v3/payloads';
import { WindowService } from '@/services/window.service';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { useSecretStore } from '@/shared/stores/secretStore';
import { ref } from 'vue';

import { useSecretForm } from './useSecretForm';

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

export function useSecretConcealer(options?: SecretConcealerOptions) {
  const secretStore = useSecretStore();
  const notifications = useNotificationsStore();

  const isSubmitting = ref(false);

  const { form, validation, operations } = useSecretForm();

  const asyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSubmitting.value = loading),
  };

  const { wrap } = useAsyncHandler(asyncHandlerOptions);

  /**
   * Creates API payload based on submission type.
   * Only includes passphrase field if user provided one - omitting the field
   * entirely signals "no passphrase protection" to the backend.
   */
  const createPayload = (
    type: SubmitType
  ): ConcealPayload | GeneratePayload => {
    const basePayload: Record<string, unknown> = {
      kind: type,
      secret: form.secret,
      ttl: form.ttl,
      recipient: form.recipient,
      share_domain: form.share_domain,
    };

    // Only include passphrase if user provided one
    if (form.passphrase) {
      basePayload.passphrase = form.passphrase;
    }

    // Add password generation options for generate type
    if (type === 'generate') {
      const secretOptions = WindowService.get('secret_options');
      const passwordConfig = secretOptions?.password_generation;

      return {
        ...basePayload,
        length: passwordConfig?.default_length,
        character_sets: passwordConfig?.character_sets,
      } as GeneratePayload;
    }

    return basePayload as ConcealPayload;
  };

  /**
   * Handles form submission for both conceal and generate operations
   */
  const submit = async (type: SubmitType = 'conceal') =>
    wrap(async () => {
      // Skip validation for generate operations
      if (type === 'conceal' && !validation.validate()) {
        throw createError('Please check the form for errors', 'human');
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
