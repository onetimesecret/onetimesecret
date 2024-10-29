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

    <!-- Preview Section - Full Width -->
    <div class="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 shadow-xl">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Preview Container -->
        <div class="relative">
          <!-- Preview Badge -->
          <div class="absolute -top-4 left-1/2 transform -translate-x-1/2 z-10 opacity-60">
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

          <!-- Preview Instructions -->
          <div class="mt-4 text-center">
            <p class="text-sm text-gray-500 dark:text-gray-400">
              This is what the recipient sees when they open the secret link.
            </p>
          </div>
        </div>

      </div>

      <!-- Settings Section -->
      <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-xl overflow-hidden">
        <div class="p-8">
          <h2 class="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-6">
            Brand Settings
          </h2>
          <div class="flex justify-between items-baseline p-6">
            <div class="text-sm text-gray-600 dark:text-gray-400">
              <span class="inline-flex items-center">
                <Icon icon="mdi:information-outline"
                      class="mr-1"
                      aria-hidden="true" />
                Click on the preview should be square, at least 128x128px, with a max size of 2MB.
              </span>
              <div class="mt-1">Supported formats: PNG, JPG, SVG</div>
            </div>
          </div>
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
  button_style: 'rounded',
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
      button_style: brand.button_style || 'rounded',
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
  brandSettings.value = newSettings;
  if (showSuccessMessage) {
    success.value = 'Brand settings updated successfully';
  } else {
    success.value = null;
  }
};
import { useNotificationsStore } from '@/stores/notifications';

const notifications = useNotificationsStore();
//const isSubmitting = ref(false)

// Handle logo upload
// Then modify handleLogoUpload

// Update the handleLogoUpload to be more generic
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

  } catch (err: unknown) {
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
