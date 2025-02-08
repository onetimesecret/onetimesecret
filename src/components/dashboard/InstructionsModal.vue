<script setup lang="ts">

import OIcon from '@/components/icons/OIcon.vue';
import { useEventListener } from '@vueuse/core';
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const props = withDefaults(defineProps<{
  modelValue?: string;
}>(), {
  modelValue: ''
});


const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
  (e: 'save'): void;
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

// Handle ESC key press globally
const handleEscPress = (e: KeyboardEvent) => {
  if (e.key === t('escape') && isOpen.value) {
    close();
  }
};
const handleKeydown = (e: KeyboardEvent) => {
  // Close on escape
  if (e.key === t('escape')) {
    close();
    return;
  }

  // Save on Cmd+Enter (Mac) or Ctrl+Enter (Windows)
  if (e.key === t('enter') && (e.metaKey || e.ctrlKey)) {
    emit('save');
    close();
  }
};

const placeholderExample = computed(() =>
  `${t('e-g-example')} ${t('use-your-phone-to-scan-the-qr-code')}`);

onMounted(() => {
  document.addEventListener('keydown', handleEscPress);
});

onUnmounted(() => {
  document.removeEventListener('keydown', handleEscPress);
});

// Close on click outside - replace existing useEventListener
useEventListener(document, 'click', (e: MouseEvent) => {
  const target = e.target as HTMLElement;
  const modalEl = textareaRef.value?.closest('.relative');
  if (modalEl && !modalEl.contains(target) && isOpen.value) {
    close();
  }
}, { capture: true });

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


<template>
  <div class="relative">
    <button
      type="button"
      @click="toggleOpen"
      class="focus:ring-primary-500 inline-flex
                   h-11 items-center rounded-lg
                   border border-gray-200 bg-white px-4
                   py-2.5 text-sm
                   text-gray-700
                   shadow-sm transition-all duration-200
                   ease-in-out
                   hover:bg-gray-50
                   focus:outline-none focus:ring-2 focus:ring-offset-2
                   dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-800
                 dark:focus:ring-offset-gray-900"
      :aria-expanded="isOpen"
      aria-haspopup="true">
      <OIcon
        collection="mdi"
        name="text-box-edit"
        class="mr-2 size-5"
        aria-hidden="true"
      />
      {{ $t('instructions') }}
      <OIcon
        collection="mdi"
        :name="isOpen ? 'chevron-up' : 'chevron-down'"
        class="ml-2 size-5"
        aria-hidden="true"
      />
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
        class="absolute right-0 z-50
                  mt-2 w-96
                  rounded-lg bg-white
                  shadow-lg
                  ring-1
                  ring-black ring-opacity-5 dark:bg-gray-800">
        <div class="p-4">
          <label
            class="mb-2
                       block
                       text-sm font-medium text-gray-700
                       dark:text-gray-200">
            {{ $t('pre-reveal-instructions') }}
            <OIcon
              collection="mdi"
              name="help-circle"
              class="ml-1
                         inline-block size-4 text-gray-400"
              @mouseenter="tooltipShow = true"
              @mouseleave="tooltipShow = false"
            />
            <div
              v-if="tooltipShow"
              class="absolute z-50
                        max-w-xs rounded
                        bg-gray-900
                        px-2 py-1
                        text-xs text-white
                        shadow-lg
                        dark:bg-gray-700">
              {{ $t('these-instructions-will-be-shown-to-recipients-before') }}
            </div>
          </label>
          <textarea
            :value="modelValue"
            @input="updateValue"
            @keydown="handleKeydown"
            ref="textareaRef"
            rows="3"
            class="w-full
                           rounded-lg
                           border-gray-300 text-sm
                           shadow-sm
                           focus:border-brand-300 focus:ring focus:ring-brand-200
                           focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
            :placeholder="placeholderExample"
            @keydown.esc="close"></textarea>

          <div
            class="mt-2 flex items-center
                      justify-between
                      text-xs text-gray-500
                      dark:text-gray-400">
            <span>{{ $t('charactercount-500-characters', [characterCount]) }}</span>
            <span>{{ $t('press-esc-to-close') }}</span>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>
