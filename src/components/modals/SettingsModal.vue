<template>
  <div v-show="isOpen"
       class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 backdrop-blur-sm transition-opacity duration-300"
       :class="{ 'opacity-0': !isOpen }"
       aria-labelledby="settings-modal"
       role="dialog"
       aria-modal="true">
    <div ref="modalContentRef"
         class="relative mx-auto w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-2xl dark:bg-gray-800 transition-all duration-300 ease-out transform"
         :class="{ 'opacity-0 scale-95': !isOpen, 'opacity-100 scale-100': isOpen }">

      <div class="flex h-[90vh] sm:h-[80vh] flex-col">
        <!-- Modal Header -->
        <div class="flex-shrink-0 flex items-center justify-between bg-gray-50 p-4 dark:bg-gray-700">
          <h2 id="settings-modal"
              class="text-2xl font-bold text-gray-900 dark:text-white">
            Settings
          </h2>
          <button @click="closeModal"
                  class="rounded-md p-2 text-gray-500 hover:bg-gray-200 dark:text-gray-300 dark:hover:bg-gray-600 transition-colors duration-200"
                  aria-label="Close settings">
            <svg class="h-5 w-5"
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

        <!-- Tabs -->
        <div class="flex-shrink-0 flex overflow-x-auto px-6 py-2 gap-2">
          <button v-for="tab in tabs"
                  :key="tab"
                  @click="activeTab = tab"
                  class="min-w-[80px] px-3 py-1.5 text-base font-medium transition-colors duration-200 whitespace-nowrap rounded-md"
                  :class="[
                    activeTab === tab
                      ? 'bg-brand-50 text-brand-600 dark:bg-brand-900/20 dark:text-brand-400'
                      : 'text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700'
                  ]">
            {{ tab }}
          </button>
        </div>

        <!-- Content -->
        <div class="flex-grow overflow-y-auto p-4 sm:p-6">
          <Suspense>
            <template #default>
              <!-- General Tab -->
              <div v-if="activeTab === 'General'"
                   class="space-y-8">
                <GeneralTab @close="closeModal" />

              </div>
              <div v-else-if="activeTab === 'Data Region'"
                   class="space-y-8">
                <JurisdictionTab />
              </div>
            </template>
            <template #fallback>
              <div class="flex items-center justify-center h-full">
                <div class="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-brand-600"></div>
              </div>
            </template>
          </Suspense>
        </div>

        <!-- Footer -->
        <div class="flex-shrink-0 flex justify-end bg-gray-50 p-4 dark:bg-gray-700">
          <button @click="closeModal"
                  class="rounded-md bg-brand-600 px-4 py-2 text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 transition-colors duration-200">
            Done
          </button>
        </div>
      </div>
    </div>
  </div>
</template>



<script setup lang="ts">
import { useFocusTrap } from '@vueuse/integrations/useFocusTrap';
import { onBeforeUnmount, onMounted, ref } from 'vue';
import JurisdictionTab from './settings/JurisdictionTab.vue';
import GeneralTab from './settings/GeneralTab.vue';


defineProps<{
  isOpen: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
}>();

const modalContentRef = ref<HTMLElement | null>(null);
const tabs = ['General', 'Data Region']; // , 'Notifications', 'Security'
const activeTab = ref('General');

const closeModal = () => {
  emit('close');
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
