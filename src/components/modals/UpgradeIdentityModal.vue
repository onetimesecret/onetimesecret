<script setup lang="ts">
import { productTiers, paymentFrequencies } from '@/sources/productTiers'
import type { Testimonial } from '@/sources/testimonials';
import { testimonials } from '@/sources/testimonials';
import { onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

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

const frequency = ref('monthly')

const toggleFrequency = (newFrequency: string) => {
  frequency.value = newFrequency
}

// Methods
const closeModal = () => {
  emit('close');
};

const upgradeNow = () => {
  emit('upgrade');
};

const handleModalClick = (event: MouseEvent) => {
  event.stopPropagation();
};

const handleModalInteraction = (event: TouchEvent) => {
  event.stopPropagation();
};

const getRandomTestimonial = () => {
  const randomIndex = Math.floor(Math.random() * testimonials.length);
  randomTestimonial.value = testimonials[randomIndex];
};

const getPriceSuffix = (frequency: string) => {
  const selectedFrequency = paymentFrequencies.find(f => f.value === frequency);
  return selectedFrequency ? selectedFrequency.priceSuffix : '';
}

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
  <teleport to="body">
    <div
      v-if="isOpen"
      @click="closeModal"
      @touchend="closeModal"
      class="fixed inset-0 z-50 overflow-y-auto bg-gray-900/50 dark:bg-gray-900/80"
      aria-labelledby="modal-title"
      role="dialog"
      aria-modal="true">
      <div class="flex min-h-screen items-center justify-center p-4 text-center sm:p-0">
        <div
          @click.stop="handleModalClick"
          @touchend.stop="handleModalInteraction"
          class="w-full max-w-lg overflow-hidden rounded-2xl bg-white p-6 text-left align-middle shadow-xl transition-all dark:bg-gray-800">
          <!-- Header -->
          <div class="flex items-start space-x-4">
            <div
              class="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900">
              <svg
                class="size-6 text-brand-600 dark:text-brand-300"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                xmlns="http://www.w3.org/2000/svg">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 13l4 4L19 7"
                />
              </svg>
            </div>
            <div>
              <h3
                class="text-xl font-semibold leading-6 text-gray-900 dark:text-white"
                id="modal-title">
                {{ $t('upgrade-to-identity-plus') }}
              </h3>
              <p class="mt-2 text-sm text-gray-500 dark:text-gray-300">
                {{ productTiers[0].description }}
              </p>
            </div>
          </div>

          <!-- Pricing Toggle -->
          <div class="mt-6 flex justify-center">
            <div class="relative flex items-center rounded-full bg-gray-100 p-1 dark:bg-gray-700">
              <button
                @click="toggleFrequency('monthly')"
                :class="{ 'bg-white shadow-sm dark:bg-gray-600': frequency === 'monthly' }"
                class="relative rounded-full px-3 py-1 text-sm font-medium transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
                {{ $t('monthly') }}
              </button>
              <button
                @click="toggleFrequency('annually')"
                :class="{ 'bg-white shadow-sm dark:bg-gray-600': frequency === 'annually' }"
                class="relative rounded-full px-3 py-1 text-sm font-medium transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
                {{ $t('yearly') }}
              </button>
            </div>
          </div>

          <!-- Pricing -->
          <div class="mt-4 pb-5 text-center">
            <p class="font-brand text-4xl font-bold text-gray-900 dark:text-white">
              {{ productTiers[0].price[frequency] }}
              <span class="text-lg font-normal text-gray-500 dark:text-gray-400">
                {{ getPriceSuffix(frequency) }}
              </span>
            </p>
          </div>

          <!-- Benefits -->
          <div class="mt-6">
            <h4 class="text-lg font-semibold text-gray-700 dark:text-gray-200">
              {{ $t('benefits-of') }}:
              {{ $t('identity-plus') }}
            </h4>
            <ul class="mt-3 space-y-2 text-sm text-gray-600 dark:text-gray-300">
              <li
                v-for="feature in productTiers[0].features"
                :key="feature"
                class="flex items-center space-x-2">
                <svg
                  class="size-5 text-brand-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  xmlns="http://www.w3.org/2000/svg">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span>{{ feature }}</span>
              </li>
            </ul>
          </div>

          <!-- Testimonial -->
          <div
            v-if="randomTestimonial"
            class="mt-6 rounded-lg bg-gray-50 p-4 dark:bg-gray-700">
            <h5 class="mb-2 text-sm font-bold text-gray-700 dark:text-gray-200">
              {{ $t('ai-generated-testimonial') }}:
            </h5>
            <blockquote class="text-sm italic text-gray-600 dark:text-gray-300">
              "{{ randomTestimonial.quote }}"
            </blockquote>
            <div class="mt-2 flex items-center justify-between">
              <p class="text-xs text-gray-500 dark:text-gray-400">
                - {{ randomTestimonial.name }}, {{ randomTestimonial.company }}
              </p>
              <div class="flex items-center">
                <span class="mr-1 text-yellow-400">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="size-4"
                    viewBox="0 0 20 20"
                    fill="currentColor">
                    <path
                      d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z"
                    />
                  </svg>
                </span>
                <span
                  class="text-xs font-medium text-gray-600 dark:text-gray-300">{{ randomTestimonial.stars }}/5</span>
              </div>
            </div>
          </div>

          <!-- CTA -->
          <div class="mt-8 flex flex-col sm:flex-row sm:justify-end sm:space-x-4">
            <button
              @click="closeModal"
              class="mb-3 inline-flex items-center justify-center rounded-md border border-gray-300 bg-white
                    px-4 py-2 text-base font-medium text-gray-700 shadow-sm hover:bg-gray-50
                    focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-600
                    dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600 sm:mb-0 sm:w-auto"
              type="button">
              {{ $t('maybe-later') }}
            </button>

            <a
              :href="`${productTiers[0].href}${getPriceSuffix(frequency)}`"
              @click.stop="upgradeNow"
              class="inline-flex items-center justify-center rounded-md border border-transparent bg-brand-600
               px-4 py-2 font-brand text-lg font-bold text-white shadow-sm
               hover:bg-brand-700
               focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-brand-500
               dark:hover:bg-brand-600 sm:w-auto"
              type="button"
              :aria-label="$t('upgrade-account')">
              {{ productTiers[0].cta }}
            </a>
          </div>


          <!-- Disclaimer -->
          <p class="mt-4 text-xs text-gray-500 dark:text-gray-400">
            {{ $t('note') }}: {{ $t('ai-generated-content-disclaimer') }}
          </p>
        </div>
      </div>
    </div>
  </teleport>
</template>
