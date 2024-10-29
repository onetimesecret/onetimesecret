<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader :domain-id="domainId" />

      <BrandSettingsBar
        v-model="brandSettings"
        :shrimp="csrfStore.shrimp"
        :is-submitting="isSubmitting"
        @submit="submitForm">
        <template #instructions-button>
          <InstructionsModal
            v-model="brandSettings.instructions_pre_reveal" />
        </template>
      </BrandSettingsBar>
    </div>

    <!-- Main Content -->
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Preview Section -->
      <div class="relative mb-12">
        <BrowserPreviewFrame :domain="domainId">
          <SecretPreview
            v-if="!loading && !error"
            ref="secretPreview"
            :brandSettings="brandSettings"
            :onLogoUpload="handleLogoUpload"
            :onLogoRemove="removeLogo"
            secretKey="abcd"
            class="transform transition-all duration-200 hover:scale-[1.02]" />
        </BrowserPreviewFrame>
      </div>
    </div>

    <!-- Loading Overlay -->
    <LoadingOverlay
      :show="loading"
      message="Loading brand settings" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useCsrfStore } from '@/stores/csrfStore';
import { useNotificationsStore } from '@/stores/notifications';
import type { BrandSettings } from '@/types/onetime';
import api from '@/utils/api';
import { shouldUseLightText } from '@/utils/colorUtils';

// Import components
import DomainHeader from '@/components/account/DomainHeader.vue';
import BrandSettingsBar from '@/components/account/BrandSettingsBar.vue';
import BrowserPreviewFrame from '@/components/account/BrowserPreviewFrame.vue';
import InstructionsModal from '@/components/account/InstructionsModal.vue';
import SecretPreview from '@/components/account/SecretPreview.vue';
import LoadingOverlay from '@/components/common/LoadingOverlay.vue';

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
  const textLight = shouldUseLightText(newSettings.primary_color);
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

// Fetch brand settings on component mount
onMounted(fetchBrandSettings);
</script>
