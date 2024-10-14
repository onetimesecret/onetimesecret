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
        <div @click="handleModalClick"
             @touchend="handleModalInteraction"
             class="inline-block w-full max-w-md p-6 my-56 overflow-hidden text-left align-middle transition-all transform
                    bg-white shadow-xl rounded-2xl dark:bg-gray-800 sm:max-w-lg">
          <div class="sm:flex sm:items-start">
            <div class="flex items-center justify-center flex-shrink-0 w-12 h-12 mx-auto
                 bg-brand-100 rounded-full sm:mx-0 sm:h-10 sm:w-10 dark:bg-brand-900">
              <svg class="w-6 h-6 text-brand-600 dark:text-brand-300"
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
            <h4 class="text-md font-semibold text-gray-700 dark:text-gray-200">Benefits of Identity Plus:</h4>
            <ul class="list-disc list-inside text-sm text-gray-600 dark:text-gray-300 space-y-2">
              <li>Secure your brand with custom domains</li>
              <li>Build customer trust with links from your domain</li>
              <li>Privacy-first design</li>
              <li>Full API access</li>
              <li>Meets and exceeds compliance standards</li>
            </ul>
            <div v-if="randomTestimonial" class="bg-gray-100 dark:bg-gray-800 rounded-lg p-4">
              <h5 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">AI-Generated Testimonial:</h5>
              <blockquote class="text-sm italic text-gray-600 dark:text-gray-400">
                "{{ randomTestimonial.quote }}"
              </blockquote>
              <div class="mt-2 flex justify-between items-center">
                <p class="text-xs text-gray-500 dark:text-gray-400">
                  - {{ randomTestimonial.name }}, {{ randomTestimonial.company }}
                </p>
                <div class="flex items-center">
                  <span class="text-yellow-400 mr-1">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                    </svg>
                  </span>
                  <span class="text-xs font-medium text-gray-600 dark:text-gray-400">{{ randomTestimonial.stars }}/5</span>
                </div>
              </div>
            </div>
          </div>

          <!-- CTA -->
          <div class="mt-6 sm:mt-4 sm:flex sm:flex-row-reverse">
            <a :href="to"
                         @click.stop="upgradeNow"
                         type="button"
                         class="w-full px-4 py-2 text-base font-brand font-medium
           text-white bg-brand-600 border border-transparent rounded-md shadow-sm hover:bg-brand-700
           focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 sm:w-auto sm:text-sm
           dark:bg-brand-500 dark:hover:bg-brand-600"
                         aria-label="Upgrade account">
              Upgrade Now
          </a>
            <div class="mt-3 sm:mt-0 sm:mr-3">
              <a href="#"
                 @click.stop.prevent="closeModal"
                 class="inline-block w-full px-4 py-2 text-base font-medium
             text-gray-700 hover:text-gray-900 sm:w-auto sm:text-sm
             dark:text-gray-300 dark:hover:text-white
             hover:underline underline-offset-2"
                 aria-label="Close modal">
                Maybe Later
              </a>
            </div>
          </div>

          <!--
          <div>
            <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
              Note: This quote was generated by AI based on our product features. It does not represent an actual person or company.
            </p>
          </div>
          -->
        </div>
      </div>
    </div>
  </teleport>
</template>

<script setup lang="ts">
import type { Testimonial } from '@/sources/testimonials';
import { testimonials } from '@/sources/testimonials';
import { onMounted, onUnmounted, ref, watch } from 'vue';

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

// Handle ESC key press
const handleEscKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape' && props.isOpen) {
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
