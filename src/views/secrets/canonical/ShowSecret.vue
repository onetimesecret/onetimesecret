<script setup lang="ts">
/**
 * Core OneTimeSecret implementation that uses distinct layouts for confirmation
 * and reveal states to optimize for marketing and user acquisition.
 *
 * This component deliberately uses different UIs:
 * 1. Confirmation: Marketing-focused layout with onboarding content
 * 2. Reveal: Simplified secret display focused on content delivery
 *
 * Unlike the branded implementation, this does not use BaseSecretDisplay for confirmation
 * state to allow for richer marketing content placement.
 *
 * @see SecretConfirmationForm - Marketing-optimized confirmation layout
 * @see SecretDisplayCase - Simplified secret reveal display
 */
import SecretConfirmationForm from '@/components/secrets/canonical/SecretConfirmationForm.vue';
import SecretDisplayCase from '@/components/secrets/canonical/SecretDisplayCase.vue';
import SecretRecipientOnboardingContent from '@/components/secrets/SecretRecipientOnboardingContent.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { Secret, SecretDetails } from '@/schemas/models';
import { AsyncDataResult, SecretRecordApiResponse } from '@/types';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';

import UnknownSecret from './UnknownSecret.vue';

interface Props {
  secretKey: string;
  domainId: string | null;
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

const submissionStatus = ref<{
  status: 'idle' | 'submitting' | 'success' | 'error';
  message?: string;
}>({
  status: 'idle'
});

const handleSubmissionStatus = (status: { status: string; message?: string }) => {
  submissionStatus.value = status as typeof submissionStatus.value;
};

// Watch for changes in the finalRecord and update the view accordingly
watch(finalRecord, (newValue) => {
  if (newValue) {
    console.log('Secret fetched successfully');
  }
});

const closeWarning = (event: Event) => {
  const element = event.target as HTMLElement;
  const warning = element.closest('.bg-amber-50, .bg-brand-50');
  if (warning) {
    warning.remove();
    // Announce removal to screen readers
    const announcement = document.createElement('div');
    announcement.setAttribute('role', 'status');
    announcement.setAttribute('aria-live', 'polite');
    announcement.textContent = 'Warning dismissed';
    document.body.appendChild(announcement);
    setTimeout(() => announcement.remove(), 1000);
  }
};
</script>

<template>
  <main
    class="container mx-auto mt-24 px-4"
    role="main"
    aria-label="Secret viewing page">
    <div
      v-if="record && details"
      class="space-y-20">
      <!-- Owner warnings -->
      <template v-if="!record.verification">
        <div
          v-if="details.is_owner && !details.show_secret"
          class="mb-4 border-l-4 border-amber-400 bg-amber-50 p-4
            text-amber-700 dark:border-amber-500 dark:bg-amber-900 dark:text-amber-100"
          role="alert"
          aria-live="polite">
          <button
            type="button"
            class="float-right hover:text-amber-900 focus:outline-none
              focus:ring-2 focus:ring-amber-500 dark:hover:text-amber-50"
            @click="closeWarning"
            aria-label="Dismiss warning">
            <span aria-hidden="true">&times;</span>
          </button>
          <strong class="font-medium">{{ $t('web.COMMON.warning') }}:</strong>
          {{ $t('web.shared.you_created_this_secret') }}
        </div>

        <div
          v-if="details.is_owner && details.show_secret"
          class="mb-4 border-l-4 border-brand-400 bg-brand-50 p-4
            text-brand-700 dark:border-brand-500 dark:bg-brand-900 dark:text-brand-100"
          role="alert"
          aria-live="polite">
          <button
            type="button"
            class="float-right hover:text-brand-900 focus:outline-none
              focus:ring-2 focus:ring-brand-500 dark:hover:text-brand-50"
            @click="closeWarning"
            aria-label="Dismiss notification">
            <span aria-hidden="true">&times;</span>
          </button>
          {{ $t('web.shared.viewed_own_secret') }}
        </div>
      </template>

      <div v-if="!details.show_secret">
        <SecretConfirmationForm
          :secretKey="secretKey"
          :record="record"
          :details="details"
          :domainId="domainId"
          :submissionStatus="submissionStatus"
          @secret-loaded="handleSecretLoaded"
          @submission-status="handleSubmissionStatus"
        />

        <div v-if="!record.verification">
          <SecretRecipientOnboardingContent
            :displayPoweredBy="true"
          />
        </div>
      </div>

      <div
        v-if="details.show_secret"
        class="space-y-4">
        <h2
          class="text-brand-600 dark:text-brand-100"
          id="secret-heading">
          {{ $t('web.shared.this_message_for_you') }}
        </h2>

        <SecretDisplayCase
          :displayPoweredBy="true"
          :record="record"
          :details="details"
          :submissionStatus="submissionStatus"
          aria-labelledby="secret-heading"
          @secret-loaded="handleSecretLoaded"
          @submission-status="handleSubmissionStatus"
        />
      </div>
    </div>

    <!-- Unknown Secret -->
    <UnknownSecret v-else-if="!record" :branded="false" />

    <div class="flex justify-center pt-16">
      <ThemeToggle />
    </div>
  </main>
</template>

<style scoped>
/* Ensure focus outline is visible in all color schemes */
:focus {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}
</style>
