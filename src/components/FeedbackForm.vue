<template>
  <div class="space-y-8">
    <!-- Feedback Form -->
    <div class="bg-white dark:bg-gray-800 shadow-md rounded-lg overflow-hidden">
      <div class="p-6">
        <h2 class="text-xl font-semibold mb-4 text-gray-800 dark:text-gray-200">Submit Your Feedback</h2>
        <form @submit.prevent="submitForm"
              class="space-y-4">
          <input type="hidden"
                 name="utf8"
                 value="✓" />
          <input type="hidden"
                 name="shrimp"
                 :value="csrfStore.shrimp" />

          <div class="flex flex-col sm:flex-row gap-4">
            <div class="flex-grow">
              <label for="feedback-message"
                     class="sr-only">Your feedback</label>
              <input id="feedback-message"
                     v-model="feedbackMessage"
                     type="text"
                     name="msg"
                     class="w-full px-4 py-2 border border-gray-300 rounded-md
                  focus:border-brand-500 focus:ring-2 focus:ring-brand-500 focus:outline-none
                  dark:bg-gray-700 dark:border-gray-600 dark:text-gray-200"
                     autocomplete="off"
                     :placeholder="$t('web.COMMON.feedback_text')"
                     aria-label="Enter your feedback">
            </div>
            <button type="submit"
                    :disabled="isSubmitting"
                    :class="[
                      'px-6 py-2 font-medium text-white transition duration-150 ease-in-out rounded-md',
                      showRedButton
                        ? 'bg-brand-600 hover:bg-brand-700 focus:ring-brand-500'
                        : 'bg-gray-500 hover:bg-gray-600 focus:ring-gray-400',
                      isSubmitting ? 'opacity-50 cursor-not-allowed' : ''
                    ]"
                    aria-label="Send feedback">
              {{ isSubmitting ? 'Sending...' : $t('web.COMMON.button_send_feedback') }}
            </button>
          </div>

          <AltchaChallenge v-if="!cust" />
        </form>

        <div v-if="error"
             class="mt-4 text-red-600 dark:text-red-400">{{ error }}</div>
        <div v-if="success"
             class="mt-4 text-green-600 dark:text-green-400">{{ success }}</div>
      </div>

      <div class="bg-gray-50 dark:bg-gray-700 px-6 py-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Information included with your feedback:
        </h3>
        <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
          <li v-if="cust"
              class="flex items-center">
            <svg class="h-4 w-4 mr-2 text-brand-500"
                 fill="none"
                 viewBox="0 0 24 24"
                 stroke="currentColor">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
            </svg>
            Customer ID: {{ cust?.custid }}
          </li>
          <li class="flex items-center">
            <svg class="h-4 w-4 mr-2 text-brand-500"
                 fill="none"
                 viewBox="0 0 24 24"
                 stroke="currentColor">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            Timezone: {{ userTimezone }}
          </li>
          <li class="flex items-center">
            <svg class="h-4 w-4 mr-2 text-brand-500"
                 fill="none"
                 viewBox="0 0 24 24"
                 stroke="currentColor">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
            </svg>
            Website Version: v{{ ot_version }}
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import AltchaChallenge from '@/components/AltchaChallenge.vue';
import { useCsrfStore } from '@/stores/csrfStore';
import { useWindowProps } from '@/composables/useWindowProps';
import { useFormSubmission } from '@/composables/useFormSubmission';

const csrfStore = useCsrfStore();

export interface Props {
  enabled?: boolean;
  showRedButton: boolean | null;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = withDefaults(defineProps<Props>(), {
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
const { cust, ot_version } = useWindowProps(['cust', 'ot_version']);

const emit = defineEmits(['feedback-sent']);

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: '/api/v2/feedback',
  successMessage: 'Feedback received.',
  onSuccess: (data: unknown) => {
    console.debug('Feedback sent:', data);
    emit('feedback-sent');
    resetForm();
  },
  onError: (data) => {
    console.error('Error sending feedback:', data);
  },
});
</script>
