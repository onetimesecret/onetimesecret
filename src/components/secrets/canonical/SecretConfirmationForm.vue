<template>
  <div :class="[
    'w-full',
    'bg-white dark:bg-gray-800 rounded-lg p-8'
  ]">

    <p v-if="record?.verification && !record?.has_passphrase"
       class="text-md text-gray-600 dark:text-gray-400">
      {{ $t('web.COMMON.click_to_verify') }}
    </p>

    <h2 v-if="record?.has_passphrase"
        class="text-xl font-bold text-gray-800 dark:text-gray-200">
      {{ $t('web.shared.requires_passphrase') }}
    </h2>

    <form @submit.prevent="submitForm"
          class="space-y-4"
          aria-label="Secret confirmation form">
      <input name="shrimp"
             type="hidden"
             :value="1" />
      <input name="continue"
             type="hidden"
             value="true" />

      <input v-if="record?.has_passphrase"
             v-model="passphrase"
             type="password"
             name="passphrase"
             class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
             autocomplete="current-password"
             :aria-label="$t('web.COMMON.enter_passphrase_here')"
             :placeholder="$t('web.COMMON.enter_passphrase_here')" />

      <button type="submit"
              :disabled="isSubmitting"
              :class="[
                'w-full px-6 py-3 text-3xl font-semibold text-white bg-brand-500 rounded-md hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800 transition duration-150 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed',
                'mt-4'
              ]"
              aria-live="polite">
        {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
      </button>
    </form>

    <div class="text-right mt-4">
      <p class="text-sm text-gray-500 dark:text-gray-400 italic">
        {{ $t('web.COMMON.careful_only_see_once') }}
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { SecretData, SecretDetails } from '@/schemas/models';
import { useSecretsStore } from '@/stores/secretsStore';
import { ref } from 'vue';

interface Props {
  secretKey: string;
  record: SecretData | null;
  details: SecretDetails | null;
}

const props = defineProps<Props>();
const secretStore = useSecretsStore();
const passphrase = ref('');
const isSubmitting = ref(false);

const submitForm = async () => {
  if (isSubmitting.value) return;

  isSubmitting.value = true;
  try {
    await secretStore.revealSecret(props.secretKey, passphrase.value);
  } catch (error) {
    // Error handling done by store
  } finally {
    isSubmitting.value = false;
  }
};
</script>
