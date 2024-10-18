<template>
  <teleport to="body">
    <div v-if="isOpen"
         @click="closeModal"
         class="fixed inset-0 z-50 overflow-y-auto bg-black/50 backdrop-blur-sm flex items-center justify-center"
         aria-labelledby="settings-modal"
         role="dialog"
         aria-modal="true">
      <div @click.stop
           class="relative w-full max-w-lg mx-auto bg-white dark:bg-gray-800 rounded-xl shadow-2xl overflow-hidden transition-all duration-300 ease-out transform"
           :class="{ 'scale-95 opacity-0': !isOpen, 'scale-100 opacity-100': isOpen }">
        <!-- Header -->
        <div class="flex justify-between items-center p-6 border-b border-gray-200 dark:border-gray-700">
          <h2 id="settings-modal"
              class="text-2xl font-bold text-gray-900 dark:text-white">
            Settings
          </h2>
          <button @click="closeModal"
                  class="text-gray-400 hover:text-gray-500 dark:text-gray-300 dark:hover:text-gray-200 transition-colors duration-200"
                  aria-label="Close settings">
            <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Content -->
        <div class="p-6 space-y-8">
          <div class="space-y-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Appearance</h3>
            <ThemeToggle />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Language</h3>
            <LanguageToggle @menuToggled="handleMenuToggled" />
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Jurisdiction</h3>
            {{ currentJurisdiction.display_name }}
          </div>

          <div class="space-y-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Notifications</h3>
            <div class="flex items-center justify-between">
              <span class="text-gray-700 dark:text-gray-300">Email notifications</span>
              <label class="relative inline-flex items-center cursor-pointer">
                <input type="checkbox" value="" class="sr-only peer">
                <div class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-brand-300 dark:peer-focus:ring-brand-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-brand-600"></div>
              </label>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="px-6 py-4 bg-gray-50 dark:bg-gray-700 flex justify-end">
          <button @click="closeModal"
                  class="inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-colors duration-200">
            Done
          </button>
        </div>
      </div>
    </div>
  </teleport>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue';

import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';

// Props
defineProps<{
  isOpen: boolean;
}>();

// Emits
const emit = defineEmits<{
  (e: 'close'): void;
}>();

const isLanguageMenuOpen = ref(false);
const jurisdictionStore = useJurisdictionStore();

//const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);
const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);

const handleMenuToggled = (isOpen: boolean) => {
  isLanguageMenuOpen.value = isOpen;
};

// Methods
const closeModal = () => {
  emit('close');
};
</script>
