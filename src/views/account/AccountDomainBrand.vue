<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <!-- Domain Info -->
      <div class="border-b border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex items-center space-x-4">
            <RouterLink to="/account/domains"
                        class="inline-flex items-center text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100 transition-colors"
                        aria-label="Return to domains list">
              <svg class="w-5 h-5 mr-2"
                   fill="none"
                   stroke="currentColor"
                   viewBox="0 0 24 24"
                   aria-hidden="true">
                <path stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 19l-7-7m0 0l7-7m-7 7h18" />
              </svg>
              Back to Domains
            </RouterLink>
          </div>

          <div class="mt-4 flex flex-col gap-1">
            <div class="flex items-baseline justify-between">
              <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
                {{ domainId }}
              </h1>
              <span class="px-3 py-1 text-sm rounded-full bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-100"
                    role="status">
                Custom Domain
              </span>
            </div>
            <h2 class="text-base text-gray-600 dark:text-gray-400">
              Link Preview
            </h2>
          </div>
        </div>
      </div>

      <!-- Quick Settings Bar -->
      <div class="bg-white/80 dark:bg-gray-800/80 backdrop-blur-sm border-b border-gray-200 dark:border-gray-700">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
          <form @submit.prevent="submitForm"
                class="flex items-center gap-4">
            <input type="hidden"
                   name="shrimp"
                   :value="csrfStore.shrimp" />

            <!-- Color Picker -->
            <div class="w-48">
              <label id="color-picker-label"
                     class="sr-only">Brand Color</label>
              <div
                   class="group flex items-center bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-600 rounded-lg shadow-sm px-3 py-2">
                <div class="relative">
                  <input type="color"
                         v-model="brandSettings.primary_color"
                         name="brand[primary_color]"
                         class="w-8 h-8 rounded cursor-pointer border border-gray-200 dark:border-gray-600 focus:outline-none"
                         aria-labelledby="color-picker-label">
                  <div class="absolute -right-1 -top-1 w-3 h-3 rounded-full shadow-sm ring-2 ring-white dark:ring-gray-800"
                       :style="{ backgroundColor: brandSettings.primary_color }"
                       aria-hidden="true"></div>
                </div>
                <input type="text"
                       v-model="brandSettings.primary_color"
                       name="brand[primary_color]"
                       class="ml-3 w-24 bg-transparent border-none focus:ring-0 p-0 text-base font-medium text-gray-900 dark:text-gray-100 placeholder-gray-400 uppercase"
                       pattern="^#[0-9A-Fa-f]{6}$"
                       placeholder="#000000"
                       maxlength="7"
                       aria-label="Brand color hex value">
              </div>
            </div>

            <!-- Font Family -->
            <CycleButton v-model="brandSettings.font_family"
                         :options="fontOptions"
                         label=""
                         :display-map="fontDisplayMap"
                         :icon-map="{
                          'inter': 'simple-icons:inter',
                          'helvetica': 'simple-icons:helvetica',
                          'roboto': 'simple-icons:roboto',
                          'arial': 'material-symbols:font-download', // No specific Arial icon available
                          'system-ui': 'ph:desktop-bold',
                          'sans-serif': 'ph:text-aa-bold',
                          'serif': 'ph:text-t-bold',
                          'monospace': 'ph:code-simple-bold'

                        }" />
            <!-- Corner Style -->
            <CycleButton v-model="brandSettings.corner_style"
                         :options="cornerStyleOptions"
                         label="Corner Style"
                         :display-map="cornerStyleDisplayMap"
                         :icon-map="{
                          'rounded': 'tabler:border-corner-rounded',
                          'pill': 'tabler:border-corner-pill',
                          'square': 'tabler:border-corner-square'
                        }" />

            <!-- Spacer -->
            <div class="flex-1"></div>

            <div class="relative">
              <button type="button"
                      @click="isInstructionsOpen = !isInstructionsOpen"
                      class="inline-flex items-center px-3 py-2 border border-gray-200 dark:border-gray-600 rounded-lg shadow-sm text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500"
                      :aria-expanded="isInstructionsOpen"
                      aria-haspopup="true">
                <Icon icon="mdi:text-box-edit"
                      class="w-5 h-5 mr-2"
                      aria-hidden="true" />
                Instructions
                <Icon :icon="isInstructionsOpen ? 'mdi:chevron-up' : 'mdi:chevron-down'"
                      class="w-5 h-5 ml-2"
                      aria-hidden="true" />
              </button>

              <Transition enter-active-class="transition duration-200 ease-out"
                          enter-from-class="transform scale-95 opacity-0"
                          enter-to-class="transform scale-100 opacity-100"
                          leave-active-class="transition duration-75 ease-in"
                          leave-from-class="transform scale-100 opacity-100"
                          leave-to-class="transform scale-95 opacity-0">
                <div v-if="isInstructionsOpen"
                     class="absolute right-0 mt-2 w-96 bg-white dark:bg-gray-800 rounded-lg shadow-lg ring-1 ring-black ring-opacity-5 z-50">
                  <div class="p-4">
                    <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">
                      Pre-reveal Instructions
                      <Icon icon="mdi:help-circle"
                            class="inline-block w-4 h-4 ml-1 text-gray-400"
                            @mouseenter="tooltipShow = true"
                            @mouseleave="tooltipShow = false" />
                      <div v-if="tooltipShow"
                           class="absolute z-50 px-2 py-1 text-xs text-white bg-gray-900 dark:bg-gray-700 rounded shadow-lg max-w-xs">
                        These instructions will be shown to recipients before they reveal the secret content
                      </div>
                    </label>
                    <textarea v-model="brandSettings.instructions_pre_reveal"
                              ref="textareaRef"
                              rows="3"
                              class="w-full rounded-lg border-gray-300 dark:border-gray-600 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white text-sm"
                              placeholder="e.g. Use your phone to scan the QR code"
                              @keydown.esc="isInstructionsOpen = false"></textarea>

                    <div class="mt-2 flex justify-between items-center text-xs text-gray-500 dark:text-gray-400">
                      <span>{{ characterCount }}/500 characters</span>
                      <span>Press ESC to close</span>
                    </div>
                  </div>
                </div>
              </Transition>
            </div>





            <!-- Save Button -->
            <button type="submit"
                    :disabled="isSubmitting"
                    class="inline-flex items-center px-4 py-2 border border-transparent rounded-lg shadow-sm text-sm font-medium text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 disabled:opacity-50 disabled:cursor-not-allowed">
              <Icon v-if="isSubmitting"
                    icon="mdi:loading"
                    class="animate-spin -ml-1 mr-2 h-4 w-4" />
              <Icon v-else
                    icon="mdi:content-save"
                    class="-ml-1 mr-2 h-4 w-4" />
              {{ isSubmitting ? 'Save' : 'Save' }}
            </button>
          </form>
        </div>
      </div>
    </div>

    <!-- Main Content -->
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Preview Section -->
      <div class="relative mb-12">
        <!-- Preview Badge -->
        <div class="absolute -top-6 left-1/2 transform -translate-x-1/2 z-10 opacity-60">
          <span
                class="inline-flex items-center px-4 py-1.5 rounded-full text-xs font-medium bg-brandcomp-100 dark:bg-brandcomp-900 text-brand-800 dark:text-brandcomp-200 shadow-sm">
            <svg class="w-4 h-4 mr-1.5"
                 fill="none"
                 stroke="currentColor"
                 viewBox="0 0 24 24">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
            </svg>
            Preview Mode
          </span>
        </div>

        <!-- Browser-like frame -->
        <div class="rounded-xl shadow-2xl overflow-hidden border border-gray-200 dark:border-gray-700">
          <!-- Browser Top Bar -->
          <div
               class="bg-gray-100 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 p-3 flex items-center space-x-2">
            <div class="flex space-x-2">
              <div class="w-3 h-3 rounded-full bg-red-400"></div>
              <div class="w-3 h-3 rounded-full bg-yellow-400"></div>
              <div class="w-3 h-3 rounded-full bg-green-400"></div>
            </div>
            <div class="flex-1 mx-4">
              <div
                   class="bg-white dark:bg-gray-700 rounded-md px-3 py-1.5 text-sm text-gray-600 dark:text-gray-300 flex items-center">
                <svg class="w-4 h-4 mr-2 text-gray-400"
                     fill="none"
                     stroke="currentColor"
                     viewBox="0 0 24 24">
                  <path stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                <span class="text-green-400">https://</span><span class="font-bold">{{ domainId }}</span><span
                      class="opacity-50">/secret/abcdef0123456789</span>
              </div>
            </div>
          </div>

          <!-- Actual Preview Content -->
          <div class="bg-white dark:bg-gray-800 p-6">
            <SecretPreview v-if="!loading && !error"
                           ref="secretPreview"
                           :brandSettings="brandSettings"
                           :onLogoUpload="handleLogoUpload"
                           :onLogoRemove="removeLogo"
                           secretKey="abcd"
                           class="transform transition-all duration-200 hover:scale-[1.02]" />
          </div>
        </div>
      </div>

    </div>

    <!-- Loading State -->
    <div v-if="loading"
         class="fixed inset-0 bg-gray-900/50 dark:bg-gray-900/70 flex items-center justify-center"
         role="alert"
         aria-busy="true"
         aria-label="Loading brand settings">
      <div class="bg-white dark:bg-gray-800 rounded-lg p-6 shadow-xl">
        <div class="animate-spin w-8 h-8 border-4 border-gray-300 dark:border-gray-600 border-t-blue-600 rounded-full"
             aria-hidden="true"></div>
        <p class="sr-only">Loading brand settings, please wait...</p>
      </div>
    </div>

  </div>
</template>

<script setup lang="ts">
import SecretPreview from '@/components/account/SecretPreview.vue';
import CycleButton from '@/components/common/CycleButton.vue';
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notifications';
import { BrandSettings } from '@/types/onetime';
import api from '@/utils/api';
import { shouldUseLightText } from '@/utils/colorUtils';
import { Icon } from '@iconify/vue';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const notifications = useNotificationsStore();
const csrfStore = useCsrfStore();

const props = defineProps<{
  domain?: string;
}>();

const domainId = computed(() => `${props.domain || route.params.domain as string}`);

// State management
const brandSettings = ref<BrandSettings>({
  logo: '',
  primary_color: '#000000',
  image_content_type: '',
  image_encoded: '',
  image_filename: '',
  instructions_pre_reveal: '',
  instructions_post_reveal: '',
  instructions_reveal: '',
  font_family: 'sans-serif',
  corner_style: 'rounded',
  button_text_light: false,
});

const loading = ref(true);
const error = ref<string | null>(null);
const success = ref<string | null>(null);
const isSubmitting = ref(false);

const fontOptions = ['sans-serif', 'serif', 'monospace'];
const fontDisplayMap = {
  'sans-serif': 'Sans Serif',
  'serif': 'Serif',
  'monospace': 'Monospace'
};

const cornerStyleOptions = ['rounded', 'pill', 'square'];
const cornerStyleDisplayMap = {
  'rounded': 'Rounded',
  'pill': 'Pill Shape',
  'square': 'Square'
};

// API response interface
interface ApiResponse {
  record: {
    brand: Partial<BrandSettings>;
  };
}

// Fetch brand settings from the API
const fetchBrandSettings = async () => {
  loading.value = true;
  error.value = null;
  success.value = null;
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId.value}/brand`);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const data: ApiResponse = await response.json();
    const { brand } = data.record;
    updateBrandSettings({
      logo: brand.image_filename || '',
      primary_color: brand.primary_color || '#ffffff',
      instructions_pre_reveal: brand.instructions_pre_reveal || '',
      instructions_post_reveal: brand.instructions_post_reveal || '',
      instructions_reveal: brand.instructions_reveal || '',
      image_encoded: brand.image_encoded || '',
      image_filename: brand.image_filename || '',
      image_content_type: brand.image_content_type || '',
      font_family: brand.font_family || 'sans-serif',
      corner_style: brand.corner_style || 'rounded',
      button_text_light: brand.button_text_light || false,
    }, false);
  } catch (err) {
    console.error('Error fetching brand settings:', err);
    error.value = err instanceof Error ? err.message : 'Failed to fetch brand settings. Please try again.';
  } finally {
    loading.value = false;
  }
};

// Update brand settings
const updateBrandSettings = (newSettings: BrandSettings, showSuccessMessage: boolean = true) => {
  // Calculate button text color based on primary color before updating settings
  const textLight = shouldUseLightText(newSettings.primary_color);

  // Update settings with the correct button_text_light value
  brandSettings.value = {
    ...newSettings,
    button_text_light: textLight
  };

  if (showSuccessMessage) {
    success.value = 'Brand settings updated successfully';
  } else {
    success.value = null;
  }
};

// Form submission handler
const submitForm = async () => {
  try {
    isSubmitting.value = true;
    const response = await api.put(`/api/v2/account/domains/${domainId.value}/brand`, {
      brand: brandSettings.value,
      shrimp: csrfStore.shrimp
    });

    if (response.data.success) {
      updateBrandSettings(response.data.record.brand, true);
      notifications.show('Brand settings saved successfully', 'success');
    } else {
      throw new Error(response.data.message || 'Failed to save brand settings');
    }
  } catch (err) {
    console.error('Error saving brand settings:', err);
    notifications.show(
      err instanceof Error ? err.message : 'Failed to save brand settings. Please try again.',
      'error'
    );
  } finally {
    isSubmitting.value = false;
  }
};

// Handle logo upload
const handleLogoUpload = async (file: File) => {
  try {
    isSubmitting.value = true;

    const formData = new FormData();
    formData.append('logo', file);

    const response = await api.post(
      `/api/v2/account/domains/${domainId.value}/logo`,
      formData,
      {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      }
    );

    if (response.data.success) {
      updateBrandSettings(response.data.record.brand, true);
      notifications.show('Logo uploaded successfully', 'success');
    } else {
      throw new Error(response.data.message || 'Failed to upload logo');
    }

  } catch (err) {
    console.error('Error uploading logo:', err);
    notifications.show(
      err instanceof Error ? err.message : 'Failed to upload logo. Please try again.',
      'error'
    );
  } finally {
    isSubmitting.value = false;
  }
};

const removeLogo = async () => {
  try {
    isSubmitting.value = true;
    error.value = '';
    success.value = '';

    const response = await api.delete(`/api/v2/account/domains/${domainId.value}/logo`);

    if (response.data.success) {
      updateBrandSettings({
        ...brandSettings.value,
        image_encoded: '',
        image_content_type: '',
        image_filename: ''
      }, true);

      success.value = response.data.details?.msg || 'Logo removed successfully';
    } else {
      throw new Error('Failed to remove logo');
    }

  } catch (err) {
    console.error('Error removing logo:', err);
    error.value = err instanceof Error ? err.message : 'Failed to remove logo. Please try again.';
  } finally {
    isSubmitting.value = false;
  }
};

// Watch effect for primary color
watch(() => brandSettings.value.primary_color, (newColor) => {
  const textLight = shouldUseLightText(newColor);
  if (newColor) {
    brandSettings.value = {
      ...brandSettings.value,
      button_text_light: textLight
    };
  }
}, { immediate: true });



import { useEventListener } from '@vueuse/core';
import { nextTick } from 'vue';

const isInstructionsOpen = ref(false);
const tooltipShow = ref(false);
const textareaRef = ref<HTMLTextAreaElement | null>(null);

// Character count
const characterCount = computed(() =>
  brandSettings.value.instructions_pre_reveal?.length ?? 0
);

// Close on click outside
useEventListener(document, 'click', (e) => {
  const target = e.target as HTMLElement;
  if (!target.closest('.relative') && isInstructionsOpen.value) {
    isInstructionsOpen.value = false;
  }
}, { capture: true });

// Focus textarea when opening
watch(isInstructionsOpen, (newValue) => {
  if (newValue && textareaRef.value) {
    nextTick(() => {
      textareaRef.value?.focus();
    });
  }
});


// Fetch brand settings on component mount
onMounted(fetchBrandSettings); // Todo: move to router
</script>

<style>
[role="tooltip"] {
  transition: opacity 150ms ease-in-out;
}
</style>
