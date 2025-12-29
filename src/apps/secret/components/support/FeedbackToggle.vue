<!-- src/apps/secret/components/support/FeedbackToggle.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { ref } from 'vue';
  const { t } = useI18n();

  import OIcon from '@/shared/components/icons/OIcon.vue';
  import FeedbackModal from '@/shared/components/modals/FeedbackModal.vue';

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
      class="group inline-flex flex-nowrap items-center whitespace-nowrap rounded-md
                 bg-gray-200 px-3
                 py-1.5 text-sm
                 font-medium text-gray-700
                 transition-colors hover:bg-gray-200
                 hover:text-gray-900 focus:outline-none focus:ring-2
                 focus:ring-brand-500 focus:ring-offset-2 focus:ring-offset-white
                 dark:bg-gray-700 dark:text-gray-400
                 dark:ring-offset-gray-900 dark:hover:bg-gray-700 dark:hover:text-gray-300 dark:focus:ring-brand-400 dark:focus:ring-offset-gray-900 sm:space-x-2"
      :aria-label="t('web.feedback.open-feedback-form')">
      <span class="hidden sm:inline sm:pl-1">{{ t('web.colonel.feedback') }}</span>
      <OIcon
        class="size-5 text-gray-500 transition-colors
             group-hover:text-brand-500 dark:text-gray-400
             dark:group-hover:text-brand-400"
        collection="heroicons"
        name="chat-bubble-bottom-center-text" />
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
            :is-open="isFeedbackModalOpen" />
        </div>
      </Transition>
    </Teleport>
  </div>
</template>
