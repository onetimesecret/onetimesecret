<!-- src/components/secrets/canonical/SecretConfirmationForm.vue -->

<script setup lang="ts">
import { Secret, SecretDetails } from '@/schemas/models';
import { ref } from 'vue';

interface Props {
  secretKey: string;
  record: Secret | null;
  details: SecretDetails | null;
  isSubmitting: boolean;
  error: unknown;
}

defineProps<Props>();

const emit = defineEmits(['user-confirmed']);
// const useSecret = useSecret();
const passphrase = ref('');

const submitForm = async () => {
  emit('user-confirmed', passphrase.value);
};
</script>

<template>
  <div
    :class="[
      'w-full',
      'rounded-lg bg-white p-8 dark:bg-gray-800'
    ]"
    role="region"
    :aria-label="$t('secret-confirmation')">
    <p
      v-if="record?.verification && !record?.has_passphrase"
      class="text-base text-gray-600 dark:text-gray-400"
      role="status"
      aria-live="polite">
      {{ $t('web.COMMON.click_to_verify') }}
    </p>

    <h1
      v-if="record?.has_passphrase"
      class="text-xl font-bold text-gray-800 dark:text-gray-200"
      id="passphrase-heading">
      {{ $t('web.shared.requires_passphrase') }}
    </h1>

    <form
      @submit.prevent="submitForm"
      class="space-y-4"
      aria-labelledby="passphrase-heading"
      :aria-describedby="record?.has_passphrase ? 'passphrase-description' : undefined">
      <div v-if="record?.has_passphrase" class="space-y-2">
        <p
          v-if="error"
          class="text-sm text-red-600 dark:text-red-400"
          role="alert">
          {{ error }}
        </p>
        <label
          :for="'passphrase-' + secretKey"
          class="sr-only">
          {{ $t('web.COMMON.enter_passphrase_here') }}
        </label>
        <input
          v-model="passphrase"
          :id="'passphrase-' + secretKey"
          type="password"
          name="passphrase"
          class="w-full rounded-md border border-gray-300 px-3 py-2
            focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
          autocomplete="current-password"
          :aria-label="$t('web.COMMON.enter_passphrase_here')"
          :placeholder="$t('web.COMMON.enter_passphrase_here')"
          aria-required="true"
        />
        <p
          id="passphrase-description"
          class="text-sm text-gray-500 dark:text-gray-400">
          {{ $t('web.COMMON.careful_only_see_once') }}
        </p>
      </div>

      <button
        type="submit"
        :disabled="isSubmitting"
        :class="[
          'w-full rounded-md bg-brand-500 px-6 py-3 text-3xl font-semibold text-white transition duration-150 ease-in-out',
          'hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2',
          'disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-600 dark:hover:bg-brand-600 dark:focus:ring-brand-400'
        ]"
        aria-live="polite">
        <span class="sr-only">{{ isSubmitting ? 'Submitting...' : 'Click to continue' }}</span>
        {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
      </button>
    </form>
  </div>
</template>
