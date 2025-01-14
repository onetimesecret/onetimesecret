// src/composables/useSecretConcealer.ts

import { ref } from 'vue';

import { useSecretForm } from './useSecretForm';
import { useRouter } from 'vue-router';
import { useSecretStore } from '@/stores/secretStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import {
  AsyncHandlerOptions,
  useAsyncHandler,
} from '@/composables/useAsyncHandler';
import {
  concealPayloadSchema,
  generatePayloadSchema,
} from '@/schemas/api/payloads';
import { useDomainDropdown } from './useDomainDropdown';
import { ConcealDataResponse } from '@/schemas/api';

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
export function useSecretConcealer() {
  const secretStore = useSecretStore();
  const router = useRouter();
  const notifications = useNotificationsStore();

  const isSubmitting = ref(false);
  const error = ref<string | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSubmitting.value = loading),
    // onError: (err) => (error.value = err.message),
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);
  const { form, validate, hasContent, reset } = useSecretForm();
  const { selectedDomain } = useDomainDropdown();

  /**
   * Creates API payload from form state
   */
  const createConcealPayload = () => {
    const payload = {
      kind: 'conceal' as const,
      secret: form.secret,
      ttl: form.ttl,
      passphrase: form.passphrase,
      recipient: form.recipient,
      share_domain: selectedDomain.value,
    };
    return concealPayloadSchema.strip().parse(payload);
  };

  /**
   * Creates generation payload from form state
   */
  const createGeneratePayload = () => {
    const payload = {
      kind: 'generate' as const,
      ttl: form.ttl,
      passphrase: form.passphrase,
      recipient: form.recipient,
      share_domain: selectedDomain.value,
    };
    // const payload = validate();
    // const payload = formSchema.parse(form); // throws ZodError
    return generatePayloadSchema.strip().parse(payload);
  };

  /**
   * Handles successful secret creation
   */
  const handleSuccess = async (response: ConcealDataResponse) => {
    await router.push({
      name: 'Metadata link',
      params: { metadataKey: response.record.metadata.key },
    });
    reset();
    return response;
  };

  /**
   * Conceals a secret using form data
   */
  const conceal = () => {
    wrap(async () => {
      const payload = createConcealPayload();
      const response = await secretStore.conceal(payload);
      return handleSuccess(response);
    });
  };

  /**
   * Generates a secret using form data
   */
  const generate = () =>
    wrap(async () => {
      const payload = createGeneratePayload();
      const response = await secretStore.generate(payload);
      return handleSuccess(response);
    });

  return {
    form,
    validate,
    isSubmitting,
    error,
    hasContent,
    conceal,
    generate,
    reset,
  };
}
