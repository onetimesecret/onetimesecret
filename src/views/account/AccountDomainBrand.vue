<template>
  <div>
    <DashboardTabNav />
    <DomainBrandView :heading="domainId" headingId="domain-brand" :logoPreview="logoPreview">
      <template #form>
        <div v-if="loading" class="flex justify-center items-center h-64">
          <div class="animate-spin rounded-full h-16 w-16 border-t-2 border-b-2 border-brand-600 dark:border-brand-400"></div>
        </div>
        <div v-else-if="error" class="text-center p-8 bg-red-100 dark:bg-red-900 rounded-lg">
          <p class="text-red-700 dark:text-red-300">{{ error }}</p>
          <button @click="fetchBrandSettings" class="mt-4 px-4 py-2 bg-brand-500 text-white rounded hover:bg-brand-600 dark:bg-brand-600 dark:hover:bg-brand-700 transition duration-300 ease-in-out focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:focus:ring-offset-gray-800">
            Retry
          </button>
        </div>
        <AccountDomainBrandForm
          v-else
          :brandSettings="brandSettings"
          @updateBrandSettings="updateBrandSettings"
        />
      </template>
    </DomainBrandView>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { useRoute } from 'vue-router';
import DomainBrandView from '@/components/account/DomainBrandView.vue';
import AccountDomainBrandForm from '@/components/account/AccountDomainBrandForm.vue';
import { BrandSettings } from '@/types/onetime';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
const props = defineProps<{
  domain?: string;
}>();

const route = useRoute();
const domainId = computed(() => `Customize - ${props.domain || route.params.domain as string}`);

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

const logoPreview = computed(() => {
  if (brandSettings.value.image_encoded && brandSettings.value.image_content_type) {
    return `data:${brandSettings.value.image_content_type};base64,${brandSettings.value.image_encoded}`;
  }
  return null;
});

const fetchBrandSettings = async () => {
  loading.value = true;
  error.value = null;
  try {
    const response = await fetch(`/api/v2/account/domains/${domainId.value.replace('Customize - ', '')}/brand`);
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
