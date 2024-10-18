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
        @settingsSaved="handleSettingsSaved"
      />
    </template>
  </AuthView>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import AuthView from '@/components/auth/AuthView.vue';
import AccountDomainBrandForm from '@/components/account/AccountDomainBrandForm.vue';

const route = useRoute();
const domainId = route.params.domain as string;

interface CustomDomainBrand {
  logo: string;
  primaryColor: string;
  description: string;
  fontFamily: string;
  buttonStyle: string;
}

const brandSettings = ref<CustomDomainBrand>({
  logo: '',
  primaryColor: '#000000',
  description: '',
  fontFamily: 'sans-serif',
  buttonStyle: 'rounded'
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
    brandSettings.value = data;
  } catch (err) {
    console.error('Error fetching brand settings:', err);
    error.value = 'Failed to fetch brand settings. Please try again.';
  } finally {
    loading.value = false;
  }
};

const handleSettingsSaved = (newSettings: CustomDomainBrand) => {
  brandSettings.value = newSettings;
  // You can add a success message or perform any other actions here
  console.log('Brand settings saved successfully');
};

onMounted(fetchBrandSettings);
</script>
