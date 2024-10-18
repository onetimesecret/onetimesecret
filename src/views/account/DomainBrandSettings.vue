<template>
  <div class="container mx-auto px-4 py-8">
    <h1 class="text-2xl font-bold mb-6 dark:text-white">Domain Branding Settings</h1>
    <form @submit.prevent="saveBrandingSettings" class="space-y-6">
      <div>
        <label for="logo" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Logo</label>
        <input type="file" id="logo" @change="handleLogoUpload" accept="image/*" class="mt-1 block w-full text-sm text-gray-500
          file:mr-4 file:py-2 file:px-4
          file:rounded-full file:border-0
          file:text-sm file:font-semibold
          file:bg-violet-50 file:text-violet-700
          hover:file:bg-violet-100
          dark:file:bg-violet-900 dark:file:text-violet-300
          dark:hover:file:bg-violet-800
        ">
      </div>
      <div>
        <label for="primaryColor" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Primary Color</label>
        <input type="color" id="primaryColor" v-model="brandingSettings.primaryColor" class="mt-1 block w-full h-10 rounded-md">
      </div>
      <div>
        <label for="description" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Description</label>
        <textarea id="description" v-model="brandingSettings.description" rows="3" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"></textarea>
      </div>
      <div>
        <label for="fontFamily" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Font Family</label>
        <select id="fontFamily" v-model="brandingSettings.fontFamily" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
          <option value="sans-serif">Sans-serif</option>
          <option value="serif">Serif</option>
          <option value="monospace">Monospace</option>
        </select>
      </div>
      <div>
        <label for="buttonStyle" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Button Style</label>
        <select id="buttonStyle" v-model="brandingSettings.buttonStyle" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
          <option value="rounded">Rounded</option>
          <option value="square">Square</option>
          <option value="pill">Pill</option>
        </select>
      </div>
      <div>
        <button type="submit" class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 dark:bg-indigo-500 dark:hover:bg-indigo-600">
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
const domainId = route.params.id as string;
const csrfStore = useCsrfStore();

interface BrandingSettings {
  logo: string;
  primaryColor: string;
  description: string;
  fontFamily: string;
  buttonStyle: string;
}

const brandingSettings = ref<BrandingSettings>({
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
    // and get back a URL to store in brandingSettings.logo
    console.log('File selected:', file.name);
  }
};

const saveBrandingSettings = async () => {
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId}/branding`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfStore.shrimp,
      },
      body: JSON.stringify(brandingSettings.value),
    });

    if (!response.ok) {
      throw new Error('Failed to save branding settings');
    }

    alert('Branding settings saved successfully!');
  } catch (error) {
    console.error('Error saving branding settings:', error);
    alert('Failed to save branding settings. Please try again.');
  }
};

const fetchBrandingSettings = async () => {
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId}/branding`);
    if (!response.ok) {
      throw new Error('Failed to fetch branding settings');
    }
    const data = await response.json();
    brandingSettings.value = data;
  } catch (error) {
    console.error('Error fetching branding settings:', error);
    alert('Failed to fetch branding settings. Please try again.');
  }
};

onMounted(fetchBrandingSettings);
</script>
