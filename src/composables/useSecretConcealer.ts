// src/composables/useSecretConcealer.ts

import { computed, ref } from 'vue';
import { useSecretStore } from '@/stores/secretStore';
import { useRouter } from 'vue-router';
import {
  ConcealPayload,
  GeneratePayload,
  concealPayloadSchema,
  generatePayloadSchema,
} from '@/schemas/api/payloads';
import { useAsyncHandler, AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { useDomainDropdown } from './useDomainDropdown';

const { selectedDomain } = useDomainDropdown();

/* eslint-disable max-lines-per-function */
export function useSecretConcealer() {
  const secretStore = useSecretStore();
  const router = useRouter();
  const notifications = useNotificationsStore();

  const formData = ref<ConcealPayload>({
    kind: 'conceal',
    share_domain: '',
    secret: '',
    ttl: 0,
    passphrase: '',
    recipient: '',
  });

  const isSubmitting = ref(false);
  const error = ref<string | null>(null);

  const asyncOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isSubmitting.value = loading),
    onError: (err) => (error.value = err.message),
  };

  const hasInitialContent = computed(() => formData.value?.secret?.trim().length > 0);

  const { wrap } = useAsyncHandler(asyncOptions);

  const conceal = () =>
    wrap(async () => {
      const payload = {
        ...formData.value,
        kind: 'conceal',
        share_domain: selectedDomain.value,
      };
      const validatedPayload = concealPayloadSchema.strip().parse(payload);
      const response = await secretStore.conceal(validatedPayload);

      await router.push({
        name: 'Metadata link',
        params: { metadataKey: response.record.metadata.key },
      });
      return response;
    });

  const generate = () =>
    wrap(async () => {
      const payload: GeneratePayload = {
        kind: 'generate',
        share_domain: selectedDomain.value,
        ttl: formData.value.ttl,
        passphrase: formData.value.passphrase,
        recipient: formData.value.recipient,
      };
      const validatedPayload = generatePayloadSchema.strip().parse(payload);
      const response = await secretStore.generate(validatedPayload);

      await router.push({
        name: 'Metadata link',
        params: { metadataKey: response.record.metadata.key },
      });
      return response;
    });

  const reset = () => {
    formData.value = <ConcealPayload>{};
    error.value = null;
  };

  return {
    formData,
    isSubmitting,
    error,
    generate,
    conceal,
    reset,
    hasInitialContent,
  };
}
