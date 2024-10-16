<template>
  <teleport to="body">
    <div v-if="isOpen"
         class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4 sm:p-6"
         aria-labelledby="feedback-modal-title"
         role="dialog"
         aria-modal="true">
      <div class="bg-gray-800 p-6 rounded-lg w-full max-w-md max-h-[90vh] overflow-y-auto shadow-xl">
        <div class="flex justify-between items-center mb-4">
          <h2 id="feedback-modal-title" class="text-xl font-semibold text-white">
            Provide Feedback
          </h2>
          <button @click="close"
                  class="text-gray-400 hover:text-white transition-colors"
                  aria-label="Close feedback modal">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>

        <FeedbackModalForm :showRedButton="true" />

        <p class="mt-4 text-xs text-center text-gray-400 italic">
          Your feedback helps us improve. Especially the annoyances!
        </p>
      </div>
    </div>
  </teleport>
</template>


<script setup>


import FeedbackModalForm from '@/components/FeedbackModalForm.vue'

defineProps({
  isOpen: Boolean,
});

const emit = defineEmits(['close']);

const close = () => {
  emit('close');
};
</script>
