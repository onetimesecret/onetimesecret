<script setup lang="ts">
/**
 * Branded secret display implementation that maintains consistent UI between confirmation
 * and reveal states by leveraging BaseSecretDisplay for both.
 *
 * This component handles secrets for custom domains, ensuring brand consistency by:
 * 1. Using identical layouts for both confirmation and reveal states
 * 2. Applying domain-specific styling (colors, fonts, corner styles)
 * 3. Displaying branded logos when available
 *
 * @see SecretConfirmationForm - Handles passphrase entry using BaseSecretDisplay
 * @see SecretDisplayCase - Displays revealed content using BaseSecretDisplay
 */

import ThemeToggle from '@/components/ThemeToggle.vue';
import type { Secret, SecretDetails } from '@/schemas/models';
import { AsyncDataResult, SecretRecordApiResponse } from '@/types/api';
import { computed, ref, watch, defineAsyncComponent } from 'vue';
import { useRoute } from 'vue-router';

import UnknownSecret from './UnknownSecret.vue';

// Import components that will be used in dynamic component rendering
const SecretConfirmationForm = defineAsyncComponent(() => import('@/components/secrets/branded/SecretConfirmationForm.vue'));
const SecretDisplayCase = defineAsyncComponent(() => import('@/components/secrets/branded/SecretDisplayCase.vue'));

interface Props {
  secretKey: string;
  domainId: string;
  displayDomain: string;
  siteHost: string;
}

defineProps<Props>();
const route = useRoute();

const initialData = computed(() => route.meta.initialData as AsyncDataResult<SecretRecordApiResponse>);

const finalRecord = ref<Secret | null>(null);
const finalDetails = ref<SecretDetails | null>(null);

// Compute the current state based on initial and final data
const record = computed(() => finalRecord.value || (initialData?.value.data?.record ?? null));
const details = computed(() => finalDetails.value || (initialData?.value.data?.details ?? null));

const handleSecretLoaded = (data: { record: Secret; details: SecretDetails; }) => {
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

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4 py-12 dark:bg-gray-900 sm:px-6 lg:px-8">
    <div class="w-full max-w-xl space-y-8">

      <div v-if="record && details">
        <!-- Secret Content -->

        <component
          :is="details.show_secret ? SecretDisplayCase : SecretConfirmationForm"
          :secretKey="secretKey"
          :record="record"
          :details="details"
          :domainId="domainId"
          :displayPoweredBy="true"
          @secret-loaded="handleSecretLoaded"
        />
      </div>

      <!-- Unknown Secret -->
      <UnknownSecret v-else-if="!record" :branded="true" />

      <div class="flex justify-center pt-16">
        <ThemeToggle />
      </div>

      <div class="pt-20 text-center text-xs text-gray-400 dark:text-gray-600">
        <div class="space-x-2">
          <a
            :href="`https://${siteHost}`"
            class="hover:underline"
            rel="noopener noreferrer">
            Powered by Onetime Secret
          </a>
          <span>·</span>
          <router-link
            to="/info/terms"
            class="hover:underline">
            Terms
          </router-link>
          <span>·</span>
          <router-link
            to="/info/privacy"
            class="hover:underline">
            Privacy
          </router-link>
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
