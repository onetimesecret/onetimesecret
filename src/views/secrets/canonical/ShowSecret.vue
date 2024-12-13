<script setup lang="ts">
import SecretConfirmationForm from '@/components/secrets/canonical/SecretConfirmationForm.vue';
import SecretDisplayCase from '@/components/secrets/canonical/SecretDisplayCase.vue';
import SecretRecipientOnboardingContent from '@/components/secrets/SecretRecipientOnboardingContent.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
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

const props = defineProps<Props>();
const route = useRoute();

const initialData = computed(() => route.meta.initialData as AsyncDataResult<SecretRecordApiResponse>);

const finalRecord = ref<Secret | null>(null);
const finalDetails = ref<SecretDetails | null>(null);

const {
  isSubmitting,
} = useFormSubmission({
  url: `/api/v2/secret/${props.secretKey}`,
  successMessage: '',
  onSuccess: (data: SecretRecordApiResponse) => {
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

const closeWarning = (event: Event) => {
  const element = event.target as HTMLElement;
  element.closest('.bg-amber-50, .bg-brand-50')?.remove();
};
</script>

<template>
  <div class="container mx-auto mt-24 px-4">

    <!-- Loading State -->
    <div
      v-if="isLoading"
      class="flex items-center justify-center">
      <div class="size-12 animate-spin rounded-full border-y-2 border-brand-500"></div>
    </div>

    <div
      v-if="record && details"
      class="space-y-20">
      <!-- Owner warnings -->
      <template v-if="!record.verification">
        <div
          v-if="details.is_owner && !details.show_secret"
          class="mb-4 border-l-4 border-amber-400 bg-amber-50 p-4 text-amber-700 dark:border-amber-500 dark:bg-amber-900 dark:text-amber-100"
          role="alert">
          <button
            type="button"
            class="float-right hover:text-amber-900 dark:hover:text-amber-50"
            @click="closeWarning"
            aria-label="Close warning">
            &times;
          </button>
          <strong class="font-medium">{{ $t('web.COMMON.warning') }}</strong>
          {{ $t('web.shared.you_created_this_secret') }}
        </div>

        <div
          v-if="details.is_owner && details.show_secret"
          class="mb-4 border-l-4 border-brand-400 bg-brand-50 p-4 text-brand-700 dark:border-brand-500 dark:bg-brand-900 dark:text-brand-100"
          role="alert">
          <button
            type="button"
            class="float-right hover:text-brand-900 dark:hover:text-brand-50"
            @click="closeWarning"
            aria-label="Close notification">
            &times;
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
          @secret-loaded="handleSecretLoaded"
        />

        <div v-if="!record.verification">
          <SecretRecipientOnboardingContent
            :displayPoweredBy="true"
          />
        </div>
      </div>

      <div
        v-else
        class="space-y-4">
        <h2 class="text-gray-600 dark:text-gray-400">
          {{ $t('web.shared.this_message_for_you') }}
        </h2>

        <SecretDisplayCase
          :displayPoweredBy="true"
          :record="record"
          :details="details"
        />
      </div>
    </div>

    <!-- Unknown Secret -->
    <UnknownSecret v-else-if="!record" :branded="false" />

    <div class="flex justify-center pt-16">
      <ThemeToggle />
    </div>
  </div>
</template>
