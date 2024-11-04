<template>
  <div class="min-h-screen flex items-center justify-center px-4 py-12 sm:px-6 lg:px-8 bg-gray-50 dark:bg-gray-900">
    <div class="w-full max-w-md space-y-8">

      <!-- Add logo display -->
      <div v-if="logoImage" class="flex justify-center mb-8">
        <img
          :src="`data:${logoImage.content_type};base64,${logoImage.encoded}`"
          :alt="logoImage.filename || 'Brand logo'"
          class="h-16 w-16 object-contain"
          :class="{
            'rounded-lg': brandSettings?.corner_style === 'rounded',
            'rounded-full': brandSettings?.corner_style === 'pill',
            'rounded-none': brandSettings?.corner_style === 'square'
          }"
        />
      </div>

      <!-- Loading State -->
      <div v-if="isLoading"
           class="flex justify-center items-center">
        <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-brand-500"></div>
      </div>

      <div v-else-if="record && details">
        <!-- Secret Header -->
        <div class="flex items-center space-x-4 mb-8">
          <div class="h-12 w-12 rounded-full bg-brand-100 dark:bg-brand-900 flex items-center justify-center">
            <svg xmlns="http://www.w3.org/2000/svg"
                 class="h-6 w-6 text-brand-600 dark:text-brand-400"
                 fill="none"
                 viewBox="0 0 24 24"
                 stroke="currentColor">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <div>
            <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
              {{ $t('web.shared.this_message_for_you') }}
            </h2>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              {{ $t('web.COMMON.click_to_continue') }}
            </p>
          </div>
        </div>

        <!-- Secret Content -->
        <div v-if="!details.show_secret">
          <SecretConfirmationForm :secretKey="secretKey"
                                :record="record"
                                :details="details"
                                :branded="true"
                                @secret-loaded="handleSecretLoaded" />
        </div>

        <div v-else
             class="bg-white dark:bg-gray-800 rounded-lg shadow-xl p-8 space-y-4">
          <h2 class="text-gray-600 dark:text-gray-400">
            {{ $t('web.shared.this_message_for_you') }}
          </h2>

          <SecretDisplayCase :secret="record"
                           :details="details" />
        </div>
      </div>

      <!-- Unknown Secret -->
      <UnknownSecret v-else-if="!record"
                     :branded="true"
                     :brand-settings="brandSettings" />

      <div class="flex justify-center pt-16">
        <ThemeToggle />
      </div>

    </div>
  </div>
</template>

<style scoped>
.logo-container {
  transition: all 0.3s ease;
}

.logo-container img {
  max-width: 100%;
  height: auto;
}
</style>

<script setup lang="ts">
import SecretConfirmationForm from '@/components/secrets/SecretConfirmationForm.vue';
import SecretDisplayCase from '@/components/secrets/SecretDisplayCase.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import type { AsyncDataResult, BrandSettings, ImageProps, SecretData, SecretDataApiResponse, SecretDetails } from '@/types/onetime';
import { createApi } from '@/utils/api';
import UnknownSecret from '@/views/secrets/UnknownSecret.vue';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

interface Props {
  secretKey: string;
  domainStrategy: string;
  displayDomain: string;
  domainBranding: BrandSettings;
  siteHost: string;
}

const props = defineProps<Props>();
const route = useRoute();

const initialData = computed(() => route.meta.initialData as AsyncDataResult<SecretDataApiResponse>);

const finalRecord = ref<SecretData | null>(null);
const finalDetails = ref<SecretDetails | null>(null);

const {
  isSubmitting,
} = useFormSubmission({
  url: `/api/v2/secret/${props.secretKey}`,
  successMessage: '',
  onSuccess: (data: SecretDataApiResponse) => {
    finalRecord.value = data.record;
    finalDetails.value = data.details;
  },
  onError: (data: { message: string }) => {
    console.debug('Error fetching secret:', data.message);
    throw new Error(data.message);
  },
});

// Compute the current state based on initial and final data
const record = computed(() => finalRecord.value || (initialData?.value.data?.record ?? null));
const details = computed(() => finalDetails.value || (initialData?.value.data?.details ?? null));
const isLoading = computed(() => isSubmitting.value);

const handleSecretLoaded = (data: { record: SecretData; details: SecretDetails }) => {
  finalRecord.value = data.record;
  finalDetails.value = data.details;
};

// Watch for changes in the finalRecord and update the view accordingly
watch(finalRecord, (newValue) => {
  if (newValue) {
    console.log('Secret fetched successfully');
  }
});

// Add logo state
const logoImage = ref<ImageProps | null>(null);

// Modify the logo fetching function to use displayDomain
const fetchLogo = async () => {
  if (!props.displayDomain) return;
  const api = createApi({ domain: props.siteHost });
  try {
    const response = await api.get(`/api/v2/account/domains/${props.displayDomain}/logo`);
    if (response.data.success && response.data.record) {
      logoImage.value = response.data.record;
    }
  } catch (err) {
    console.error('Error fetching logo:', err);
  }
};

// Use the brand settings directly from props
const brandSettings = computed(() => props.domainBranding);

// Call fetchLogo when the component mounts
onMounted(() => {
  fetchLogo();
});
</script>
