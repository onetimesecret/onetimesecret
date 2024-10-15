<template>
  <teleport to="body">
    <div v-if="isOpen"
         class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div class="bg-white dark:bg-gray-800 p-8 rounded-lg w-full max-w-3xl max-h-[90vh] overflow-y-auto">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-2xl font-bold text-gray-900 dark:text-gray-100">Feedback</h2>
          <button @click="close"
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
        <FeedbackForm :showRedButton="true"
                      @submitted="close" />
      </div>
    </div>
  </teleport>
</template>

<script setup lang="ts">
import FeedbackForm from '../FeedbackForm.vue'

defineProps<{
  isOpen: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
}>()

const close = () => {
  emit('close')
}
</script>
