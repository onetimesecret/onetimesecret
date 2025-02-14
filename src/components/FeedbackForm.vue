<script setup lang="ts">
import AltchaChallenge from '@/components/AltchaChallenge.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { WindowService } from '@/services/window.service';
import { useCsrfStore } from '@/stores/csrfStore';
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
  showRedButton: boolean | null;
}

withDefaults(defineProps<Props>(), {
  enabled: true,
  showRedButton: false,
})

const userTimezone = ref('');
const feedbackMessage = ref('');

const resetForm = () => {
  feedbackMessage.value = '';
  // Reset other non-hidden form fields here if you have any
};

onMounted(() => {
  userTimezone.value = Intl.DateTimeFormat().resolvedOptions().timeZone;
});

// We use this to determine whether to include the authenticity check
const windowProps = WindowService.getMultiple({
  cust: null,
  ot_version: '',
});

const emit = defineEmits(['feedback-sent']);

const submitWithCheck = async (event?: Event) => {
  console.debug('Submitting exception form');

  await submitForm(event);
};

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: '/api/v2/feedback',
  successMessage: t('web.LABELS.feedback-received'),
  onSuccess: () => {
    emit('feedback-sent');
    resetForm();
  },
  onError: (data: unknown) => {
    console.error('Error sending feedback:', data);
  },
});
</script>

<template>
  <div class="space-y-8">
    <!-- Feedback Form -->
    <div class="overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800">
      <div class="p-6">
        <form
          @submit.prevent="submitWithCheck"
          class="space-y-4">
          <input
            type="hidden"
            name="utf8"
            value="✓"
          />
          <input
            type="hidden"
            name="shrimp"
            :value="csrfStore.shrimp"
          />

          <div class="flex flex-col gap-4">
            <div class="grow">
              <label
                for="feedback-message"
                class="sr-only">{{ $t('your-feedback') }}</label>
              <textarea
                id="feedback-message"
                v-model="feedbackMessage"
                name="msg"
                rows="3"
                class="w-full resize-y rounded-md border border-gray-300 px-4 py-2
                  focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500
                  dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200"
                :placeholder="$t('web.COMMON.feedback_text')"></textarea>
              <input
                type="hidden"
                name="tz"
                :value="userTimezone"
              />
              <input
                type="hidden"
                name="version"
                :value="windowProps.ot_version"
              />
            </div>

            <div class="flex justify-end">
              <button
                type="submit"
                :disabled="isSubmitting"
                :class="[
                  'w-full rounded-md px-6 py-2 font-medium text-white transition duration-150 ease-in-out sm:w-auto',
                  showRedButton
                    ? 'bg-brand-600 hover:bg-brand-700 focus:ring-brand-500'
                    : 'bg-gray-500 hover:bg-gray-600 focus:ring-gray-400',
                  isSubmitting ? 'cursor-not-allowed opacity-50' : ''
                ]"
                :aria-label="$t('web.feedback.send-feedback')">
                {{ isSubmitting ? $t('web.feedback.sending-ellipses') : $t('web.COMMON.button_send_feedback') }}
              </button>
            </div>
          </div>

          <AltchaChallenge v-if="!windowProps.cust" />
        </form>

        <div
          v-if="error"
          role="alert"
          aria-live="polite"
          class="mt-4 text-red-600 dark:text-red-400">
          {{ error }}
        </div>
        <div
          v-if="success"
          class="mt-4 text-green-600 dark:text-green-400">
          {{ success }}
        </div>
      </div>

      <div class="bg-gray-50 px-6 py-4 dark:bg-gray-700">
        <h3 class="mb-2 text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ $t('web.feedback.when-you-submit-feedback-well-see') }}
        </h3>
        <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
          <li
            v-if="windowProps.cust"
            class="flex items-center">
            <svg
              class="mr-2 size-4 text-brand-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
              />
            </svg>
            {{ $t('web.account.customer-id') }}: {{ windowProps.cust?.custid }}
          </li>
          <li class="flex items-center">
            <svg
              class="mr-2 size-4 text-brand-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            {{ $t('web.account.timezone', [userTimezone]) }}
          </li>
          <li class="flex items-center">
            <svg
              class="mr-2 size-4 text-brand-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"
              />
            </svg>
            {{ $t('web.site.website-version') }}: v{{ windowProps.ot_version }}
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
