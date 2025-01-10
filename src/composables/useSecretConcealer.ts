// src/composables/useSecretConcealer.ts

import { computed, ref } from 'vue';
import { useSecretStore } from '@/stores/secretStore';
import { useRouter } from 'vue-router';
import { ConcealPayload, GeneratePayload } from '@/schemas/api/payloads';
import { useAsyncHandler, AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import { useNotificationsStore } from '@/stores/notificationsStore';

export function useSecretConcealer() {
  const secretStore = useSecretStore();
  const router = useRouter();
  const notifications = useNotificationsStore();

  const formData = ref<ConcealPayload>({
    kind: 'conceal',
    secret: '',
    share_domain: '', // Default domain should be set here
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

  const submit = async (kind: 'generate' | 'conceal') =>
    wrap(async () => {
      const payload = { ...formData.value, kind };
      const response = await (kind === 'generate'
        ? secretStore.generate(payload as GeneratePayload)
        : secretStore.conceal(payload as ConcealPayload));

      // Add error handling for navigation
      await router.push({
        name: 'Metadata',
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
    submit,
    reset,
    hasInitialContent,
  };
}
