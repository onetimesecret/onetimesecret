// src/composables/useSecretForm.ts
import { ref, computed } from 'vue';
import { useSecretStore } from '@/stores/secretStore';
import { useRouter } from 'vue-router';
import { z } from 'zod';

const concealPayloadSchema = z.object({
  kind: z.enum(['generate', 'share']),
  secret: z.string().min(1),
  share_domain: z.string(),
  recipient: z.string().optional(),
  passphrase: z.string().optional(),
  ttl: z.string().optional(),
});

export function useSecretForm() {
  const secretStore = useSecretStore();
  const router = useRouter();
  const isSubmitting = ref(false);
  const error = ref<string | null>(null);
  const success = ref<string | null>(null);

  const secretContent = ref('');
  const formKind = ref<'generate' | 'share'>('share');

  const handleButtonClick = (kind: 'generate' | 'share') => {
    formKind.value = kind;
    submitForm();
  };

  async function submitForm() {
    try {
      isSubmitting.value = true;
      error.value = null;
      success.value = null;

      const form = document.getElementById('createSecret') as HTMLFormElement;
      const formData = new FormData(form);
      formData.append('kind', formKind.value);

      const payload = Object.fromEntries(formData.entries());
      const validated = concealPayloadSchema.parse(payload);

      const response = await secretStore.conceal(validated);

      router.push({
        name: 'Metadata link',
        params: { metadataKey: response.record.metadata.key },
      });
    } catch (err) {
      error.value = err instanceof Error ? err.message : 'An error occurred';
    } finally {
      isSubmitting.value = false;
    }
  }

  return {
    secretContent,
    formKind,
    isSubmitting,
    error,
    success,
    handleButtonClick,
    submitForm,
  };
}
