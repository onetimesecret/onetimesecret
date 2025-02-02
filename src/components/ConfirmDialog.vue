<script setup lang="ts">
import { ref } from 'vue';

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

const confirm = () => {
  isVisible.value = false;
  emit('confirm');
};

const cancel = () => {
  isVisible.value = false;
  emit('cancel');
};
</script>


<template>
  <div
    v-if="isVisible"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 dark:bg-black/70">
    <div
      class="mx-4 w-full max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800"
      role="dialog"
      aria-modal="true">
      <h2 class="mb-4 text-xl font-bold text-gray-900 dark:text-white">
        {{ title }}
      </h2>
      <p class="mb-6 text-gray-600 dark:text-gray-300">
        {{ message }}
      </p>

      <div class="flex justify-end space-x-2">
        <button
          @click="cancel"
          class="rounded px-4 py-2 text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700">
          {{ $t(cancelText) }}
        </button>
        <button
          @click="confirm"
          :class="[
            'rounded px-4 py-2',
            type === 'danger'
              ? 'bg-red-500 text-white hover:bg-red-600 dark:bg-red-600 dark:hover:bg-red-700'
              : 'bg-blue-500 text-white hover:bg-blue-600 dark:bg-blue-600 dark:hover:bg-blue-700'
          ]">
          <span class="font-bold">{{ $t(confirmText) }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
