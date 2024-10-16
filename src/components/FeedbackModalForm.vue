<template>
  <div class="space-y-8">
    <!-- Feedback Form -->
    <form @submit.prevent="submitForm"
          class="space-y-4">
      <input type="hidden"
             name="utf8"
             value="✓" />
      <input type="hidden"
             name="shrimp"
             :value="csrfStore.shrimp" />

      <div>
        <label for="feedback-message"
               class="sr-only">Your feedback</label>
        <textarea id="feedback-message"
                  v-model="feedbackMessage"
                  name="msg"
                  rows="3"
                  class="w-full px-3 py-2 bg-gray-700 text-white placeholder-gray-400 border border-gray-600 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500"
                  :placeholder="$t('web.COMMON.feedback_text')"
                  aria-label="Enter your feedback"></textarea>
      </div>

      <input type="hidden"
             name="tz"
             :value="userTimezone" />
      <input type="hidden"
             name="version"
             :value="ot_version" />

      <button type="submit"
              :disabled="isSubmitting"
              class="w-full px-4 py-2 font-medium text-white bg-red-600 rounded-md hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 focus:ring-offset-gray-800 disabled:opacity-50 disabled:cursor-not-allowed"
              aria-label="Send feedback">
        {{ isSubmitting ? 'Sending...' : $t('web.COMMON.button_send_feedback') }}
      </button>

      <AltchaChallenge v-if="!cust" />
    </form>

    <div v-if="error"
         class="mt-4 text-red-400">{{ error }}</div>
    <div v-if="success"
         class="mt-4 text-green-400">{{ success }}</div>

    <div class="mt-6 text-sm text-gray-400">
      <h3 class="font-medium mb-2">Information included with your feedback:</h3>
      <ul class="space-y-1">
        <li v-if="cust">• Customer ID: {{ cust?.custid }}</li>
        <li>• Timezone: {{ userTimezone }}</li>
        <li>• Website Version: v{{ ot_version }}</li>
      </ul>
    </div>
  </div>
</template>

<script setup lang="ts">
import AltchaChallenge from '@/components/AltchaChallenge.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useWindowProps } from '@/composables/useWindowProps';
import { useCsrfStore } from '@/stores/csrfStore';
import { onMounted, ref } from 'vue';

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
