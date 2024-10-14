<template>
  <teleport to="body">
    <div v-if="isOpen"
         @click="closeModal"
         @touchend="closeModal"
         class="fixed inset-0 z-50 overflow-y-auto bg-gray-900 bg-opacity-50 dark:bg-opacity-80"
         aria-labelledby="modal-title"
         role="dialog"
         aria-modal="true">
      <div class="flex items-end justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">
        <!-- Modal panel -->
        <div
             class="inline-block w-full max-w-md p-6 my-56 overflow-hidden text-left align-middle transition-all transform bg-white shadow-xl rounded-2xl dark:bg-gray-800 sm:max-w-lg">
          <div class="sm:flex sm:items-start">
            <div
                 class="flex items-center justify-center flex-shrink-0 w-12 h-12 mx-auto
                 bg-brandcomp-100 rounded-full sm:mx-0 sm:h-10 sm:w-10 dark:bg-brandcomp-900">
              <svg class="w-6 h-6 text-brandcomp-600 dark:text-brandcomp-300"
                   fill="none"
                   stroke="currentColor"
                   viewBox="0 0 24 24"
                   xmlns="http://www.w3.org/2000/svg">
                <path stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"></path>
              </svg>
            </div>
            <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
              <h3 class="text-lg font-medium leading-6 text-gray-900 dark:text-white"
                  id="modal-title">
                Upgrade to Custom Domains
              </h3>
              <div class="mt-2">
                <p class="text-sm text-gray-500 dark:text-gray-300">
                  Boost your brand identity and build trust with your users by using your own custom domain.
                </p>
              </div>
            </div>
          </div>

          <!-- Additional content to make the modal taller -->
          <div class="mt-6 space-y-4">
            <h4 class="text-md font-semibold text-gray-700 dark:text-gray-200">Benefits of Custom Domains:</h4>
            <ul class="list-disc list-inside text-sm text-gray-600 dark:text-gray-300 space-y-2">
              <li>Improved brand recognition</li>
              <li>Enhanced SEO performance</li>
              <li>Increased user trust and credibility</li>
              <li>Full control over your online presence</li>
            </ul>
            <p class="text-sm text-gray-500 dark:text-gray-400 italic">
              "Using a custom domain increased our conversion rates by 25%!" - Happy Customer
            </p>
          </div>

          <!-- CTA -->
          <div class="mt-6 sm:mt-4 sm:flex sm:flex-row-reverse">
            <router-link :to="to"
                         @click="upgradeNow"
                         type="button"
                         class="w-full px-4 py-2 text-base font-medium text-white bg-brandcomp-600 border border-transparent rounded-md shadow-sm hover:bg-brandcomp-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 sm:w-auto sm:text-sm dark:bg-brandcomp-500 dark:hover:bg-brandcomp-600"
                         aria-label="Upgrade account">
              Upgrade Now
            </router-link>
            <div class="mt-3 sm:mt-0 sm:mr-3">
              <button @click="closeModal"
                      type="button"
                      class="w-full px-4 py-2 text-base font-medium text-gray-700 bg-white border border-gray-300 rounded-md shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 sm:w-auto sm:text-sm dark:bg-gray-700 dark:text-white dark:hover:bg-gray-600 dark:border-gray-600"
                      aria-label="Close modal">
                Maybe Later
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </teleport>
</template>

<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue';

// Props
const props = defineProps<{
  isOpen: boolean;
  to: string;
}>();

// Emits
const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'upgrade'): void;
}>();

// Methods
const closeModal = () => {
  emit('close');
};

const upgradeNow = () => {
  emit('upgrade');
  closeModal();
};

// Handle ESC key press
const handleEscKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape' && props.isOpen) {
    closeModal();
  }
};

// Add event listener for ESC key
onMounted(() => {
  document.addEventListener('keydown', handleEscKey);
});

// Remove event listener when component is unmounted
onUnmounted(() => {
  document.removeEventListener('keydown', handleEscKey);
});
</script>
