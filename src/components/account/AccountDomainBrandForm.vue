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
        <img v-if="localBrandSettings.logo" :src="localBrandSettings.logo" alt="Logo" class="mt-2 h-20">
      </div>

      <div>
        <label for="primaryColor" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Primary Color
        </label>
        <input type="color" id="primaryColor" v-model="localBrandSettings.primary_color"
           class="mt-1 block w-full h-10 rounded-md">
      </div>

      <div>
        <label for="description" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Description
        </label>
        <textarea id="description" v-model="localBrandSettings.description" rows="3"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
                         focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
                         dark:bg-gray-700 dark:border-gray-600 dark:text-white"></textarea>
      </div>

      <div>
        <label for="fontFamily" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Font Family
        </label>
        <select id="fontFamily" v-model="localBrandSettings.font_family"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
                       focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
                       dark:bg-gray-700 dark:border-gray-600 dark:text-white">
          <option value="sans-serif">Sans-serif</option>
          <option value="serif">Serif</option>
          <option value="monospace">Monospace</option>
        </select>
      </div>

      <div>
        <label for="buttonStyle" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Button Style
        </label>
        <select id="buttonStyle" v-model="localBrandSettings.button_style"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
                       focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
                       dark:bg-gray-700 dark:border-gray-600 dark:text-white">
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
import { ref, watch, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';

const route = useRoute();
const domainId = route.params.domain as string;
const csrfStore = useCsrfStore();

interface BrandSettings {
  logo: string;
  primary_color: string;
  description: string;
  font_family: string;
  button_style: string;
}

const props = defineProps<{
  brandSettings: BrandSettings;
}>();

const emit = defineEmits(['updateBrandSettings']);

const localBrandSettings = ref<BrandSettings>({
  logo: '',
  primary_color: '#000000',
  description: '',
  font_family: 'sans-serif',
  button_style: 'rounded'
});

watch(() => props.brandSettings, (newSettings) => {
  console.log('Updating local settings:', newSettings);
  // Explicitly update each field
  localBrandSettings.value = {
    logo: newSettings.logo || '',
    primary_color: newSettings.primary_color || '#000000',
    description: newSettings.description || '',
    font_family: newSettings.font_family || 'sans-serif',
    button_style: newSettings.button_style || 'rounded'
  };
  console.log('Updated local settings:', localBrandSettings.value);
}, { deep: true, immediate: true });

onMounted(() => {
  console.log('Component mounted. Local settings:', localBrandSettings.value);
  console.log('Props brand settings:', props.brandSettings);
});

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: `/api/v2/account/domains/${domainId}/brand`,
  successMessage: 'Brand settings saved successfully',
  onSuccess: (data) => {
    console.debug(data)
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
      localBrandSettings.value.logo = data.logoUrl;
      success.value = 'Logo uploaded successfully';
    } catch (err: unknown) {
      console.error('Error uploading logo:', err);
      error.value = err instanceof Error ? err.message : 'Failed to upload logo. Please try again.';
    }
  }
};
</script>
