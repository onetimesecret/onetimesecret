<template>
  <div class="space-y-8">
    <!-- Feedback Form -->
    <form @submit.prevent="submitForm"
          class="space-y-6">
      <input type="hidden"
             name="utf8"
             value="✓" />
      <input type="hidden"
             name="shrimp"
             :value="csrfStore.shrimp" />

      <div>
        <label for="feedback-message" class="sr-only">Your feedback</label>
        <textarea id="feedback-message"
          v-model="feedbackMessage"
          class="w-full
                px-3 py-2
                rounded-md
                text-gray-900 placeholder-gray-400
                bg-gray-50 border border-gray-300
                focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500
                dark:bg-gray-700 dark:text-white dark:border-gray-600
                transition-colors"
          name="msg"
          rows="4"
          required
          @keydown="handleKeydown"
          :placeholder="$t('web.COMMON.feedback_text')"
          aria-label="Enter your feedback"></textarea>
        <div class="flex justify-end mt-2 text-gray-500 dark:text-gray-400">
          <span v-if="isDesktop">{{ submitWithText }}</span>
        </div>
      </div>

      <input type="hidden"
             name="tz"
             :value="userTimezone" />
      <input type="hidden"
             name="version"
             :value="ot_version" />

      <button type="submit"
              :disabled="isSubmitting"
              class="w-full
                    px-4 py-2
                    rounded-md
                    font-medium text-white
                    bg-red-600
                    hover:bg-red-700
                    focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 focus:ring-offset-gray-50
                    dark:focus:ring-offset-gray-800
                    disabled:opacity-50 disabled:cursor-not-allowed
                    transition-colors"
              aria-label="Send feedback">
        {{ isSubmitting ? 'Sending...' : $t('web.COMMON.button_send_feedback') }}
      </button>

      <AltchaChallenge v-if="!cust" />
    </form>

    <div v-if="error"
         class="mt-4 text-red-600 dark:text-red-400">{{ error }}</div>
    <div v-if="success"
         class="mt-4 text-green-600 dark:text-green-400">{{ success }}</div>

    <div class="mt-6 text-sm text-gray-500 dark:text-gray-400">
      <h3 class="font-medium text-lg mb-2 text-gray-500">When you submit feedback, we'll see:</h3>
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
import { computed, onMounted, ref } from 'vue';
import { useMediaQuery } from '@vueuse/core';

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
  onError: (data: unknown) => {
    console.error('Error sending feedback:', data);
  },
});

// New function to handle keydown events
const handleKeydown = (event: KeyboardEvent) => {
  // Check if the key pressed is Enter and if Command (Mac) or Control (Windows) is held
  if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
    event.preventDefault(); // Prevent default behavior (new line in textarea)
    submitForm(); // Submit the form
  }
};

// Submit form UI

/**
 * Computed property to determine the submit key combination text based on the platform
 */
const submitWithText = computed(() => {
  return navigator.platform.includes('Mac') ? '⌘ + Enter' : 'Ctrl + Enter';
});

/**
 * State to track if the device is a desktop using useMediaQuery
 */
const isDesktop = useMediaQuery('(min-width: 1024px)');


</script>
