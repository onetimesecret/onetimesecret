<!-- src/components/common/LanguageSelector.vue -->
<script setup lang="ts">
import HoverTooltip from './HoverTooltip.vue';
import OIcon from '../icons/OIcon.vue';
import { useEventListener } from '@vueuse/core';
import { ref, watch, nextTick, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLanguage } from '@/composables/useLanguage';

const { t } = useI18n();

withDefaults(defineProps<{
  modelValue?: string;
}>(), {
  modelValue: ''
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

const { supportedLocales } = useLanguage();

const isOpen = ref(false);

const listboxRef = ref<HTMLElement | null>(null);

const toggleOpen = () => {
  isOpen.value = !isOpen.value;
};

const close = () => {
  isOpen.value = false;
};

const handleLanguageSelect = (locale: string) => {
  emit('update:modelValue', locale);
  close();
};

// Handle ESC key press globally
const handleEscPress = (e: KeyboardEvent) => {
  if (e.key === 'Escape' && isOpen.value) {
    close();
  }
};

onMounted(() => {
  document.addEventListener('keydown', handleEscPress);
});

onUnmounted(() => {
  document.removeEventListener('keydown', handleEscPress);
});

// Close on click outside
useEventListener(document, 'click', (e: MouseEvent) => {
  const target = e.target as HTMLElement;
  const modalEl = listboxRef.value?.closest('.relative');
  if (modalEl && !modalEl.contains(target) && isOpen.value) {
    close();
  }
}, { capture: true });

// Focus listbox when opening
watch(isOpen, (newValue) => {
  if (newValue && listboxRef.value) {
    nextTick(() => {
      listboxRef.value?.focus();
    });
  }
});
</script>

<template>
  <div class="relative group">
    <HoverTooltip>{{ t('language') }}</HoverTooltip>
    <button
      type="button"
      @click="toggleOpen"
      class="group relative inline-flex h-11 items-center gap-2
             rounded-lg bg-white px-4
             ring-1 ring-gray-200 shadow-sm
             hover:bg-gray-50
             focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
             dark:bg-gray-800 dark:ring-gray-700 dark:hover:bg-gray-700
             dark:focus:ring-brand-400 dark:focus:ring-offset-0
             transition-all duration-200"
      :aria-expanded="isOpen"
      :aria-label="t('language')"
      aria-haspopup="listbox">
      <OIcon
        collection="heroicons"
        name="language"
        class="size-5"
        aria-hidden="true"
      />
      <OIcon
        collection="mdi"
        :name="isOpen ? 'chevron-up' : 'chevron-down'"
        class="size-5"
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
        ref="listboxRef"
        role="listbox"
        :aria-activedescendant="modelValue"
        tabindex="0"
        class="absolute right-0 z-50
               mt-2 w-48
               rounded-lg bg-white
               shadow-lg
               ring-1 ring-black ring-opacity-5
               dark:bg-gray-800">
        <div class="py-1">
        <button
          type="button"
            v-for="locale in supportedLocales"
            :key="locale"
            role="option"
            :aria-selected="modelValue === locale"
            :class="[
              'w-full px-4 py-2 text-left text-sm',
              'hover:bg-gray-100 dark:hover:bg-gray-700',
              modelValue === locale ? 'bg-gray-50 dark:bg-gray-700' : ''
            ]"
            @click="handleLanguageSelect(locale)">
            {{ locale }}
          </button>
        </div>
      </div>
    </Transition>
  </div>
</template>
