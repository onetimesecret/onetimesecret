<script setup lang="ts">
import { paymentFrequencies, productTiers, type ProductTier } from '@/sources/productTiers';
import type { Testimonial } from '@/sources/testimonials';
import { testimonials } from '@/sources/testimonials';
import { onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const selectedTier = ref<ProductTier>(productTiers[0])
const selectedFrequency = ref(paymentFrequencies[0].value)

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

// Reactive state
const randomTestimonial = ref<Testimonial | null>(null);

// Methods
const closeModal = () => {
  emit('close');
};

const getRandomTestimonial = () => {
  const randomIndex = Math.floor(Math.random() * testimonials.length);
  randomTestimonial.value = testimonials[randomIndex];
};

// Handle ESC key press
const handleEscKey = (event: KeyboardEvent) => {
  if (event.key === t('escape') && props.isOpen) {
    closeModal();
  }
};

// Watch for changes in isOpen prop
watch(() => props.isOpen, (newValue) => {
  if (newValue) {
    getRandomTestimonial();
  }
});

// Add event listener for ESC key
onMounted(() => {
  document.addEventListener('keydown', handleEscKey);
});

// Remove event listener when component is unmounted
onUnmounted(() => {
  document.removeEventListener('keydown', handleEscKey);
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 overflow-y-auto"
    aria-labelledby="modal-title"
    role="dialog"
    aria-modal="true">
    <div class="flex min-h-screen items-end justify-center px-4 pb-20 pt-4 text-center sm:block sm:p-0">
      <div
        class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity dark:bg-gray-900 dark:bg-opacity-75"
        aria-hidden="true"></div>

      <span
        class="hidden sm:inline-block sm:h-screen sm:align-middle"
        aria-hidden="true">&#8203;</span>

      <div class="inline-block overflow-hidden rounded-lg bg-white text-left align-bottom shadow-xl transition-all dark:bg-gray-800 sm:my-8 sm:w-full sm:max-w-lg sm:align-middle">
        <div class="bg-white px-4 pb-4 pt-5 dark:bg-gray-800 sm:p-6 sm:pb-4">
          <div class="sm:flex sm:items-start">
            <div class="mx-auto flex size-12 shrink-0 items-center justify-center rounded-full bg-blue-100 sm:mx-0 sm:size-10">
              <svg
                class="size-6 text-blue-600"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                aria-hidden="true">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 10V3L4 14h7v7l9-11h-7z"
                />
              </svg>
            </div>
            <div class="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left">
              <h3
                class="text-lg font-medium leading-6 text-gray-900 dark:text-white"
                id="modal-title">
                {{ $t('upgrade-to') }} {{ selectedTier.name }}
              </h3>
              <div class="mt-2">
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  {{ selectedTier.description }}
                </p>
              </div>
            </div>
          </div>

          <div class="mt-6">
            <div class="mb-4 flex justify-center">
              <span class="relative z-0 inline-flex rounded-md shadow-sm">
                <button
                  v-for="frequency in paymentFrequencies"
                  :key="frequency.value"
                  @click="selectedFrequency = frequency.value"
                  :class="[
                    selectedFrequency === frequency.value ? 'bg-blue-600 text-white' : 'bg-white text-gray-700 dark:bg-gray-700 dark:text-white',
                    'relative inline-flex items-center border border-gray-300 px-4 py-2 text-sm font-medium focus:z-10 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500 dark:border-gray-600'
                  ]">
                  {{ frequency.label }}
                </button>
              </span>
            </div>

            <p class="text-center text-3xl font-bold text-gray-900 dark:text-white">
              {{ selectedTier.price[selectedFrequency] }}
              <span class="text-lg font-normal text-gray-500 dark:text-gray-400">
                {{ paymentFrequencies.find(f => f.value === selectedFrequency)?.priceSuffix }}
              </span>
            </p>

            <ul class="mt-6 space-y-4">
              <li
                v-for="feature in selectedTier.features"
                :key="feature"
                class="flex items-start">
                <div class="shrink-0">
                  <svg
                    class="size-5 text-green-500"
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    aria-hidden="true">
                    <path
                      fill-rule="evenodd"
                      d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </div>
                <p class="ml-3 text-sm text-gray-700 dark:text-gray-300">
                  {{ feature }}
                </p>
              </li>
            </ul>
          </div>
        </div>
        <div class="bg-gray-50 px-4 py-3 dark:bg-gray-700 sm:flex sm:flex-row-reverse sm:px-6">
          <button
            type="button"
            class="inline-flex w-full justify-center rounded-md border border-transparent bg-blue-600 px-4 py-2 text-base font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 sm:ml-3 sm:w-auto sm:text-sm">
            {{ selectedTier.cta }}
          </button>
          <button
            type="button"
            class="mt-3 inline-flex w-full justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-base font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:hover:bg-gray-700 sm:ml-3 sm:mt-0 sm:w-auto sm:text-sm">
            {{ $t('web.COMMON.word_cancel') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>


<style scoped>
.confetti-container {
  position: absolute;
  width: 100%;
  height: 100%;
  overflow: hidden;
  opacity: 0;
  transition: opacity 0.3s ease;
}

.confetti-container::before,
.confetti-container::after {
  content: '';
  position: absolute;
  width: 10px;
  height: 10px;
  background: #ff0;
  animation: confetti 5s ease-in-out infinite;
}

.confetti-container::after {
  background: #f0f;
  animation-delay: 2.5s;
}

@keyframes confetti {
  0% {
    transform: translateY(-100%) rotate(0deg);
  }
  100% {
    transform: translateY(100vh) rotate(720deg);
  }
}

div:hover .confetti-container {
  opacity: 1;
}
</style>
