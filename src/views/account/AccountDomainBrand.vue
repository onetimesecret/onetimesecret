<template>
  <AuthView :heading="`Customize - ${domainId}`" headingId="domain-brand">
    <template #form>
      <div v-if="loading" class="text-center">
        <p>Loading brand settings...</p>
      </div>
      <div v-else-if="error" class="text-center text-red-600">
        <p>{{ error }}</p>
        <button @click="fetchBrandSettings" class="mt-2 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
          Retry
        </button>
      </div>
      <AccountDomainBrandForm
        v-else
        :brandSettings="brandSettings"
        @updateBrandSettings="updateBrandSettings"
      />
    </template>
  </AuthView>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import AuthView from '@/components/auth/AuthView.vue';
import AccountDomainBrandForm from '@/components/account/AccountDomainBrandForm.vue';
import { BrandSettings } from '@/types/onetime';

const route = useRoute();
const domainId = route.params.domain as string;

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

const fetchBrandSettings = async () => {
  loading.value = true;
  error.value = null;
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId}/brand`);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const data = await response.json();

    // Map the received data to the expected format
    const mappedData = {
      logo: data.record.brand.image_filename || '',
      primary_color: data.record.brand.primary_color || '#ffffff',
      description: data.record.brand.description || '',
      image_encoded: data.record.brand.image_encoded || '',
      image_filename: data.record.brand.image_filename || '',
      image_content_type: data.record.brand.image_content_type || '',
      font_family: data.record.brand.font_family || '',
      button_style: data.record.brand.button_style || ''
    };

    updateBrandSettings(mappedData);
  } catch (err) {
    console.error('Error fetching brand settings:', err);
    error.value = 'Failed to fetch brand settings. Please try again.';
  } finally {
    loading.value = false;
  }
};

const updateBrandSettings = (newSettings: BrandSettings) => {
  brandSettings.value = newSettings;
  console.debug('Brand settings updated', newSettings);
};

onMounted(fetchBrandSettings);
</script>
