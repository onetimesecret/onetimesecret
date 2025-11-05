<!-- src/components/secrets/canonical/SecretConfirmationForm.vue -->

<script setup lang="ts">
  import NeedHelpModal from '@/components/modals/NeedHelpModal.vue';
  import SecretRecipientHelpContent from '@/components/secrets/SecretRecipientHelpContent.vue';
  import { Secret, SecretDetails } from '@/schemas/models';
  import { ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  interface Props {
    secretIdentifier: string;
    record: Secret | null;
    details: SecretDetails | null;
    isSubmitting: boolean;
    error: unknown;
  }

  const props = defineProps<Props>();
  const emit = defineEmits(['user-confirmed']);
  const { t } = useI18n();

  const passphrase = ref('');

  // Generate unique IDs for ARIA attributes based on secretIdentifier
  const formHeadingId = computed(() => `form-heading-${props.secretIdentifier}`);
  const passphraseInputId = computed(() => `passphrase-${props.secretIdentifier}`);
  const passphraseHeadingId = computed(() => `passphrase-heading-${props.secretIdentifier}`);
  const passphraseDescriptionId = computed(() => `passphrase-description-${props.secretIdentifier}`);

  // Determine the primary status message based on record state
  const statusMessage = computed(() => {
    if (props.record?.verification && !props.record?.has_passphrase) {
      return t('web.COMMON.click_to_verify');
    }
    return t('web.shared.your_message_is_ready');
  });

  // Handle form submission
  const submitForm = async () => {
    emit('user-confirmed', passphrase.value);
  };
</script>

<template>
  <div
    :class="['w-full', 'rounded-lg bg-white p-8 dark:bg-gray-800']"
    role="region"
    :aria-labelledby="formHeadingId">
    <!-- Header section with title, status, and help link -->
    <div class="mb-4 flex items-start justify-between">
      <div>
        <h1
          :id="formHeadingId"
          class="text-xl font-bold text-gray-800 dark:text-gray-200">
          {{ statusMessage }}
        </h1>
        <div
          v-if="!record?.has_passphrase"
          class="mt-1 text-base text-gray-600 dark:text-gray-400"
          role="status"
          aria-live="polite">
          {{ $t('web.COMMON.careful_only_see_once') }}
        </div>
      </div>

      <!-- Help Modal Trigger positioned to the right -->
      <NeedHelpModal
        link-icon-name="question-mark-circle-16-solid"
        link-text-label="">
        <!-- prettier-ignore-attribute class -->
        <button
          type="button"
          class="ml-4 text-sm font-medium
            text-brand-600 hover:text-brand-500
            focus:underline focus:outline-none dark:text-brand-400 dark:hover:text-brand-300">
          {{ $t('web.COMMON.need_help') }}?
        </button>
        <template #content>
          <SecretRecipientHelpContent />
        </template>
      </NeedHelpModal>
    </div>

    <form
      @submit.prevent="submitForm"
      class="space-y-6"
      :aria-labelledby="record?.has_passphrase ? passphraseHeadingId : undefined"
      :aria-describedby="record?.has_passphrase ? passphraseDescriptionId : undefined">
      <!-- Conditional Passphrase Section -->
      <div
        v-if="record?.has_passphrase"
        class="space-y-2">
        <h2
          :id="passphraseHeadingId"
          class="text-lg font-light text-gray-800 dark:text-gray-200">
          {{ $t('web.shared.requires_passphrase') }}
        </h2>
        <div>
          <label
            :for="passphraseInputId"
            class="sr-only">
            {{ $t('web.COMMON.enter_passphrase_here') }}
          </label>
          <!-- prettier-ignore-attribute class -->
          <input
            v-model="passphrase"
            :id="passphraseInputId"
            type="password"
            name="passphrase"
            class="w-full rounded-md border border-gray-300 px-3 py-2
              focus:outline-none focus:ring-2 focus:ring-brand-500
              dark:border-gray-600 dark:bg-gray-700 dark:text-white"
            autocomplete="current-password"
            :placeholder="$t('web.COMMON.enter_passphrase_here')"
            aria-required="true"
            :aria-invalid="error ? 'true' : undefined"
            :aria-errormessage="error ? 'passphrase-error' : undefined"
            :aria-describedby="passphraseDescriptionId"
          />
        </div>
        <p
          v-if="error"
          id="passphrase-error"
          class="mt-1 text-sm text-red-600 dark:text-red-400"
          role="alert">
          {{ String(error) }}
        </p>
      </div>

      <!-- Submission Button -->
      <button
        type="submit"
        :disabled="isSubmitting"
        :class="[
          'w-full rounded-md bg-brand-500 px-6 py-3 text-2xl font-semibold text-white transition duration-150 ease-in-out',
          'hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2',
          'disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-600 dark:hover:bg-brand-600 dark:focus:ring-brand-400',
        ]">
        {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
      </button>
    </form>
  </div>
</template>
