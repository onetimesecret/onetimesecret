<template>
  <div class="flex items-center">
    <button
      @click="openFeedbackModal"
      class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors p-1"
      aria-label="Open feedback form"
    >
      <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" />
      </svg>
    </button>

    <teleport to="body">
      <div v-if="isFeedbackModalOpen"
           class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
        <div class="bg-white dark:bg-gray-800 p-8 rounded-lg w-full max-w-3xl max-h-[90vh] overflow-y-auto">
          <div class="flex justify-between items-center mb-6">
            <h2 class="text-2xl font-bold text-gray-900 dark:text-gray-100">Feedback</h2>
            <button @click="closeFeedbackModal"
                    class="text-gray-600 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors">
              <svg xmlns="http://www.w3.org/2000/svg"
                   class="h-6 w-6"
                   fill="none"
                   viewBox="0 0 24 24"
                   stroke="currentColor">
                <path stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <FeedbackForm :showRedButton="false"
                        @submitted="closeFeedbackModal" />
        </div>
      </div>
    </teleport>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import FeedbackForm from './FeedbackForm.vue'

const isFeedbackModalOpen = ref(false)

const openFeedbackModal = () => {
  isFeedbackModalOpen.value = true
}

const closeFeedbackModal = () => {
  isFeedbackModalOpen.value = false
}
</script>
