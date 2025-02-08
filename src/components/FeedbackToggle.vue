<!-- src/components/FeedbackToggle.vue -->

<script setup lang="ts">
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  const { t } = useI18n();

  import FeedbackModal from './modals/FeedbackModal.vue';
  import OIcon from './icons/OIcon.vue';

  const isFeedbackModalOpen = ref(false);

  const toggleFeedbackModal = () => {
    isFeedbackModalOpen.value = true;
  };

  const closeFeedbackModal = () => {
    isFeedbackModalOpen.value = false;
  };
</script>

<template>
  <div class="relative">
    <button
      @click="toggleFeedbackModal"
      class="group inline-flex flex-nowrap items-center space-x-2 rounded-md transition-colors
                 bg-gray-200 dark:bg-gray-700
                 text-gray-700 dark:text-gray-400
                 hover:bg-gray-200 dark:hover:bg-gray-700
                 hover:text-gray-900 dark:hover:text-gray-300
                 focus:outline-none focus:ring-2 focus:ring-brand-500
                 focus:ring-offset-2 focus:ring-offset-white dark:ring-offset-gray-900
                 dark:focus:ring-brand-400 dark:focus:ring-offset-gray-900
                 px-3 py-1.5 text-sm font-medium whitespace-nowrap"
      aria-label="$t('open-feedback-form')">
      <span class="inline">{{ t('feedback') }}</span>
      <OIcon
      class="size-5 text-gray-500 dark:text-gray-400
             group-hover:text-brand-500 dark:group-hover:text-brand-400
             transition-colors"
        collection="heroicons"
        name="chat-bubble-bottom-center-text"
        />
    </button>

    <Teleport to="body">
      <Transition
        enter-active-class="transition ease-out duration-200"
        enter-from-class="opacity-0 translate-y-1"
        enter-to-class="opacity-100 translate-y-0"
        leave-active-class="transition ease-in duration-150"
        leave-from-class="opacity-100 translate-y-0"
        leave-to-class="opacity-0 translate-y-1">
        <div v-if="isFeedbackModalOpen">
          <FeedbackModal
            @close="closeFeedbackModal"
            :is-open="isFeedbackModalOpen"
          />
        </div>
      </Transition>
    </Teleport>
  </div>
</template>
