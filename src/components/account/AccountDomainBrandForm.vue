<template>
  <form @submit.prevent="submitForm">
    <input type="hidden"
           name="shrimp"
           :value="csrfStore.shrimp" />

    <input type="hidden"
           name="brand[primary_color]"
           :value="brandSettings.primary_color" />

    <input type="hidden"
           name="brand[button_text_light]"
           :value="brandSettings.button_text_light" />

    <div class="space-y-6">
      <!-- Color Picker and CycleButtons Row -->
  <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 md:gap-6 items-start">
    <!-- Color Picker -->
    <div class="relative">
      <label id="color-picker-label"
             class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1 sr-only">
        Brand Color
      </label>
      <div class="group flex items-center bg-white dark:bg-gray-800 border border-gray-200
                  dark:border-gray-600 rounded-lg shadow-sm px-4 py-2.5
                  hover:border-gray-300 dark:hover:border-gray-500
                  focus-within:ring-2 focus-within:ring-primary-500 focus-within:border-primary-500
                  transition duration-150 ease-in-out">
        <div class="relative">
          <input type="color"
                 v-model="formData.primary_color"
                 name="brand[primary_color]"
                 class="w-8 h-8 rounded cursor-pointer border border-gray-200
                        dark:border-gray-600 focus:outline-none"
                 aria-labelledby="color-picker-label">
          <div class="absolute -right-1 -top-1 w-3 h-3 rounded-full
                      shadow-sm ring-2 ring-white dark:ring-gray-800"
               :style="{ backgroundColor: formData.primary_color }"
               aria-hidden="true"></div>
        </div>
        <input type="text"
               v-model="formData.primary_color"
               name="brand[primary_color]"
               class="ml-3 w-24 bg-transparent border-none focus:ring-0 p-0
                      text-base font-medium text-gray-900 dark:text-gray-100
                      placeholder-gray-400 uppercase"
               pattern="^#[0-9A-Fa-f]{6}$"
               placeholder="#000000"
               maxlength="7"
               aria-label="Brand color hex value">
      </div>

    </div>

    <!-- Font Family -->
    <div class="relative">
      <CycleButton v-model="formData.font_family"
                   :options="fontOptions"
                   label="Font Family"
                   :display-map="fontDisplayMap"
                   class="w-full" />
    </div>

    <!-- Button Style -->
    <div class="relative">
      <CycleButton v-model="formData.button_style"
                   :options="buttonStyleOptions"
                   label="Button Style"
                   :display-map="buttonStyleDisplayMap"
                   class="w-full" />
    </div>
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

      <!-- Submit Button -->
      <div>
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

    </div>
  </form>
</template>


<!-- AccountDomainBrandForm.vue -->
<script setup lang="ts">
import CycleButton from '@/components/common/CycleButton.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import { BrandSettings } from '@/types/onetime';
import { shouldUseLightText } from '@/utils/colorUtils';
import { Icon } from '@iconify/vue';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useNotificationsStore } from '@/stores/notifications'

const notifications = useNotificationsStore()
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
  submitForm
} = useFormSubmission({
  url: `/api/v2/account/domains/${domainId}/brand`,
  successMessage: 'Brand settings updated successfully.',
  onSuccess: (response) => {
    notifications.show('Brand settings saved successfully', 'success')
    if (response.data?.record?.brand) {
      emit('update:brandSettings', response.data.record.brand);
    } else {
      // Fallback to local data if response structure is unexpected
      emit('update:brandSettings', formData.value);
    }
  },
  onError: (err) => {
    notifications.show('Failed to save brand settings', 'error')
    console.error('Error saving brand settings:', err);
  },
});

watch(() => props.isLoading, (newVal: boolean, oldVal: boolean) => {
  if (!newVal && oldVal) {
    // Focus back on the form when loading completes
    document.querySelector('form')?.focus()
  }
})

// Add a watch effect for the primary color
watch(() => formData.value.primary_color, (newColor) => {
  const textLight = shouldUseLightText(newColor);
console.debug(newColor, textLight)
  if (newColor) {
    // Update button_text_light based on color contrast
    formData.value = {
      ...formData.value,
      button_text_light: textLight
    };
  }
}, { immediate: true });
</script>


<style>
/* Optional: Add transition for smooth tooltip appearance */
[role="tooltip"] {
  transition: opacity 150ms ease-in-out;
}
</style>
