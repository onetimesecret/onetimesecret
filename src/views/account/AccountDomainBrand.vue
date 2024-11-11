<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader :displayDomain="displayDomain"
                    :domain="customDomain" />

      <BrandSettingsBar v-model="brandSettings"
                        :shrimp="csrfStore.shrimp"
                        :is-submitting="isSubmitting"
                        @submit="submitForm">
        <template #instructions-button>
          <InstructionsModal v-model="brandSettings.instructions_pre_reveal"
                             @update:modelValue="(value) => brandSettings.instructions_pre_reveal = value" />
        </template>
      </BrandSettingsBar>
    </div>

    <!-- Main Content -->
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 sm:py-8">
      <!-- Preview Section -->
      <div class="relative mb-6 sm:mb-12">
        <h2 id="previewHeading"
            class="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-6">
          Preview & Customize
        </h2>

        <!-- Instructions for screen readers -->
        <div class="sr-only"
             role="note">
          This is an interactive preview of how recipients will see your secure messages. You can:
          - Customize colors and fonts using the controls above
          - Upload a logo (minimum 128x128 pixels recommended, 1MB max)
          - Test the preview using the "View Secret" button
        </div>

        <!-- Visual instructions -->
        <ul class="mb-4 sm:mb-6 text-sm space-y-1 sm:space-y-2"
            :aria-hidden="true">
          <li class="flex items-center gap-2">
            <Icon icon="mdi:palette-outline"
                  class="w-5 h-5"
                  aria-label="Customization icon" />
            Use the controls above to customize brand color, styles, and recipient instructions
          </li>

          <li class="flex items-center gap-2">
            <Icon icon="mdi:image-outline"
                  class="w-5 h-5"
                  aria-label="Image icon" />
            Click the preview image below to update your logo (minimum 128x128 pixels recommended, 1MB max)
          </li>

          <li class="flex items-center gap-2">
            <Icon icon="mdi:eye-outline"
                  class="w-5 h-5"
                  aria-label="Eye icon" />
            Preview how recipients will see your secrets by testing the "View Secret" button
          </li>
        </ul>

        <BrowserPreviewFrame class="w-full max-w-3xl mx-auto overflow-hidden"
                             :domain="displayDomain"
                             :browser-type="selectedBrowserType"
                             @toggle-browser="toggleBrowser"
                             aria-labelledby="previewHeading">
          <SecretPreview v-if="!loading && !error"
                         ref="secretPreview"
                         :domainBranding="brandSettings"
                         :logoImage="logoImage"
                         :onLogoUpload="handleLogoUpload"
                         :onLogoRemove="removeLogo"
                         secretKey="abcd"
                         class="transform transition-all duration-200 hover:scale-[1.02] max-w-full" />
        </BrowserPreviewFrame>

        <!-- Loading and Error States -->
        <div v-if="loading"
             role="status"
             class="text-center py-8">
          <span class="sr-only">Loading preview...</span>
          <!-- Add loading spinner -->
        </div>

        <div v-if="error"
             role="alert"
             class="text-center py-8 text-red-600">
          {{ error }}
        </div>
      </div>
    </div>


    <!-- Loading Overlay -->
    <LoadingOverlay :show="loading"
                    message="Loading brand settings" />
  </div>
</template>

<script setup lang="ts">
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notifications';
import type { AsyncDataResult, BrandSettings, CustomDomain, CustomDomainApiResponse } from '@/types/onetime';
import { ImageProps } from '@/types/onetime';
import api from '@/utils/api';
import { shouldUseLightText } from '@/utils/colorUtils';
import { Icon } from '@iconify/vue';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { onBeforeRouteLeave, useRoute } from 'vue-router';

// Import components
import BrandSettingsBar from '@/components/account/BrandSettingsBar.vue';
import BrowserPreviewFrame from '@/components/account/BrowserPreviewFrame.vue';
import DomainHeader from '@/components/account/DomainHeader.vue';
import InstructionsModal from '@/components/account/InstructionsModal.vue';
import SecretPreview from '@/components/account/SecretPreview.vue';
import LoadingOverlay from '@/components/common/LoadingOverlay.vue';
import { useBrandingStore } from '@/stores/brandingStore';

const detectPlatform = (): 'safari' | 'edge' => {
  const ua = window.navigator.userAgent.toLowerCase();
  const isMac = /macintosh|mac os x|iphone|ipad|ipod/.test(ua);
  return isMac ? 'safari' : 'edge';
};

const route = useRoute();
const initialData = computed(() => route.meta.initialData as AsyncDataResult<CustomDomainApiResponse>);

const notifications = useNotificationsStore();
const csrfStore = useCsrfStore();


const selectedBrowserType = ref<'safari' | 'edge'>(detectPlatform());

const toggleBrowser = () => {
  selectedBrowserType.value = selectedBrowserType.value === 'safari' ? 'edge' : 'safari';
};

const props = defineProps<{
  domain?: string;
}>();

const displayDomain = computed(() => `${props.domain || route.params.domain as string}`);
const customDomain = ref<CustomDomain | null>(null);


// State management
const brandSettings = ref<BrandSettings>({
  primary_color: '#000000',
  instructions_pre_reveal: '',
  instructions_post_reveal: '',
  instructions_reveal: '',
  font_family: 'sans-serif',
  corner_style: 'rounded',
  button_text_light: false,
  allow_public_homepage: false,
});

const loading = ref(true);
const error = ref<string | null>(null);
const success = ref<string | null>(null);
const isSubmitting = ref(false);
//const domain = ref({} as CustomDomain)

// Add after other refs
// Move this up near the other refs, after the brandSettings ref
const hasUnsavedChanges = ref(false);
const originalSettings = ref<BrandSettings | null>(null);

// Create a new function to handle beforeunload event
const handleBeforeUnload = (e: BeforeUnloadEvent) => {
  if (hasUnsavedChanges.value) {
    e.preventDefault();
    e.returnValue = '';
    return '';
  }
};


// API response interface
interface ApiResponse {
  record: {
    brand?: Partial<BrandSettings>;
  };
}

// Fetch brand settings from the API
const fetchBrandSettings = async () => {
  loading.value = true;
  error.value = null;
  success.value = null;

  try {
    // Use preloaded data if available
    if (initialData.value) {

      if (initialData.value.data) {
        customDomain.value = initialData.value.data.record;
        const { brand } = customDomain.value;
        const settings = {
          primary_color: brand?.primary_color || '#ffffff',
          instructions_pre_reveal: brand?.instructions_pre_reveal || '',
          instructions_post_reveal: brand?.instructions_post_reveal || '',
          instructions_reveal: brand?.instructions_reveal || '',
          font_family: brand?.font_family || 'sans-serif',
          corner_style: brand?.corner_style || 'rounded',
          button_text_light: brand?.button_text_light || false,
          allow_public_homepage: brand?.allow_public_homepage || false,

        };
        brandSettings.value = settings;
        originalSettings.value = JSON.parse(JSON.stringify(settings)); // Deep copy initial settings
        hasUnsavedChanges.value = false; // Explicitly set to false
        return;
      }
    }

    // Fallback to API call if no preloaded data
    const response = await fetch(`/api/v2/account/domains/${displayDomain.value}/brand`);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const data: ApiResponse = await response.json();
    const { brand } = data.record;
    const settings = {
      primary_color: brand?.primary_color || '#ffffff',
      instructions_pre_reveal: brand?.instructions_pre_reveal || '',
      instructions_post_reveal: brand?.instructions_post_reveal || '',
      instructions_reveal: brand?.instructions_reveal || '',
      font_family: brand?.font_family || 'sans-serif',
      corner_style: brand?.corner_style || 'rounded',
      button_text_light: brand?.button_text_light || false,
      allow_public_homepage: brand?.allow_public_homepage || false,

    };
    brandSettings.value = settings;
    originalSettings.value = JSON.parse(JSON.stringify(settings)); // Deep copy initial settings
    hasUnsavedChanges.value = false; // Explicitly set to false
  } catch (err) {
    console.error('Error fetching brand settings:', err);
    error.value = err instanceof Error ? err.message : 'Failed to fetch brand settings. Please try again.';
  } finally {
    loading.value = false;
  }
};


// Update the updateBrandSettings function to properly merge the settings
const updateBrandSettings = (newSettings: Partial<BrandSettings>, showSuccessMessage: boolean = true) => {
  const textLight = shouldUseLightText(newSettings.primary_color || brandSettings.value.primary_color);

  brandSettings.value = {
    ...brandSettings.value,
    ...newSettings,
    instructions_pre_reveal: newSettings.instructions_pre_reveal ?? brandSettings.value.instructions_pre_reveal,
    instructions_post_reveal: newSettings.instructions_post_reveal ?? brandSettings.value.instructions_post_reveal,
    instructions_reveal: newSettings.instructions_reveal ?? brandSettings.value.instructions_reveal,
    button_text_light: textLight
  };

  // Set hasUnsavedChanges to true if current settings differ from original
  if (originalSettings.value) {
    hasUnsavedChanges.value = JSON.stringify(brandSettings.value) !== JSON.stringify(originalSettings.value);
  }

  if (showSuccessMessage) {
    success.value = 'Brand settings updated successfully';
    // Reset hasUnsavedChanges after successful save
    hasUnsavedChanges.value = false;
    // Update original settings
    originalSettings.value = { ...brandSettings.value };
  } else {
    success.value = null;
  }
};


// Form submission handler
const submitForm = async () => {
  try {
    isSubmitting.value = true;

    // Create a clean payload object with all the necessary fields
    const payload = {
      brand: {
        primary_color: brandSettings.value.primary_color,
        font_family: brandSettings.value.font_family,
        corner_style: brandSettings.value.corner_style,
        button_text_light: brandSettings.value.button_text_light,
        instructions_pre_reveal: brandSettings.value.instructions_pre_reveal,
        instructions_post_reveal: brandSettings.value.instructions_post_reveal,
        instructions_reveal: brandSettings.value.instructions_reveal,
        // Include other fields as needed
      },
      shrimp: csrfStore.shrimp
    };

    const response = await api.put(`/api/v2/account/domains/${displayDomain.value}/brand`, payload);

    if (response.data.success) {
      // Make sure we're getting all fields back from the response
      updateBrandSettings({
        ...brandSettings.value, // Keep existing values
        ...response.data.record.brand // Override with response data
      }, true);
      originalSettings.value = { ...brandSettings.value }; // Update original settings
      hasUnsavedChanges.value = false; // Reset changes flag

      notifications.show('Brand settings saved successfully', 'success', 'bottom');
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

const logoImage = ref<ImageProps | null>(null);

// Add function to fetch logo
const fetchLogo = async () => {
  try {
    const response = await api.get(`/api/v2/account/domains/${displayDomain.value}/logo`);
    if (response.data.success && response.data.record) {
      logoImage.value = response.data.record;
    }
  } catch {
    // Nothing to do here. This will fail until a logo is uploaded.
  }
};

// Update handleLogoUpload to set logo data after successful upload
const handleLogoUpload = async (file: File) => {
  try {
    isSubmitting.value = true;
    const formData = new FormData();
    formData.append('image', file);

    const response = await api.post(
      `/api/v2/account/domains/${displayDomain.value}/logo`,
      formData,
      {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      }
    );

    if (response.data.success) {
      // Update logo image data
      await fetchLogo();
      notifications.show('Logo uploaded successfully', 'success', 'bottom');
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

// Update removeLogo to clear logo data
const removeLogo = async () => {
  try {
    isSubmitting.value = true;
    const response = await api.delete(`/api/v2/account/domains/${displayDomain.value}/logo`);

    if (response.data.success) {
      logoImage.value = null;
      notifications.show('Logo removed successfully', 'success', 'bottom');
    } else {
      throw new Error('Failed to remove logo');
    }
  } catch (err) {
    console.error('Error removing logo:', err);
    notifications.show(
      err instanceof Error ? err.message : 'Failed to remove logo. Please try again.',
      'error'
    );
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

const brandingStore = useBrandingStore();

// Watch for changes in brandSettings.primary_color
watch(() => brandSettings.value.primary_color, (newColor) => {
  brandingStore.setPrimaryColor(newColor);
}, { immediate: true });

// Activate branding when the component is mounted
onMounted(() => {
  brandingStore.setActive(true);
});

// Deactivate branding when the component is unmounted
onUnmounted(() => {
  brandingStore.setActive(false);
});

// Update lifecycle hooks
onMounted(() => {
  fetchBrandSettings();
  fetchLogo();
  window.addEventListener('beforeunload', handleBeforeUnload);
});


onUnmounted(() => {
  window.removeEventListener('beforeunload', handleBeforeUnload);
});

// Navigation guard
onBeforeRouteLeave((to, from, next) => {
  if (hasUnsavedChanges.value) {
    const answer = window.confirm('You have unsaved changes. Are you sure you want to leave?');
    if (answer) {
      next();
    } else {
      next(false);
    }
  } else {
    next();
  }
});


</script>
