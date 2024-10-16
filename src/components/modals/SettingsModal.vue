<template>
  <teleport to="body">
    <div v-if="isOpen"
         @click="closeModal"
         class="fixed inset-0 z-50 overflow-y-auto bg-gray-500/75 dark:bg-gray-900/80 flex items-center justify-center"
         aria-labelledby="settings-modal"
         role="dialog"
         aria-modal="true">
      <div class="relative w-full max-w-md mx-auto">
        <div @click.stop
             class="bg-white dark:bg-gray-800 rounded-lg shadow-xl overflow-hidden">
          <!-- Header -->
          <div class="flex justify-between items-center p-4 border-b border-gray-200 dark:border-gray-700">
            <h2 id="settings-modal"
                class="text-xl font-semibold text-gray-900 dark:text-white">
              Settings
            </h2>
            <button @click="closeModal"
                    class="text-gray-400 hover:text-gray-500 dark:text-gray-300 dark:hover:text-gray-200">
              <span class="sr-only">Close</span>
              <svg class="h-6 w-6"
                   fill="none"
                   viewBox="0 0 24 24"
                   stroke="currentColor">
                <path stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Content -->
          <div class="p-6 space-y-6">
            <ThemeToggle />
            <LanguageToggle @menuToggled="handleMenuToggled" />
            <JurisdictionToggle />
          </div>

          <!-- Footer -->
          <div class="px-4 py-3 bg-gray-50 dark:bg-gray-700 text-right sm:px-6">
            <button @click="closeModal"
                    class="inline-flex justify-center py-2 px-4
                    border border-transparent shadow-sm text-sm font-medium rounded-md
                    text-white bg-slate-600 dark:bg-slate-500 dark:hover:bg-slate-600 hover:bg-brand-700
                    focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500">
              Done
            </button>
          </div>
        </div>
      </div>
    </div>
  </teleport>
</template>

<script setup lang="ts">
import { ref } from 'vue';

import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import JurisdictionToggle from '@/components/JurisdictionToggle.vue';
// Props
defineProps<{
  isOpen: boolean;
}>();

// Emits
const emit = defineEmits<{
  (e: 'close'): void;
}>();

const isLanguageMenuOpen = ref(false);

const handleMenuToggled = (isOpen: boolean) => {
  isLanguageMenuOpen.value = isOpen;
};
// Methods
const closeModal = () => {
  emit('close');
};


</script>
