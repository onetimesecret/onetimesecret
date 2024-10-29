<template>
  <div class="relative">
    <button
      type="button"
      @click="toggleOpen"
      class="inline-flex items-center px-3 py-2 border border-gray-200 dark:border-gray-600 rounded-lg shadow-sm text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500"
      :aria-expanded="isOpen"
      aria-haspopup="true">
      <Icon
        icon="mdi:text-box-edit"
        class="w-5 h-5 mr-2"
        aria-hidden="true" />
      Instructions
      <Icon
        :icon="isOpen ? 'mdi:chevron-up' : 'mdi:chevron-down'"
        class="w-5 h-5 ml-2"
        aria-hidden="true" />
    </button>

    <Transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="transform scale-95 opacity-0"
      enter-to-class="transform scale-100 opacity-100"
      leave-active-class="transition duration-75 ease-in"
      leave-from-class="transform scale-100 opacity-100"
      leave-to-class="transform scale-95 opacity-0">
      <div
        v-if="isOpen"
        class="absolute right-0 mt-2 w-96 bg-white dark:bg-gray-800 rounded-lg shadow-lg ring-1 ring-black ring-opacity-5 z-50">
        <div class="p-4">
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">
            Pre-reveal Instructions
            <Icon
              icon="mdi:help-circle"
              class="inline-block w-4 h-4 ml-1 text-gray-400"
              @mouseenter="tooltipShow = true"
              @mouseleave="tooltipShow = false" />
            <div
              v-if="tooltipShow"
              class="absolute z-50 px-2 py-1 text-xs text-white bg-gray-900 dark:bg-gray-700 rounded shadow-lg max-w-xs">
              These instructions will be shown to recipients before they reveal the secret content
            </div>
          </label>
          <textarea
            :value="modelValue"
            @input="updateValue"
            ref="textareaRef"
            rows="3"
            class="w-full rounded-lg border-gray-300 dark:border-gray-600 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white text-sm"
            placeholder="e.g. Use your phone to scan the QR code"
            @keydown.esc="close"></textarea>

          <div class="mt-2 flex justify-between items-center text-xs text-gray-500 dark:text-gray-400">
            <span>{{ characterCount }}/500 characters</span>
            <span>Press ESC to close</span>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, nextTick } from 'vue';
import { Icon } from '@iconify/vue';
import { useEventListener } from '@vueuse/core';


const props = withDefaults(defineProps<{
  modelValue?: string;
}>(), {
  modelValue: ''
});


const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

const isOpen = ref(false);
const tooltipShow = ref(false);
const textareaRef = ref<HTMLTextAreaElement | null>(null);

const characterCount = computed(() => props.modelValue?.length ?? 0);

const updateValue = (event: Event) => {
  const target = event.target as HTMLTextAreaElement;
  emit('update:modelValue', target.value);
};

const toggleOpen = () => {
  isOpen.value = !isOpen.value;
};

const close = () => {
  isOpen.value = false;
};

// Close on click outside
useEventListener(document, 'click', (e) => {
  const target = e.target as HTMLElement;
  if (!target.closest('.relative') && isOpen.value) {
    close();
  }
}, { capture: true });

// Focus textarea when opening
watch(isOpen, (newValue) => {
  if (newValue && textareaRef.value) {
    nextTick(() => {
      textareaRef.value?.focus();
    });
  }
});
</script>
