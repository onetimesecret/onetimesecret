<template>
  <div class="container mx-auto px-4 py-8">
    <h1 class="text-2xl font-bold mb-6 dark:text-white">Customization - {{ domainId }}</h1>
    <form @submit.prevent="saveBrandSettings"
          class="space-y-6">
      <div>
        <label for="logo"
               class="block text-sm font-medium text-gray-700 dark:text-gray-300">Logo</label>
        <input type="file"
               id="logo"
               @change="handleLogoUpload"
               accept="image/*"
               class="mt-1 block w-full text-sm text-gray-500
            file:mr-4 file:py-2 file:px-4
            file:rounded-full file:border-0
            file:text-sm file:font-semibold
            file:bg-brandcompdim-50 file:text-brandcompdim-500
            hover:file:bg-brandcompdim-100
            dark:file:bg-brandcompdim-500 dark:file:text-brandcompdim-100
            dark:hover:file:bg-brandcompdim-800">
      </div>
      <div>
        <label for="primaryColor"
               class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Primary Color
        </label>
        <input type="color"
               id="primaryColor"
               v-model="brandSettings.primaryColor"
               class="mt-1 block w-full h-10 rounded-md">
      </div>
      <div>
        <label for="description"
               class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Description
        </label>
        <textarea id="description"
                  v-model="brandSettings.description"
                  rows="3"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
            focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
            dark:bg-gray-700 dark:border-gray-600 dark:text-white"></textarea>
      </div>
      <div>
        <label for="fontFamily"
               class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Font Family
        </label>
        <select id="fontFamily"
                v-model="brandSettings.fontFamily"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
            focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
            dark:bg-gray-700 dark:border-gray-600 dark:text-white">
          <option value="sans-serif">Sans-serif</option>
          <option value="serif">Serif</option>
          <option value="monospace">Monospace</option>
        </select>
      </div>
      <div>
        <label for="buttonStyle"
               class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Button Style
        </label>
        <select id="buttonStyle"
                v-model="brandSettings.buttonStyle"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
            focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50
            dark:bg-gray-700 dark:border-gray-600 dark:text-white">
          <option value="rounded">Rounded</option>
          <option value="square">Square</option>
          <option value="pill">Pill</option>
        </select>
      </div>
      <div>
        <button type="submit"
                class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm
            text-sm font-medium rounded-md text-white
            bg-brand-600 hover:bg-brand-700
            focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
            dark:bg-brand-500 dark:hover:bg-brand-600">
          Save Settings
        </button>
      </div>
    </form>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useCsrfStore } from '@/stores/csrfStore';

const route = useRoute();
const domainId = route.params.domain as string;
const csrfStore = useCsrfStore();

interface BrandSettings {
  logo: string;
  primaryColor: string;
  description: string;
  fontFamily: string;
  buttonStyle: string;
}

const brandSettings = ref<BrandSettings>({
  logo: '',
  primaryColor: '#000000',
  description: '',
  fontFamily: 'sans-serif',
  buttonStyle: 'rounded'
});

const handleLogoUpload = (event: Event) => {
  const file = (event.target as HTMLInputElement).files?.[0];
  if (file) {
    // Here you would typically upload the file to your server
    // and get back a URL to store in brandSettings.logo
    console.log('File selected:', file.name);
  }
};

const saveBrandSettings = async () => {
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId}/brand`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfStore.shrimp,
      },
      body: JSON.stringify(brandSettings.value),
    });

    if (!response.ok) {
      throw new Error('Failed to save brand settings');
    }

    throw ('Brand settings saved successfully!');
  } catch (error) {
    console.error('Error saving brand settings:', error);
    throw ('Failed to save brand settings. Please try again.');
  }
};

const fetchBrandSettings = async () => {
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId}/brand`);
    if (!response.ok) {
      throw new Error('Failed to fetch brand settings');
    }
    const data = await response.json();
    brandSettings.value = data;
  } catch (error) {
    console.error('Error fetching brand settings:', error);
    throw ('Failed to fetch brand settings. Please try again.');
  }
};

onMounted(fetchBrandSettings);

</script>
