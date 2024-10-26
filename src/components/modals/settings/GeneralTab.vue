<template>
  <div>
    <section class="space-y-4 pb-6 border-b border-gray-200 dark:border-gray-700"
             aria-labelledby="appearance-heading">
      <h3 id="appearance-heading"
          class="text-lg font-semibold text-gray-900 dark:text-white">
        Appearance
      </h3>
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
        <button @click="$refs.themeToggle.$el.querySelector('button').click()"
                class="w-full flex items-center justify-between gap-4 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors duration-200 rounded p-2"
                :aria-label="`Switch theme`">
          <div class="flex items-center gap-2">
            <Icon icon="carbon:light-filled"
                  class="h-5 w-5 text-gray-500 dark:text-gray-400"
                  aria-hidden="true" />
            <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
              Theme
            </span>
          </div>
          <ThemeToggle ref="themeToggle"
                       @theme-changed="handleThemeChange" />
        </button>
      </div>
    </section>

    <section class="space-y-4 pb-6 border-b border-gray-200 dark:border-gray-700"
             aria-labelledby="language-heading">
      <h3 id="language-heading"
          class="text-lg font-semibold text-gray-900 dark:text-white">
        Language
      </h3>
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
        <LanguageToggle @menuToggled="handleMenuToggled"
                        class="w-full" />
      </div>
    </section>


  </div>
</template>


<script setup lang="ts">
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { Icon } from '@iconify/vue';
import { useFocusTrap } from '@vueuse/integrations/useFocusTrap';
import { onBeforeUnmount, onMounted, ref } from 'vue';



defineProps<{
  isOpen: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
}>();

const modalContentRef = ref<HTMLElement | null>(null);

const closeModal = () => {
  emit('close');
};

const handleThemeChange = (isDark: boolean) => {
  // Add any additional handling here if needed
  console.log('Theme changed:', isDark);
};


const handleMenuToggled = () => {
  // Handle language menu toggle
};

const { activate, deactivate } = useFocusTrap(modalContentRef);

// Handle ESC key
const handleKeydown = (e: KeyboardEvent) => {
  if (e.key === 'Escape') {
    closeModal();
  }
};

onMounted(() => {
  activate();
  window.addEventListener('keydown', handleKeydown);
});

onBeforeUnmount(() => {
  deactivate();
  window.removeEventListener('keydown', handleKeydown);
});
</script>
