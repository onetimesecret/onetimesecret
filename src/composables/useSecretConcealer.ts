// src/composables/useSecretConcealer.ts

import { computed, ref } from 'vue';
import { useSecretStore } from '@/stores/secretStore';
import { useRouter } from 'vue-router';
import { ConcealPayload, GeneratePayload } from '@/schemas/api/payloads';
import { useAsyncHandler, AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import { useNotificationsStore } from '@/stores/notificationsStore';

/* eslint-disable max-lines-per-function */
export function useSecretConcealer() {
  const secretStore = useSecretStore();
  const router = useRouter();
  const notifications = useNotificationsStore();

  const formData = ref<ConcealPayload>({
    kind: 'conceal',
    secret: '',
    share_domain: '',
    ttl: null, // Default TTL
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

  const hasInitialContent = computed(() => formData.value.secret.trim().length > 0);

  const { wrap } = useAsyncHandler(asyncOptions);

  const generate = async () => {
    const payload = { ...formData.value, kind: 'generate' };
    const response = await secretStore.generate(payload as GeneratePayload);
    return submitAction(response);
  };

  const conceal = async () => {
    const payload = { ...formData.value, kind: 'conceal' };
    const response = await secretStore.conceal(payload as ConcealPayload);
    return submitAction(response);
  };

  const submitAction = async (response: any) => {
    wrap(async () => {
      await router.push({
        name: 'Metadata link',
        params: { metadataKey: response.record.metadata.key },
      });
      return response;
    });
  };

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
