<template>
  <div>
    <DashboardTabNav />
    <DomainBrandView
      :heading="domainId"
      headingId="domain-brand"
      :logoPreview="logoPreview"
      :loading="loading"
      :error="error"
      :success="success"
      @retry="fetchBrandSettings"
    >
      <template #form>
        <AccountDomainBrandForm
          v-if="!loading && !error"
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

// Computed property for logo preview
const logoPreview = computed(() => {
  const { image_encoded, image_content_type } = brandSettings.value;
  return image_encoded && image_content_type
    ? `data:${image_content_type};base64,${image_encoded}`
    : null;
});

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
    const response = await fetch(`/api/v2/account/domains/${domainId.value.replace('Customize - ', '')}/brand`);
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
