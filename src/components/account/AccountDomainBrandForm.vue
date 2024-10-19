<template>
  <form @submit.prevent="submitForm" class="space-y-8 max-w-2xl mx-auto">
    <input type="hidden" name="shrimp" :value="csrfStore.shrimp" />

    <BasicFormAlerts :success="success" :error="error" />

    <!-- Logo Upload -->
    <div class="space-y-4">
      <label for="logo" class="block text-lg font-brand font-semibold text-gray-700 dark:text-gray-200">Logo</label>
      <div class="flex items-center space-x-4">
        <div class="relative w-24 h-24 bg-gray-100 dark:bg-gray-700 rounded-lg overflow-hidden flex items-center justify-center border-2 border-dashed border-gray-300 dark:border-gray-600">
          <img v-if="logoDataUrl" :src="logoDataUrl" :alt="localBrandSettings.image_filename" class="w-full h-full object-cover">
          <svg v-else class="w-12 h-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg>
        </div>
        <div class="flex-grow">
          <input type="file" id="logo" name="logo" @change="handleLogoUpload" accept="image/*" class="hidden" ref="fileInput">
          <button type="button" @click="$refs.fileInput.click()"
                  class="w-full mb-2 px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-600 dark:hover:bg-gray-600 transition duration-300 ease-in-out">
            {{ localBrandSettings.image_filename ? 'Change Logo' : 'Upload Logo' }}
          </button>
          <p class="text-sm text-gray-500 dark:text-gray-400 truncate">{{ localBrandSettings.image_filename || 'No file chosen' }}</p>
        </div>
      </div>
      <button v-if="logoDataUrl" @click="removeLogo" type="button" class="text-sm text-red-600 hover:text-red-800 dark:text-red-400 dark:hover:text-red-300 transition duration-300 ease-in-out focus:outline-none focus:underline" aria-label="Remove logo">
        Remove Logo
      </button>
    </div>

    <!-- Primary Color -->
    <div class="space-y-2">
      <label for="primary_color" class="block text-lg font-brand font-semibold text-gray-700 dark:text-gray-200">
        Primary Color
      </label>
      <div class="flex items-center space-x-4">
        <input type="color" id="primary_color" v-model="localBrandSettings.primary_color"
               class="w-12 h-12 rounded-md border-2 border-gray-300 dark:border-gray-600 cursor-pointer">
        <input type="text" v-model="localBrandSettings.primary_color"
               class="flex-grow px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-brand-500 focus:border-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
               pattern="^#[0-9A-Fa-f]{6}$"
               title="Please enter a valid hex color code (e.g., #FF0000)">
      </div>
    </div>

    <!-- Description -->
    <div class="space-y-2">
      <label for="description" class="block text-lg font-brand font-semibold text-gray-700 dark:text-gray-200">
        Description
      </label>
      <textarea id="description" v-model="localBrandSettings.description" rows="3"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                placeholder="Enter a brief description of your brand"></textarea>
    </div>

    <!-- Font Family -->
    <div class="space-y-2">
      <label for="font_family" class="block text-lg font-brand font-semibold text-gray-700 dark:text-gray-200">
        Font Family
      </label>
      <select id="font_family" v-model="localBrandSettings.font_family"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
        <option value="">Select a font family</option>
        <option value="sans-serif">Sans-serif</option>
        <option value="serif">Serif</option>
        <option value="monospace">Monospace</option>
      </select>
    </div>

    <!-- Button Style -->
    <div class="space-y-2">
      <label for="button_style" class="block text-lg font-brand font-semibold text-gray-700 dark:text-gray-200">
        Button Style
      </label>
      <select id="button_style" v-model="localBrandSettings.button_style"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
        <option value="">Select a button style</option>
        <option value="rounded">Rounded</option>
        <option value="square">Square</option>
        <option value="pill">Pill</option>
      </select>
    </div>

    <!-- Submit Button -->
    <div class="pt-6">
      <button type="submit" :disabled="isSubmitting"
              class="w-full inline-flex justify-center py-3 px-4 border border-transparent shadow-sm text-base font-medium rounded-md text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-600 transition duration-300 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed">
        <span v-if="isSubmitting" class="mr-2">
          <svg class="animate-spin h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        </span>
        {{ isSubmitting ? 'Saving...' : 'Save Settings' }}
      </button>
    </div>
  </form>
</template>


<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { useRoute } from 'vue-router';
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import { BrandSettings } from '@/types/onetime';

const route = useRoute();
const domainId = route.params.domain as string;
const csrfStore = useCsrfStore();

const props = defineProps<{
  brandSettings: BrandSettings;
}>();

const emit = defineEmits(['updateBrandSettings']);

const localBrandSettings = ref<BrandSettings>({
  logo: props.brandSettings?.logo || '',
  image_encoded: props.brandSettings?.image_encoded || '',
  image_content_type: props.brandSettings?.image_content_type || '',
  image_filename: props.brandSettings?.image_filename || '',
  primary_color: props.brandSettings?.primary_color || '#000000',
  description: props.brandSettings?.description || '',
  font_family: props.brandSettings?.font_family || 'sans-serif',
  button_style: props.brandSettings?.button_style || 'rounded'
});

const logoDataUrl = computed(() => {
  if (localBrandSettings.value.image_encoded && localBrandSettings.value.image_content_type) {
    return `data:${localBrandSettings.value.image_content_type};base64,${localBrandSettings.value.image_encoded}`;
  }
  return null;
});

watch(() => props.brandSettings, (newSettings) => {
  localBrandSettings.value = { ...newSettings };
}, { deep: true, immediate: true });

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: `/api/v2/account/domains/${domainId}/brand`,
  successMessage: 'Brand settings saved successfully',
  onSuccess: () => {
    emit('updateBrandSettings', localBrandSettings.value, true);
  },
  onError: (err) => {
    console.error('Error saving brand settings:', err);
  },
});

const handleLogoUpload = async (event: Event) => {
  const file = (event.target as HTMLInputElement).files?.[0];
  if (file) {
    try {
      isSubmitting.value = true;
      error.value = '';
      success.value = '';

      const formData = new FormData();
      formData.append('logo', file);

      const response = await fetch(`/api/v2/account/domains/${domainId}/logo`, {
        method: 'POST',
        headers: {
          'O-Shrimp': csrfStore.shrimp,
        },
        body: formData,
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || 'Failed to upload logo');
      }

      // Use Vue's reactivity system to update the object
      Object.assign(localBrandSettings.value, {
        image_encoded: data.image_encoded,
        image_content_type: data.image_content_type,
        image_filename: data.image_filename,
      });

      emit('updateBrandSettings', {...localBrandSettings.value}, true);
      success.value = 'Logo uploaded successfully';
    } catch (err: unknown) {
      console.error('Error uploading logo:', err);
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

    const response = await fetch(`/api/v2/account/domains/${domainId}/logo`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'O-Shrimp': csrfStore.shrimp,
      },
    });

    if (!response.ok) {
      throw new Error('Failed to remove logo');
    }

    const result = await response.json();

    // Update local state
    localBrandSettings.value.image_encoded = '';
    localBrandSettings.value.image_content_type = '';
    localBrandSettings.value.image_filename = '';
    (document.getElementById('logo') as HTMLInputElement).value = '';

    success.value = result.details?.msg || 'Logo removed successfully';
    emit('updateBrandSettings', result.record, true);
  } catch (err: unknown) {
    console.error('Error removing logo:', err);
    error.value = err instanceof Error ? err.message : 'Failed to remove logo. Please try again.';
  } finally {
    isSubmitting.value = false;
  }
};


</script>
