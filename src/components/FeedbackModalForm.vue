<script setup lang="ts">
import AltchaChallenge from '@/components/AltchaChallenge.vue';
import { useExceptionReporting } from '@/composables/useExceptionReporting';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { WindowService } from '@/services/window.service';
import { useCsrfStore } from '@/stores/csrfStore';
import { useMediaQuery } from '@vueuse/core';
import { computed, onMounted, ref } from 'vue';
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
const cust = WindowService.get('cust');
const ot_version = WindowService.get('ot_version');

const emit = defineEmits(['feedback-sent']);

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: '/api/v2/feedback',
  successMessage: t('web.LABELS.feedback-received'),
  onSuccess: (data: unknown) => {
    console.debug('Feedback sent:', data);
    emit('feedback-sent');
    resetForm();
  },
  onError: (data: unknown) => {
    console.error('Error sending feedback:', data);
  },
});

const form = ref<HTMLFormElement | null>(null);

const handleKeydown = (event: KeyboardEvent) => {
  if (event.key === t('enter') && (event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    form.value?.requestSubmit(); // This triggers the form submission event
  }
};

// Submit form UI

/**
 * Computed property to determine the submit key combination text based on the platform
 */
const submitWithText = computed(() => {
  return navigator.platform.includes(t('mac')) ? t('enter-0') : t('ctrl-enter');
});

/**
 * State to track if the device is a desktop using useMediaQuery
 */
const isDesktop = useMediaQuery(t('min-width-1024px'));

// UseExceptionReporting integration
const { reportException } = useExceptionReporting();

const handleSpecialMessages = (message: string) => {
  console.log(`Checking for special message: ${message}`)
  if (message.startsWith('#ex')) {
    const error = new Error(t('test-error-triggered-via-feedback'));
    reportException({
      message: t('test-exception-message-substring-11', [message.substring(11)]),
      type: 'TestFeedbackError',
      stack: error.stack || '',
      url: window.location.href,
      line: 0,
      column: 0,
      environment: 'production',
      release: ot_version || 'unknown'
    });
    return true;
  }
  return false;
};

const submitWithCheck = async (event?: Event) => {
  console.debug('Submitting exception form');

  if (handleSpecialMessages(feedbackMessage.value)) {
    // Special message handled, don't submit form
    return;
  }
  await submitForm(event);
};

const buttonText = computed(() => isSubmitting.value ? t('web.LABELS.sending-ellipses') : t('web.COMMON.button_send_feedback'))
</script>

<template>
  <div class="space-y-8">
    <!-- Feedback Form -->
    <form ref="form"
          @submit.prevent="submitWithCheck"
          class="space-y-6">
      <input type="hidden"
             name="utf8"
             value="✓" />
      <input type="hidden"
             name="shrimp"
             :value="csrfStore.shrimp" />

      <div>
        <label for="feedback-message"
               class="sr-only">{{ $t('your-feedback') }}</label>
        <textarea id="feedback-message"
                  v-model="feedbackMessage"
                  class="w-full
                rounded-md border
                border-gray-300
                bg-gray-50 px-3
                py-2 text-gray-900 transition-colors
                placeholder:text-gray-400 focus:border-red-500 focus:outline-none focus:ring-2
                focus:ring-red-500 dark:border-gray-600 dark:bg-gray-700
                dark:text-white"
                  name="msg"
                  rows="4"
                  required
                  @keydown="handleKeydown"
                  :placeholder="$t('web.COMMON.feedback_text')"
                  aria-label="$t('enter-your-feedback')"></textarea>
        <div class="mt-2 flex justify-end text-gray-500 dark:text-gray-400">
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
              :disabled="isSubmitting || feedbackMessage == ''"
              class="w-full
                    rounded-md bg-red-600
                    px-4
                    py-2 font-medium
                    text-white
                    transition-colors
                    hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2
                    focus:ring-offset-gray-50
                    disabled:cursor-not-allowed disabled:opacity-50
                    dark:focus:ring-offset-gray-800"
              :aria-label="$t('web.feedback.send-feedback')">
        {{ buttonText }}
      </button>

      <AltchaChallenge v-if="!cust || cust.identifier == 'anon'" :is-floating="true" />
    </form>

    <div class="h-6">
      <div v-if="error"
          class="mt-4 text-red-600 dark:text-red-400">
        {{ error }}
      </div>
      <div v-if="success"
          class="mt-4 text-green-600 dark:text-green-400">
        {{ success }}
      </div>
    </div>

    <div class="mt-6 text-sm text-gray-500 dark:text-gray-400">
      <h3 class="mb-2 text-lg font-medium text-gray-500">
        {{ $t('web.feedback.when-you-submit-feedback-well-see') }}
      </h3>
      <ul class="space-y-1">
        <li v-if="cust">
          • {{ $t('web.account.customer-id') }} {{ cust?.custid }}
        </li>
        <li>• {{ $t('web.account.timezone') }} {{ userTimezone }}</li>
        <li>• {{ $t('web.site.website-version') }} {{ ot_version }}</li>
      </ul>
    </div>
  </div>
</template>
