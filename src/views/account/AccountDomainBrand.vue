<template>
  <div>
    <DashboardTabNav />

    <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
      <div>
        <AccountDomainBrandForm
          v-if="!loading && !error"
          :brandSettings="brandSettings"
          @updateBrandSettings="updateBrandSettings"
        />
      </div>
      <div>
        <h2 class="text-2xl font-bold mb-4 text-gray-800 dark:text-gray-200">
          Preview
        </h2>
        <SecretPreview
          v-if="!loading && !error"
          :brandSettings="brandSettings"
          secretKey="abcd"
        />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import AccountDomainBrandForm from '@/components/account/AccountDomainBrandForm.vue';
import SecretPreview from '@/components/account/SecretPreview.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { BrandSettings } from '@/types/onetime';
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

const props = defineProps<{
  domain?: string;
}>();

const route = useRoute();
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
  console.debug('Brand settings updated', newSettings);
  if (showSuccessMessage) {
    success.value = 'Brand settings updated successfully';
  } else {
    success.value = null;
  }
};

// Fetch brand settings on component mount
onMounted(fetchBrandSettings);
</script>
