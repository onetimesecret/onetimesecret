<template>
  <div class="min-h-screen flex items-center justify-center px-4 py-12 sm:px-6 lg:px-8 bg-gray-50 dark:bg-gray-900">
    <div class="w-full max-w-xl space-y-8">

      <!-- Loading State -->
      <div v-if="isLoading"
           class="flex justify-center items-center">
        <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-brand-500"></div>
      </div>

      <div v-else-if="record && details">

        <!-- Secret Content -->

        <SecretConfirmationForm v-if="!details.show_secret"
                                :secretKey="secretKey"
                                :record="record"
                                :details="details"
                                :domainId="domainId"
                                :domainBranding="domainBranding"
                                @secret-loaded="handleSecretLoaded" />


        <SecretDisplayCase v-else
                           :secretKey="secretKey"
                           :record="record"
                           :details="details"
                           :domainId="domainId"
                           :domainBranding="domainBranding" />

      </div>

      <!-- Unknown Secret -->
      <UnknownSecret v-else-if="!record"
                     :domainBranding="domainBranding" />

      <div class="flex justify-center pt-16">
        <ThemeToggle />
      </div>
      <div class="text-center pt-20 text-xs text-gray-400 dark:text-gray-600">
        <div class="space-x-2">
          <a :href="`https://${siteHost}`"
             class="hover:underline"
             rel="noopener noreferrer">
            Powered by Onetime Secret
          </a>
          <span>·</span>
          <router-link to="/info/terms"
                       class="hover:underline">Terms</router-link>
          <span>·</span>
          <router-link to="/info/privacy"
                       class="hover:underline">Privacy</router-link>
        </div>
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
import SecretConfirmationForm from '@/components/secrets/branded/SecretConfirmationForm.vue';
import SecretDisplayCase from '@/components/secrets/branded/SecretDisplayCase.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import type { AsyncDataResult, BrandSettings, SecretData, SecretDataApiResponse, SecretDetails } from '@/types/onetime';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import UnknownSecret from './UnknownSecret.vue';

interface Props {
  secretKey: string;
  domainStrategy: string;
  domainId: string;
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
  onError: (data: { message: string; }) => {
    console.debug('Error fetching secret:', data.message);
    throw new Error(data.message);
  },
});

// Compute the current state based on initial and final data
const record = computed(() => finalRecord.value || (initialData?.value.data?.record ?? null));
const details = computed(() => finalDetails.value || (initialData?.value.data?.details ?? null));
const isLoading = computed(() => isSubmitting.value);

const handleSecretLoaded = (data: { record: SecretData; details: SecretDetails; }) => {
  finalRecord.value = data.record;
  finalDetails.value = data.details;
};

// Watch for changes in the finalRecord and update the view accordingly
watch(finalRecord, (newValue) => {
  if (newValue) {
    console.log('Secret fetched successfully');
  }
});


</script>
