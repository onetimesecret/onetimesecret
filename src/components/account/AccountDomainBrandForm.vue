<template>
  <form @submit.prevent="submitForm">
    <input type="hidden"
           name="shrimp"
           :value="csrfStore.shrimp" />

    <!-- Add hidden input for primary_color since it's managed in parent -->
    <input type="hidden"
           name="brand[primary_color]"
           :value="brandSettings.primary_color" />


    <!-- Color Picker -->
    <div class="space-y-2">
      <label id="color-picker-label"
             class="block text-sm font-medium sr-only">Brand Color</label>
      <div class="flex items-center space-x-4">
        <div class="relative">
          <input type="color"
                 v-model="formData.primary_color"
                 name="brand[primary_color]"
                 class="w-12 h-12 rounded-lg cursor-pointer border-2 border-gray-200 dark:border-gray-600"
                 aria-labelledby="color-picker-label"
                 aria-describedby="color-picker-help">
          <div class="absolute -right-2 -top-2 w-4 h-4 rounded-full"
               :style="{ backgroundColor: formData.primary_color }"
               aria-hidden="true"></div>
        </div>
        <input type="text"
               v-model="formData.primary_color"
               name="brand[primary_color]"
               class="flex-1 max-w-xs px-4 py-2 rounded-lg border border-gray-200 dark:border-gray-600 dark:bg-gray-700 text-sm"
               aria-label="Brand color hex value">
      </div>
      <p id="color-picker-help"
         class="text-sm text-gray-600 dark:text-gray-400">
        Choose a brand color that provides good contrast for text and buttons
      </p>

    </div>
    <!-- Instructions with Tooltip -->
    <div class="space-y-2">
      <div class="flex items-center relative group">
        <label for="instructions_pre_reveal"
               class="block text-sm font-medium text-gray-700 dark:text-gray-200">
          Instructions
        </label>
        <button type="button"
                @mouseenter="showTooltip = true"
                @mouseleave="showTooltip = false"
                @focus="showTooltip = true"
                @blur="showTooltip = false"
                class="ml-1 p-1 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500"
                aria-describedby="instructions-tooltip">
          <Icon icon="mdi:information-outline"
                class="w-5 h-5"
                aria-hidden="true" />
        </button>

        <!-- Tooltip -->
        <div v-if="showTooltip"
             id="instructions-tooltip"
             role="tooltip"
             class="absolute z-50 transform -translate-y-full top-0 left-0 mt-[-8px] w-72 px-3 py-2 bg-gray-900 dark:bg-gray-700 text-white text-sm rounded shadow-lg">
          <div class="relative">
            These instructions will be shown to recipients before they reveal the secret content. Consider including any
            specific steps or context they should know.
            <!-- Arrow -->
            <div class="absolute bottom-[-16px] left-5 transform">
              <div class="w-4 h-4 rotate-45 bg-gray-900 dark:bg-gray-700"></div>
            </div>
          </div>
        </div>
      </div>

      <textarea id="instructions_pre_reveal"
                v-model="formData.instructions_pre_reveal"
                name="brand[instructions_pre_reveal]"
                rows="3"
                class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                placeholder="e.g. Use your phone to scan the QR code"></textarea>
    </div>

    <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
      <!-- Font Family -->
      <CycleButton v-model="formData.font_family"
                   :options="fontOptions"
                   label="Font Family"
                   :display-map="fontDisplayMap" />

      <!-- Button Style -->
      <CycleButton v-model="formData.button_style"
                   :options="buttonStyleOptions"
                   label="Button Style"
                   :display-map="buttonStyleDisplayMap" />
    </div>

    <!-- Submit Button -->
    <div class="pt-6">
      <button type="submit"
              :disabled="isSubmitting"
              class="w-full inline-flex justify-center py-3 px-4 border border-transparent shadow-sm text-sm font-medium rounded-lg text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-600 transition-colors duration-200 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed">
        <span v-if="isSubmitting"
              class="mr-2">
          <svg class="animate-spin h-5 w-5 text-white"
               xmlns="http://www.w3.org/2000/svg"
               fill="none"
               viewBox="0 0 24 24">
            <circle class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"></circle>
            <path class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z">
            </path>
          </svg>
        </span>
        {{ isSubmitting ? 'Saving...' : 'Save Settings' }}
      </button>
    </div>
    <StatusBar :success="success"
               :error="error"
               :loading="isSubmitting"
               :auto-dismiss="true" />
  </form>
</template>

<!-- AccountDomainBrandForm.vue -->
<script setup lang="ts">
import CycleButton from '@/components/common/CycleButton.vue';
import StatusBar from '@/components/StatusBar.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import { BrandSettings } from '@/types/onetime';
import { computed, watch, ref } from 'vue';
import { useRoute } from 'vue-router';
import { Icon } from '@iconify/vue';

const route = useRoute();
const domainId = route.params.domain as string;
const csrfStore = useCsrfStore();


const props = defineProps<{
  brandSettings: BrandSettings;
  isLoading: boolean;
}>();

const emit = defineEmits<{
  (e: 'update:brandSettings', value: BrandSettings): void;
}>();

// Add this with other refs/variables
const showTooltip = ref(false);

const fontOptions = ['sans-serif', 'serif', 'monospace'];
const fontDisplayMap = {
  'sans-serif': 'Sans Serif',
  'serif': 'Serif',
  'monospace': 'Monospace'
};

const buttonStyleOptions = ['rounded', 'pill', 'square'];
const buttonStyleDisplayMap = {
  'rounded': 'Rounded',
  'pill': 'Pill Shape',
  'square': 'Square'
};


// Use computed instead of watch + ref
const formData = computed({
  get: () => props.brandSettings,
  set: (newValue) => emit('update:brandSettings', newValue)
});

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: `/api/v2/account/domains/${domainId}/brand`,
  successMessage: 'Brand settings saved successfully',
  onSuccess: (response) => {
    if (response.data?.record?.brand) {
      emit('update:brandSettings', response.data.record.brand);
    } else {
      // Fallback to local data if response structure is unexpected
      emit('update:brandSettings', formData.value);
    }
  },
  onError: (err) => {
    console.error('Error saving brand settings:', err);
  },
});

watch(() => props.isLoading, (newVal: boolean, oldVal: boolean) => {
  if (!newVal && oldVal) {
    // Focus back on the form when loading completes
    document.querySelector('form')?.focus()
  }
})
</script>


<style>
/* Optional: Add transition for smooth tooltip appearance */
[role="tooltip"] {
  transition: opacity 150ms ease-in-out;
}
</style>
