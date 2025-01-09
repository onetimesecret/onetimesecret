// src/composables/useSecretConcealer.ts

import { ref } from 'vue';
import { useSecretStore } from '@/stores/secretStore';
import { useRouter } from 'vue-router';
import {
  concealPayloadSchema,
  ConcealPayload,
  GeneratePayload,
} from '@/schemas/api/payloads';
import { useAsyncHandler, AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { ConcealData } from '@/schemas';

export function useSecretConcealer() {
  const secretStore = useSecretStore();
  const router = useRouter();
  const notifications = useNotificationsStore();

  const formData = ref<ConcealPayload>({
    kind: 'share',
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

  const { wrap } = useAsyncHandler(asyncOptions);

  const submit = async (kind: 'generate' | 'share') => {
    return wrap(async () => {
      const payload = { ...formData.value, kind };
      let response;
      if (kind === 'generate') {
        response = await secretStore.generate(payload as GeneratePayload);
      } else {
        response = await secretStore.conceal(payload as ConcealPayload);
      }
      router.push({
        name: 'Metadata',
        params: { metadataKey: response.record.metadata.key },
      });
      return response;
    });
  };

  const reset = () => {
    formData.value = <SecretFormData>{};
    error.value = null;
  };

  return {
    formData,
    isSubmitting,
    error,
    submit,
    reset,
  };
}
