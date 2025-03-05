<script setup lang="ts">
import FeedbackModalForm from '@/components/FeedbackModalForm.vue'
import { FocusTrap } from 'focus-trap-vue'
import { ref, onMounted, onBeforeUnmount, nextTick } from 'vue'

defineProps({
  isOpen: Boolean,
});

const closeButton = ref(null);
const emit = defineEmits(['close']);

// Store the element that had focus before the modal opened
let previouslyFocusedElement: HTMLElement | null = null;

onMounted(() => {
  // Store the currently focused element when the component mounts
  previouslyFocusedElement = document.activeElement as HTMLElement;
});

const close = () => {
  emit('close');
  // Return focus to the previous element when modal closes
  nextTick(() => {
    previouslyFocusedElement?.focus();
  });
};

// Clean up when component is destroyed
onBeforeUnmount(() => {
  previouslyFocusedElement = null;
});
</script>

<template>
  <teleport to="body">
    <div v-if="isOpen"
         class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 dark:bg-black/70 sm:p-6"
         aria-labelledby="feedback-modal-title"
         role="dialog"
         aria-modal="true">
      <FocusTrap :active="isOpen"
                 :initial-focus="() => $refs.closeButton"
                 :click-outside-deactivates="true"
                 :escape-deactivates="true"
                 @deactivate="close">
        <div class="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800">
          <div class="mb-6 flex items-center justify-between">
            <h2 id="feedback-modal-title"
                class="text-2xl font-semibold text-gray-900 dark:text-white">
              {{ $t('share-your-feedback') }}
            </h2>
            <button ref="closeButton"
                    @click="close"
                    class="text-gray-400 transition-colors hover:text-gray-500 dark:hover:text-white"
                    :aria-label="$t('close-feedback-modal')">
              <svg xmlns="http://www.w3.org/2000/svg"
                   class="size-6"
                   viewBox="0 0 20 20"
                   fill="currentColor"
                   aria-hidden="true">
                <path fill-rule="evenodd"
                      d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                      clip-rule="evenodd" />
              </svg>
            </button>
          </div>

          <FeedbackModalForm :show-red-button="true" />

          <p class="mt-6 text-center text-sm italic text-gray-500 dark:text-gray-400">
            <RouterLink to="/feedback"
                        class="underline">{{ $t('help-us-improve') }}</RouterLink>{{ $t('all-feedback-welcome') }}
          </p>
        </div>
      </FocusTrap>
    </div>
  </teleport>
</template>
