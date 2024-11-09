<template>
  <div class="relative">
    <button @click="toggleFeedbackModal"
            class="group flex items-center space-x-2 rounded-md
               px-3 py-1.5
               text-sm font-medium
               bg-gray-200 dark:bg-gray-700
               text-gray-700 dark:text-gray-300
               hover:bg-slate-50 dark:hover:bg-slate-900
               focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
               dark:focus:ring-brand-400
               transition-all"
            aria-label="Open feedback form">

      <span class="inline">Feedback</span>
      <svg xmlns="http://www.w3.org/2000/svg"
           class="h-4 w-4 text-gray-500 dark:text-gray-300 group-hover:text-brand-500
                  dark:group-hover:text-brand-400 transition-colors"
           fill="none"
           viewBox="0 0 24 24"
           aria-hidden="true"
           stroke="currentColor">
        <path stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z" />
      </svg>
    </button>

    <Teleport to="body">
      <Transition enter-active-class="transition ease-out duration-200"
                  enter-from-class="opacity-0 translate-y-1"
                  enter-to-class="opacity-100 translate-y-0"
                  leave-active-class="transition ease-in duration-150"
                  leave-from-class="opacity-100 translate-y-0"
                  leave-to-class="opacity-0 translate-y-1">
        <div v-if="isFeedbackModalOpen">
          <FeedbackModal @close="closeFeedbackModal"
                         :isOpen="isFeedbackModalOpen" />
        </div>
      </Transition>
    </Teleport>
  </div>
</template>


<script setup lang="ts">
import { ref } from 'vue';

import FeedbackModal from './modals/FeedbackModal.vue';

const isFeedbackModalOpen = ref(false);

const toggleFeedbackModal = () => {
  isFeedbackModalOpen.value = true;
};

const closeFeedbackModal = () => {
  isFeedbackModalOpen.value = false;
};
</script>
