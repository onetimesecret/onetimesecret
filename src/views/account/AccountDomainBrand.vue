<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Navigation Bar -->
    <nav class="border-b border-gray-200 dark:border-gray-800  bg-white dark:bg-gray-800 px-4 py-3">
      <router-link to="/account/domains"
                   class="inline-flex items-center text-base font-brand text-gray-700 dark:text-gray-200 hover:text-brand-600 dark:hover:text-brand-400 transition-colors"
                   aria-label="Back to domains">
        <Icon icon="heroicons-outline:chevron-left"
              class="w-4 h-4 mr-1" />

        Back to domains
      </router-link>
    </nav>

    <!-- Main Container -->
    <div class="max-w-5xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
      <!-- Status Messages -->
      <TransitionGroup name="fade">
        <div v-if="error"
             class="mb-4 p-4 bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-800 rounded-lg text-red-700 dark:text-red-300"
             :key="'error'">
          {{ error }}
        </div>
        <div v-if="success"
             class="mb-4 p-4 bg-green-50 dark:bg-green-900/30 border border-green-200 dark:border-green-800 rounded-lg text-green-700 dark:text-green-300"
             :key="'success'">
          {{ success }}
        </div>
      </TransitionGroup>

      <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-xl overflow-hidden">
        <!-- Brand Preview Header -->
        <div
             class="relative h-56 sm:h-64 bg-gradient-to-r from-brand-600 to-brand-800 dark:from-brand-800 dark:to-brand-900">
          <div class="absolute inset-0 bg-black/20"></div>

          <!-- Preview Controls -->
          <div class="absolute top-4 right-4">
            <button @click="isPreviewMode = !isPreviewMode"
                    class="px-4 py-2 bg-black/30 hover:bg-black/40 text-white rounded-lg text-sm font-medium transition-colors flex items-center">
              <Icon icon="heroicons-outline:eye"
                    class="w-4 h-4 mr-2" />
              <Icon icon="heroicons-outline:eye-off"
                    class="w-4 h-4 mr-2" />

              {{ isPreviewMode ? 'Exit Preview' : 'Preview Mode' }}
            </button>
          </div>

          <!-- Brand Content -->
          <div class="absolute bottom-0 left-0 right-0 p-6 sm:p-8">
            <div class="flex items-end space-x-6">
              <!-- Logo Upload Area -->
              <div class="relative group">
                <div class="w-24 h-24 sm:w-32 sm:h-32 rounded-xl bg-white dark:bg-gray-700 shadow-lg overflow-hidden flex items-center justify-center border-4 border-white dark:border-gray-700 transition-transform group-hover:scale-105"
                     :class="{ 'animate-pulse': isSubmitting }">
                  <img v-if="logoSrc"
                       :src="logoSrc"
                       alt="Brand logo"
                       class="w-full h-full object-cover">
                  <Icon icon="heroicons-outline:photograph"
                        class="w-12 h-12 text-gray-400"
                        aria-hidden="true" />
                </div>

                <!-- File Input -->
                <input type="file"
                       @change="handleLogoUpload"
                       class="hidden"
                       ref="fileInput"
                       accept="image/*"
                       aria-label="Upload brand logo">

                <!-- Upload Controls -->
                <div v-if="!isPreviewMode"
                     class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-all duration-200 flex flex-col items-center justify-center gap-2 rounded-xl">
                  <button @click="$refs.fileInput.click()"
                          class="text-sm font-medium text-white hover:text-brand-200 transition-colors flex items-center"
                          :disabled="isSubmitting">
                    <Icon icon="heroicons-outline:upload"
                          class="w-4 h-4 mr-1" />

                    {{ logoSrc ? 'Change' : 'Upload' }}
                  </button>
                  <button v-if="logoSrc"
                          @click="removeLogo"
                          class="text-sm font-medium text-red-400 hover:text-red-300 transition-colors flex items-center"
                          :disabled="isSubmitting">
                    <Icon icon="heroicons-outline:trash"
                          class="w-4 h-4 mr-1" />
                    Remove
                  </button>
                </div>
              </div>

              <!-- Brand Text Preview -->
              <div class="flex-1">
                <h1 class="text-2xl sm:text-3xl font-bold text-white mb-2"
                    :style="{ fontFamily: brandSettings.font_family }">
                  {{ brandSettings.name || 'Your Brand Name' }}
                </h1>
                <p class="text-white/80 text-sm sm:text-base line-clamp-2"
                   :style="{ fontFamily: brandSettings.font_family }">
                  {{ brandSettings.description || 'Add a description to showcase your brand' }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Settings Tabs -->
        <div class="border-b border-gray-200 dark:border-gray-700">
          <nav class="px-6 -mb-px flex space-x-6"
               role="tablist">
            <button v-for="tab in tabs"
                    :key="tab.id"
                    @click="switchTab(tab.id)"
                    :aria-selected="activeTab === tab.id"
                    :aria-controls="`panel-${tab.id}`"
                    role="tab"
                    class="py-4 border-b-2 text-sm font-medium transition-colors"
                    :class="[
                      activeTab === tab.id
                        ? 'border-brand-600 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                        : 'border-transparent text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'
                    ]">
              {{ tab.name }}
            </button>
          </nav>
        </div>

          <!-- Content Sections -->
  <div class="p-6 space-y-8">
    <div v-if="loading" class="space-y-4">
      <div v-for="n in 3"
           :key="n"
           class="h-8 bg-gray-200 dark:bg-gray-700 rounded animate-pulse">
      </div>
    </div>

    <Transition name="fade" mode="out-in">
      <div v-if="!loading"
           role="tabpanel"
           :aria-labelledby="`tab-${activeTab}`">
        <BrandSettingsBasic
          v-if="activeTab === 'basic'"
          :brandSettings="brandSettings"
          :isSubmitting="isSubmitting"
          @update:brandSettings="updateBrandSettings"
        />
        <BrandSettingsAppearance
          v-if="activeTab === 'appearance'"
          :brandSettings="brandSettings"
          :isSubmitting="isSubmitting"
          @update:brandSettings="updateBrandSettings"
        />
        <BrandSettingsAdvanced
          v-if="activeTab === 'advanced'"
          :brandSettings="brandSettings"
          :isSubmitting="isSubmitting"
          @update:brandSettings="updateBrandSettings"
        />
      </div>
    </Transition>
  </div>
      </div>
    </div>
  </div>
</template>


<script setup lang="ts">
import { BrandSettings } from '@/types/onetime';
import api from '@/utils/api';
import { Icon } from '@iconify/vue';
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

// Import and define components
import BrandSettingsAdvanced from './tabs/BrandSettingsAdvanced.vue';
import BrandSettingsAppearance from './tabs/BrandSettingsAppearance.vue';
import BrandSettingsBasic from './tabs/BrandSettingsBasic.vue';

const tabs = [
  { id: 'basic', name: 'Basic Information' },
  { id: 'appearance', name: 'Appearance' },
  { id: 'advanced', name: 'Advanced' }
] as const

const activeTab = ref<string>('basic')

const switchTab = (tabId: string) => {
  activeTab.value = tabId
}



const route = useRoute();

const props = defineProps<{
  domain?: string;
}>();


const isPreviewMode = ref(false);

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

<style>
.tab-fade-enter-active,
.tab-fade-leave-active {
  transition: opacity 0.2s ease;
}

.tab-fade-enter-from,
.tab-fade-leave-to {
  opacity: 0;
}
</style>
