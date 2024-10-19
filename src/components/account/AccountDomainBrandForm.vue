<template>
  <form @submit.prevent="submitForm" class="space-y-8">
    <input type="hidden" name="shrimp" :value="csrfStore.shrimp" />

    <BasicFormAlerts :success="success" :error="error" />

    <!-- Logo Upload -->
    <div class="space-y-4">
      <label for="logo" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Logo</label>
      <div class="flex items-center space-x-4">
        <input type="file" id="logo" name="logo" @change="handleLogoUpload" accept="image/*"
               class="hidden" ref="fileInput">
        <button type="button" @click="$refs.fileInput.click()"
                class="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-600 dark:hover:bg-gray-600 transition duration-300 ease-in-out">
          {{ localBrandSettings.image_filename ? 'Change Logo' : 'Upload Logo' }}
        </button>
        <span class="text-sm text-gray-500 dark:text-gray-400">{{ localBrandSettings.image_filename || 'No file chosen' }}</span>
      </div>
      <div v-if="logoDataUrl" class="mt-2 relative w-20 h-20">
        <img :src="logoDataUrl" :alt="localBrandSettings.image_filename" class="w-full h-full object-cover rounded-md">
        <button @click="removeLogo" type="button" class="absolute top-0 right-0 bg-red-500 text-white rounded-full p-1 transform translate-x-1/2 -translate-y-1/2 hover:bg-red-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500" aria-label="Remove logo">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
        </button>
      </div>
    </div>

    <!-- Primary Color -->
    <div class="space-y-2">
      <label for="primary_color" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
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
      <label for="description" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
        Description
      </label>
      <textarea id="description" v-model="localBrandSettings.description" rows="3"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                placeholder="Enter a brief description of your brand"></textarea>
    </div>

    <!-- Font Family -->
    <div class="space-y-2">
      <label for="font_family" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
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
      <label for="button_style" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
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
    <div class="pt-4">
      <button type="submit" :disabled="isSubmitting"
              class="w-full inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-600 transition duration-300 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed">
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
      const formData = new FormData();
      formData.append('logo', file);

      const response = await fetch(`/api/v2/account/domains/${domainId}/logo`, {
        method: 'POST',
        headers: {
          'O-Shrimp': csrfStore.shrimp,
        },
        body: formData,
      });

      if (!response.ok) {
        throw new Error('Failed to upload logo');
      }

      const data = await response.json();

      localBrandSettings.value.image_encoded = data.image_encoded;
      localBrandSettings.value.image_content_type = data.image_content_type;
      localBrandSettings.value.image_filename = data.image_filename;

      emit('updateBrandSettings', localBrandSettings.value, true);
    } catch (err: unknown) {
      console.error('Error uploading logo:', err);
      error.value = err instanceof Error ? err.message : 'Failed to upload logo. Please try again.';
    }
  }
};

const removeLogo = async () => {
  localBrandSettings.value.image_encoded = '';
  localBrandSettings.value.image_content_type = '';
  localBrandSettings.value.image_filename = '';
  (document.getElementById('logo') as HTMLInputElement).value = '';

  try {
    isSubmitting.value = true;
    error.value = '';
    success.value = '';

    const response = await fetch(`/api/v2/account/domains/${domainId}/brand`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'O-Shrimp': csrfStore.shrimp,
      },
      body: JSON.stringify(localBrandSettings.value),
    });

    if (!response.ok) {
      throw new Error('Failed to save brand settings');
    }

    success.value = 'Logo removed successfully';
    emit('updateBrandSettings', localBrandSettings.value, true);
  } catch (err: unknown) {
    console.error('Error removing logo:', err);
    error.value = err instanceof Error ? err.message : 'Failed to remove logo. Please try again.';
  } finally {
    isSubmitting.value = false;
  }
};

</script>
