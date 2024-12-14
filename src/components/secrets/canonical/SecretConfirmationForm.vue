<script setup lang="ts">
import { Secret, SecretDetails } from '@/schemas/models';
import { useSecretsStore } from '@/stores/secretsStore';
import { ref } from 'vue';

interface Props {
  secretKey: string;
  record: Secret | null;
  details: SecretDetails | null;
}

const props = defineProps<Props>();
const emit = defineEmits(['secret-loaded']); // Add this line
const secretStore = useSecretsStore();
const passphrase = ref('');
const isSubmitting = ref(false);


const submitForm = async () => {
  if (isSubmitting.value) return;

  isSubmitting.value = true;
  try {
    const response = await secretStore.revealSecret(props.secretKey, passphrase.value);
    // Emit the secret-loaded event with the response data
    emit('secret-loaded', {
      record: response.record,
      details: response.details
    });
  } catch {
    // Error handling done by store
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div
    :class="[
      'w-full',
      'rounded-lg bg-white p-8 dark:bg-gray-800'
    ]">
    <p
      v-if="record?.verification && !record?.has_passphrase"
      class="text-md text-gray-600 dark:text-gray-400">
      {{ $t('web.COMMON.click_to_verify') }}
    </p>

    <h2
      v-if="record?.has_passphrase"
      class="text-xl font-bold text-gray-800 dark:text-gray-200">
      {{ $t('web.shared.requires_passphrase') }}
    </h2>

    <form
      @submit.prevent="submitForm"
      class="space-y-4"
      aria-label="Secret confirmation form">
      <input
        name="shrimp"
        type="hidden"
        :value="1"
      />
      <input
        name="continue"
        type="hidden"
        value="true"
      />

      <input
        v-if="record?.has_passphrase"
        v-model="passphrase"
        type="password"
        name="passphrase"
        class="w-full rounded-md border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        autocomplete="current-password"
        :aria-label="$t('web.COMMON.enter_passphrase_here')"
        :placeholder="$t('web.COMMON.enter_passphrase_here')"
      />

      <button
        type="submit"
        :disabled="isSubmitting"
        :class="[
          'w-full rounded-md bg-brand-500 px-6 py-3 text-3xl font-semibold text-white transition duration-150 ease-in-out hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:focus:ring-offset-gray-800',
          'mt-4'
        ]"
        aria-live="polite">
        {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
      </button>
    </form>

    <div class="mt-4 text-right">
      <p class="text-sm italic text-gray-500 dark:text-gray-400">
        {{ $t('web.COMMON.careful_only_see_once') }}
      </p>
    </div>
  </div>
</template>
