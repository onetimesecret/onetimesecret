<!-- src/apps/secret/components/incoming/IncomingSecretFormBody.vue -->

<script setup lang="ts">
  /**
   * Incoming Secret Form Body
   *
   * The pure form for sending an incoming secret: recipient dropdown,
   * secret content, memo, and submit/reset actions. Extracted from the
   * /incoming route page (IncomingForm.vue) so the branded custom-domain
   * homepage can embed the same flow.
   *
   * Deliberately owns NO gating: callers decide whether the feature is
   * available (entitlement, enabled, recipients) and load the incoming
   * config before rendering this component. The route page keeps its
   * EmptyStates; the branded homepage degrades to its trust card.
   *
   * Optional branding props mirror SecretForm's contract so the embedded
   * form tracks the domain's brand color; without them the form renders
   * exactly as the /incoming route page always has.
   */
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useIncomingSecret } from '@/shared/composables/useIncomingSecret';
  import IncomingMemoInput from '@/apps/secret/components/incoming/IncomingMemoInput.vue';
  import IncomingRecipientDropdown from '@/apps/secret/components/incoming/IncomingRecipientDropdown.vue';
  import SecretContentInputArea from '@/apps/secret/components/form/SecretContentInputArea.vue';

  interface Props {
    /** Brand color for the submit button (falls back to the brand classes). */
    primaryColor?: string;
  }

  const props = withDefaults(defineProps<Props>(), {
    primaryColor: '',
  });

  const { t } = useI18n();
  const {
    form,
    errors,
    isSubmitting,
    memoMaxLength,
    recipients,
    isFormValid,
    validateMemo,
    validateSecret,
    validateRecipient,
    submit,
  } = useIncomingSecret();

  const secretContentRef = ref<InstanceType<typeof SecretContentInputArea> | null>(null);

  const handleTitleBlur = () => {
    validateMemo();
  };

  const handleRecipientBlur = () => {
    validateRecipient();
  };

  const handleSecretUpdate = (content: string) => {
    form.value.secret = content;
    if (errors.value.secret && content.trim()) {
      validateSecret();
    }
  };

  const handleSubmit = async () => {
    await submit();
  };

  const handleReset = () => {
    form.value.memo = '';
    form.value.secret = '';
    form.value.recipientId = '';
    errors.value = {};
    secretContentRef.value?.clearTextarea();
  };
</script>

<template>
  <div class="overflow-hidden rounded-2xl bg-white shadow-lg dark:bg-slate-800">
    <form
      @submit.prevent="handleSubmit"
      class="space-y-8 p-8 sm:p-10"
      data-testid="incoming-form">
      <!-- Recipient Dropdown (First - like e-transfer) -->
      <IncomingRecipientDropdown
        v-model="form.recipientId"
        :recipients="recipients"
        :error="errors.recipientId"
        :disabled="isSubmitting"
        @blur="handleRecipientBlur" />

      <!-- Secret Content (Second) -->
      <div>
        <label
          for="secret-content"
          class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('incoming.secret_content_label') }}
          <span
            v-if="errors.secret"
            class="text-red-500">
            *
          </span>
        </label>

        <SecretContentInputArea
          ref="secretContentRef"
          :initial-content="form.secret"
          :disabled="isSubmitting"
          :max-length="10000"
          @update:content="handleSecretUpdate" />

        <span
          v-if="errors.secret"
          class="mt-1 block text-sm text-red-600 dark:text-red-400"
          data-testid="incoming-secret-error">
          {{ errors.secret }}
        </span>
      </div>

      <!-- Memo Input (Last - optional, like e-transfer) -->
      <IncomingMemoInput
        v-model="form.memo"
        :max-length="memoMaxLength"
        :error="errors.memo"
        :disabled="isSubmitting"
        @blur="handleTitleBlur" />

      <!-- Action Buttons -->
      <div
        class="flex flex-col gap-4 border-t border-gray-200 pt-8 dark:border-gray-700 sm:flex-row sm:items-center sm:justify-between">
        <button
          type="button"
          :disabled="isSubmitting"
          class="order-2 rounded-xl border-2 border-gray-300 bg-white px-6 py-3.5 text-base font-semibold text-gray-700 shadow-sm transition-all duration-200 hover:border-gray-400 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-slate-800 dark:text-gray-300 dark:hover:border-gray-500 dark:hover:bg-slate-700 sm:order-1"
          @click="handleReset"
          data-testid="incoming-form-reset">
          {{ t('incoming.reset_form') }}
        </button>

        <button
          type="submit"
          :disabled="isSubmitting || !isFormValid"
          class="order-1 flex items-center justify-center gap-2 rounded-xl px-8 py-3.5 text-base font-semibold text-white shadow-md transition-all duration-300 sm:order-2"
          :class="
            isFormValid && !isSubmitting
              ? [
                  'hover:scale-105 hover:shadow-lg active:scale-100',
                  props.primaryColor ? '' : 'bg-brand-500 hover:bg-brand-600',
                ]
              : 'cursor-not-allowed bg-gray-400 opacity-60 dark:bg-gray-600'
          "
          :style="
            props.primaryColor && isFormValid && !isSubmitting
              ? { backgroundColor: props.primaryColor }
              : undefined
          "
          data-testid="incoming-form-submit">
          <svg
            class="size-5 text-white"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            viewBox="0 0 24 24"
            aria-hidden="true">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
          </svg>
          {{ isSubmitting ? t('incoming.submitting') : t('incoming.submit_secret') }}
        </button>
      </div>
    </form>
  </div>
</template>
