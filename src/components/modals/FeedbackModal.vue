<template>
  <teleport to="body">
    <div v-if="isOpen"
         class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4 sm:p-6"
         aria-labelledby="feedback-modal-title"
         role="dialog"
         aria-modal="true">
      <div class="bg-white dark:bg-gray-800 p-6 sm:p-8 rounded-lg w-full max-w-3xl max-h-[90vh] overflow-y-auto shadow-xl">
        <div class="flex justify-between items-center mb-6">
          <h2 id="feedback-modal-title" class="text-2xl font-bold text-gray-900 dark:text-gray-100">
            Provide Feedback
          </h2>
          <button @click="close"
                  class="text-gray-600 hover:text-brand-500 hover:bg-gray-100
                         dark:text-gray-400 dark:hover:text-brand-400 dark:hover:bg-gray-700
                         transition-colors p-2 rounded-full"
                  aria-label="Close feedback modal">
            <svg xmlns="http://www.w3.org/2000/svg"
                 class="h-6 w-6"
                 width="24"
                 height="24"
                 fill="none"
                 viewBox="0 0 24 24"
                 stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <FeedbackForm :showRedButton="true" @submitted="close" />

        <p class="mt-6 text-xs text-center text-gray-500 dark:text-gray-400">
          Your feedback helps us improve. Especially the annoyances!
        </p>
      </div>
    </div>
  </teleport>
</template>

<script setup>
import FeedbackForm from '../FeedbackForm.vue'

defineProps({
  isOpen: Boolean,
});

const emit = defineEmits(['close']);

const close = () => {
  emit('close');
};
</script>
