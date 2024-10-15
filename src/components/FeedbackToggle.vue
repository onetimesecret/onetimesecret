<template>
  <div class="flex items-center">
    <button @click="toggleFeedbackModal"
                    class="rounded-md hover:bg-gray-200 dark:hover:bg-gray-700 opacity-80 text-gray-400 dark:text-gray-400 hover:text-brand-500 dark:hover:text-brand-400 transition-colors p-1"


            aria-label="Open feedback form">
      <svg xmlns="http://www.w3.org/2000/svg"
           class="h-6 w-6"
           fill="none"
           viewBox="0 0 24 24"
           stroke="currentColor">
        <path stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" />
      </svg>
    </button>
    <FeedbackModal :is-open="isFeedbackModalOpen"
                   @close="closeFeedbackModal" />
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import FeedbackModal from './modals/FeedbackModal.vue'

const isFeedbackModalOpen = ref(false)

const toggleFeedbackModal = () => {
  isFeedbackModalOpen.value = true
}

const closeFeedbackModal = () => {
  isFeedbackModalOpen.value = false
}
</script>
