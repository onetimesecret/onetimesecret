<!-- src/shared/components/modals/ConfirmDialog.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import { FocusTrap } from 'focus-trap-vue';
import { ref } from 'vue';
import { useBackdropClose } from '@/shared/composables/useBackdropClose';

const { t } = useI18n();

withDefaults(defineProps<{
  title: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  type?: 'danger' | 'default';
}>(), {
  confirmText: 'web.COMMON.word_confirm',
  cancelText: 'web.COMMON.word_cancel',
  type: 'default'
});

const emit = defineEmits<{
  (e: 'confirm'): void;
  (e: 'cancel'): void;
}>();

const isVisible = ref(true);
const cancelButton = ref<HTMLButtonElement | null>(null);

const confirm = () => {
  isVisible.value = false;
  emit('confirm');
};

const cancel = () => {
  // Unmounting the focus trap after confirm also fires @deactivate.
  if (!isVisible.value) return;
  isVisible.value = false;
  emit('cancel');
};

const { onBackdropMousedown, onBackdropClick } = useBackdropClose(cancel);
</script>

<template>
  <!-- Teleported to body: an ancestor with backdrop-filter (the settings
       cards use backdrop-blur-sm) becomes the containing block for fixed
       descendants, which would confine the overlay to that card. -->
  <Teleport to="body">
    <div
      v-if="isVisible"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 dark:bg-black/70"
      aria-labelledby="confirm-dialog-title"
      aria-describedby="confirm-dialog-message"
      role="dialog"
      aria-modal="true"
      @mousedown="onBackdropMousedown"
      @click="onBackdropClick">
      <FocusTrap
        :active="isVisible"
        :initial-focus="() => cancelButton ?? false"
        :escape-deactivates="true"
        :click-outside-deactivates="false"
        :allow-outside-click="true"
        @deactivate="cancel">
        <div
          class="mx-4 w-full max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800"
          data-testid="confirm-dialog">
          <h2
            id="confirm-dialog-title"
            class="mb-4 text-xl font-bold text-gray-900 dark:text-white">
            {{ title }}
          </h2>
          <p
            id="confirm-dialog-message"
            class="mb-6 text-gray-600 dark:text-gray-300">
            {{ message }}
          </p>

          <div class="flex justify-end space-x-2">
            <button
              ref="cancelButton"
              @click="cancel"
              data-testid="confirm-dialog-cancel"
              class="rounded px-4 py-2 text-gray-600 hover:bg-gray-100
                dark:text-gray-300 dark:hover:bg-gray-700">
              {{ t(cancelText) }}
            </button>
            <button
              @click="confirm"
              data-testid="confirm-dialog-confirm"
              :class="[
                'rounded px-4 py-2',
                type === 'danger'
                  ? 'bg-red-500 text-white hover:bg-red-600 dark:bg-red-600 dark:hover:bg-red-700'
                  : 'bg-blue-500 text-white hover:bg-blue-600 dark:bg-blue-600 dark:hover:bg-blue-700'
              ]">
              <span class="font-bold">{{ t(confirmText) }}</span>
            </button>
          </div>
        </div>
      </FocusTrap>
    </div>
  </Teleport>
</template>
