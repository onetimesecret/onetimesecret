<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900 ">
    <DashboardTabNav class="mb-8" />

    <!-- Main Container -->
    <div class="max-w-4xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
      <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-xl overflow-hidden">
        <!-- Header with Preview -->
        <div class="relative h-48 bg-gradient-to-r from-brand-600 to-brand-800 dark:from-brand-800 dark:to-brand-900">
          <div class="absolute inset-0 bg-black/20"></div>
          <div class="absolute bottom-0 left-0 right-0 p-6 flex items-end space-x-6">

            <!-- Logo Preview/Upload -->
            <div class="relative group">
              <div
                   class="w-24 h-24 rounded-xl bg-white dark:bg-gray-700 shadow-lg overflow-hidden flex items-center justify-center border-4 border-white dark:border-gray-700">
                <img v-if="logoSrc"
                     :src="logoSrc"
                     alt="Brand logo"
                     class="w-full h-full object-cover">
                <svg v-else
                     class="w-12 h-12 text-gray-400"
                     fill="none"
                     stroke="currentColor"
                     viewBox="0 0 24 24">
                  <path stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
              </div>

              <!-- Upload Input -->
              <input type="file"
                     @change="handleLogoUpload"
                     class="hidden"
                     ref="fileInput"
                     accept="image/*">

              <!-- Overlay Controls -->
              <div v-if="logoSrc"
                   class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex flex-col items-center justify-center gap-2 rounded-xl">
                <button @click="$refs.fileInput.click()"
                        class="text-sm font-medium text-white hover:text-brand-200 transition-colors">
                  Change
                </button>
                <button @click="removeLogo"
                        class="text-sm font-medium text-red-400 hover:text-red-300 transition-colors">
                  Remove
                </button>
              </div>

              <!-- Upload Button (shown when no logo) -->
              <button v-else
                      @click="$refs.fileInput.click()"
                      class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center text-white rounded-xl">
                <span class="text-sm font-medium">Upload Logo</span>
              </button>
            </div>

            <!-- Brand Name & Description Preview -->
            <div class="flex-1">
              <h1 class="text-2xl font-bold text-white mb-2"
                  :style="{ fontFamily: brandSettings.font_family }">
                Brand Preview
              </h1>
              <p class="text-white/80 text-sm line-clamp-2"
                 :style="{ fontFamily: brandSettings.font_family }">
                {{ brandSettings.description || 'Add a description to showcase your brand' }}
              </p>
            </div>
          </div>
        </div>

        <!-- Form Section -->
        <div class="p-6 space-y-8"> <!-- Changed from grid to vertical stack -->



          <!-- Settings Section -->
          <div class="max-w-2xl"> <!-- Constrain width for better readability -->
            <h2 class="text-lg font-medium text-gray-900 dark:text-gray-100 mb-6">Brand Settings</h2>
            <div class="space-y-6">
              <div class="flex items-center space-x-4">
                <div class="relative">
                  <input type="color"
                         v-model="brandSettings.primary_color"
                         name="brand[primary_color]"
                         class="w-12 h-12 rounded-lg cursor-pointer border-2 border-gray-200 dark:border-gray-600">
                  <div class="absolute -right-2 -top-2 w-4 h-4 rounded-full"
                       :style="{ backgroundColor: brandSettings.primary_color }">
                  </div>
                </div>
                <input type="text"
                       v-model="brandSettings.primary_color"
                       name="brand[primary_color]"
                       class="flex-1 px-4 py-2 rounded-lg border border-gray-200 dark:border-gray-600 dark:bg-gray-700 text-sm">
              </div>
              <AccountDomainBrandForm v-if="!loading && !error"
                                      :brandSettings="brandSettings"
                                      :isLoading="loading"
                                      @update:brandSettings="updateBrandSettings"
                                      class="space-y-6" />
            </div>
          </div>

          <!-- Preview Section -->
          <div class="border-t border-gray-200 dark:border-gray-700 pt-8">
            <h2 class="text-lg font-medium text-gray-900 dark:text-gray-100 mb-6">Preview</h2>
            <div class="max-w-2xl mx-auto bg-gray-50 dark:bg-gray-900 rounded-xl p-6">
              <SecretPreview v-if="!loading && !error"
                             :brandSettings="brandSettings"
                             secretKey="abcd"
                             class="transform transition-all duration-200 hover:scale-[1.02]" />
            </div>
          </div>
        </div>
      </div>

    </div>

  </div>
</template>

<script setup lang="ts">
import AccountDomainBrandForm from '@/components/account/AccountDomainBrandForm.vue';
import SecretPreview from '@/components/account/SecretPreview.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { BrandSettings } from '@/types/onetime';
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import api from '@/utils/api';

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
  description: '',
  font_family: 'sans-serif',
  button_style: 'rounded'
});

const loading = ref(true);
const error = ref<string | null>(null);
const success = ref<string | null>(null);
const isSubmitting = ref(false);

// Computed property for logo preview
const logoSrc = computed(() => {
  if (brandSettings.value.image_encoded && brandSettings.value.image_content_type) {
    return `data:${brandSettings.value.image_content_type};base64,${brandSettings.value.image_encoded}`;
  }
  return null;
});

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
      description: brand.description || '',
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
const handleLogoUpload = async (event: Event) => {
  const file = (event.target as HTMLInputElement).files?.[0];
  if (file) {
    try {
      isSubmitting.value = true;
      error.value = '';
      success.value = '';

      const formData = new FormData();
      formData.append('logo', file);

      // Use api utility instead of fetch
      const response = await api.post(
        `/api/v2/account/domains/${domainId.value}/logo`,
        formData,
        {
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        }
      );

      // The api utility will automatically handle the shrimp update
      // through its interceptors

      if (response.data.success) {
        updateBrandSettings(response.data.record.brand, true);
        success.value = 'Logo uploaded successfully';
      } else {
        throw new Error(response.data.message || 'Failed to upload logo');
      }

    } catch (err: unknown) {
      console.error('Error uploading logo:', err);
      // Even if the request failed, the interceptor would have updated the shrimp
      // if it was included in the error response
      error.value = err instanceof Error ? err.message : 'Failed to upload logo. Please try again.';
      // Reset the file input
      (event.target as HTMLInputElement).value = '';
    } finally {
      isSubmitting.value = false;
    }
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
