<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section -->
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

        <div class="mt-4 flex items-baseline justify-between">
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
            {{ domainId }}
          </h1>
          <span class="px-3 py-1 text-sm rounded-full bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-100"
                role="status">
            Custom Domain
          </span>
        </div>
      </div>
    </div>

    <!-- Preview Section - Full Width -->
    <div class="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 shadow-xl">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">

        <div class="bg-gray-50 dark:bg-gray-900 rounded-xl p-8 shadow-inner"
             role="region"
             aria-label="Secret link preview">
          <SecretPreview v-if="!loading && !error"
                         ref="secretPreview"
                         :brandSettings="brandSettings"
                         :onLogoUpload="handleLogoUpload"
                         :onLogoRemove="removeLogo"
                         secretKey="abcd"
                         class="transform transition-all duration-200 hover:scale-[1.02]" />
        </div>
        <div class="flex justify-between items-baseline mb-6">
        <div class="text-sm text-gray-600 dark:text-gray-400">
          <span class="inline-flex items-center">
            <Icon icon="mdi:information-outline"
                  class="mr-1"
                  aria-hidden="true" />
            Logo should be square, at least 128x128px, with a max size of 2MB.
          </span>
          <div class="mt-1">Supported formats: PNG, JPG, SVG</div>
        </div>
      </div>
</div>
      <!-- Settings Section -->
      <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-xl overflow-hidden">
        <div class="p-8">
          <h2 class="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-6">
            Brand Settings
          </h2>

          <div class="space-y-6">

            <!-- Brand Settings Form -->
            <AccountDomainBrandForm v-if="!loading && !error"
                                    :brandSettings="brandSettings"
                                    :isLoading="loading"
                                    @update:brandSettings="updateBrandSettings"
                                    class="space-y-6" />
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
import AccountDomainBrandForm from '@/components/account/AccountDomainBrandForm.vue';
import SecretPreview from '@/components/account/SecretPreview.vue';
import { BrandSettings } from '@/types/onetime';
import api from '@/utils/api';
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { Icon } from '@iconify/vue';

const route = useRoute();

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
  button_style: 'rounded'
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
    console.log(brand, data);
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
      button_style: brand.button_style || 'rounded'
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
  brandSettings.value = newSettings;
  if (showSuccessMessage) {
    success.value = 'Brand settings updated successfully';
  } else {
    success.value = null;
  }
};

// Handle logo upload
// Then modify handleLogoUpload

// Update the handleLogoUpload to be more generic
const handleLogoUpload = async (file: File) => {
  try {
    isSubmitting.value = true;
    error.value = '';
    success.value = '';

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
      success.value = 'Logo uploaded successfully';
    } else {
      throw new Error(response.data.message || 'Failed to upload logo');
    }

  } catch (err: unknown) {
    console.error('Error uploading logo:', err);
    error.value = err instanceof Error ? err.message : 'Failed to upload logo. Please try again.';
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

    // The api utility will automatically handle the shrimp update

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

  } catch (err: unknown) {
    console.error('Error removing logo:', err);
    error.value = err instanceof Error ? err.message : 'Failed to remove logo. Please try again.';
  } finally {
    isSubmitting.value = false;
  }
};

// Fetch brand settings on component mount
onMounted(fetchBrandSettings);
</script>
