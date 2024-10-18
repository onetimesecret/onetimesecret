<template>
  <div class="container mx-auto px-4 py-8">
    <h1 class="text-2xl font-bold mb-6 dark:text-white">Customization - {{ domainId }}</h1>
    <BasicFormAlerts :success="success" :error="error" />
    <form @submit.prevent="submitForm" class="space-y-6">
      <input type="hidden" name="shrimp" :value="csrfStore.shrimp" />

      <div>
    <label for="logo" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Logo</label>
    <input type="file" id="logo" name="logo" @change="handleLogoUpload" accept="image/*"
           class="mt-1 block w-full text-sm text-gray-500
                  file:mr-4 file:py-2 file:px-4
                  file:rounded-full file:border-0
                  file:text-sm file:font-semibold
                  file:bg-brandcompdim-50 file:text-brandcompdim-500
                  hover:file:bg-brandcompdim-100
                  dark:file:bg-brandcompdim-500 dark:file:text-brandcompdim-100
                  dark:hover:file:bg-brandcompdim-800">

    <img v-if="logoDataUrl" :src="logoDataUrl" :alt="localBrandSettings.image_filename" class="mt-2 h-20">
  </div>
      <div>
        <label for="primary_color" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Primary Color
        </label>
        <input type="color" id="primary_color" name="primary_color" v-model="localBrandSettings.primary_color"
           class="mt-1 block w-full h-10 rounded-md">
      </div>


      <div>
        <label for="description" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Description
        </label>
        <textarea id="description" name="description" v-model="localBrandSettings.description" rows="3"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
                         focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
                         dark:bg-gray-700 dark:border-gray-600 dark:text-white"></textarea>

      </div>


      <div>
        <label for="font_family" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Font Family
        </label>
        <select id="font_family" name="font_family" v-model="localBrandSettings.font_family"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
                       focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
                       dark:bg-gray-700 dark:border-gray-600 dark:text-white">
          <option></option>
          <option value="sans-serif">Sans-serif</option>
          <option value="serif">Serif</option>
          <option value="monospace">Monospace</option>
        </select>
      </div>

      <div>
        <label for="button_style" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Button Style
        </label>
        <select id="button_style" name="button_style" v-model="localBrandSettings.button_style"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
                       focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
                       dark:bg-gray-700 dark:border-gray-600 dark:text-white">
          <option></option>
          <option value="rounded">Rounded</option>
          <option value="square">Square</option>
          <option value="pill">Pill</option>
        </select>
      </div>

      <div>
        <button type="submit" :disabled="isSubmitting"
                class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm
                       text-sm font-medium rounded-md text-white
                       bg-brand-600 hover:bg-brand-700
                       focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
                       dark:bg-brand-500 dark:hover:bg-brand-600">
          {{ isSubmitting ? 'Saving...' : 'Save Settings' }}
        </button>
      </div>
    </form>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { useRoute } from 'vue-router';
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import { BrandSettings } from '@/types/onetime'; // Adjust the import according to your project structure

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


/**
 * Computed property to generate data URL for the logo image.
 * Includes debug logging for tracing the values.
 */
 const logoDataUrl = computed(() => {

  if (localBrandSettings.value.image_encoded && localBrandSettings.value.image_content_type) {
    const dataUrl = `data:${localBrandSettings.value.image_content_type};base64,${localBrandSettings.value.image_encoded}`;
    return dataUrl;
  }

  console.debug('No valid image data found, returning null.');
  return null;
});

watch(() => props.brandSettings, (newSettings) => {

  localBrandSettings.value = {
    logo: newSettings.logo || '',
    image_encoded: newSettings.image_encoded || '',
    primary_color: newSettings.primary_color || '#ededed',
    image_content_type: newSettings.image_content_type || '',
    image_filename: newSettings.image_filename || '',
    description: newSettings.description || '',
    font_family: newSettings.font_family || '',
    button_style: newSettings.button_style || ''
  };

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
    emit('updateBrandSettings', localBrandSettings.value);
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

      // Update localBrandSettings with the new image data
      localBrandSettings.value.image_encoded = data.image_encoded;
      localBrandSettings.value.image_content_type = data.image_content_type;
      localBrandSettings.value.image_filename = data.image_filename;

      success.value = 'Logo uploaded successfully';
    } catch (err: unknown) {
      console.error('Error uploading logo:', err);
      error.value = err instanceof Error ? err.message : 'Failed to upload logo. Please try again.';
    }
  }
};

</script>
