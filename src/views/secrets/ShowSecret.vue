<template>
  <div class="mt-24 container mx-auto px-4">
    <div v-if="record && details"
         class="space-y-20">
      <!-- Owner warning -->
      <div v-if="!record.verification && record.is_owner && !details.show_secret"
           class="bg-amber-50 border-l-4 border-amber-400 text-amber-700 p-4 mb-4 dark:bg-amber-900 dark:border-amber-500 dark:text-amber-100"
           role="alert">
        <button type="button"
                class="float-right hover:text-amber-900 dark:hover:text-amber-50"
                @click="closeWarning"
                aria-label="Close warning">
          &times;
        </button>
        <strong class="font-medium">{{ $t('web.COMMON.warning') }}</strong>
        {{ $t('web.shared.you_created_this_secret') }}
      </div>

      <!-- Owner viewed secret -->
      <div v-if="!record.verification && record.is_owner && details.show_secret"
           class="bg-brand-50 border-l-4 border-brand-400 text-brand-700 p-4 mb-4 dark:bg-brand-900 dark:border-brand-500 dark:text-brand-100"
           role="alert">
        <button type="button"
                class="float-right hover:text-brand-900 dark:hover:text-brand-50"
                @click="closeWarning"
                aria-label="Close notification">
          &times;
        </button>
        {{ $t('web.shared.viewed_own_secret') }}
      </div>

      <div v-if="!details.show_secret">
        <SecretConfirmationForm :secretKey="secretKey"
                                :record="record"
                                :details="details"
                                @secret-loaded="handleSecretLoaded" />

        <div v-if="!record.verification">
          <SecretRecipientOnboardingContent :displayPoweredBy="displayPoweredBy" />
        </div>
      </div>

      <div v-else
           class="space-y-4">
        <h2 class="text-gray-600 dark:text-gray-400">
          {{ $t('web.shared.this_message_for_you') }}
        </h2>

        <SecretDisplayCase :secret="record"
                           :details="details" />
      </div>
    </div>

    <UnknownSecret v-else />

    <div class="flex justify-center mt-12">
      <ThemeToggle />
    </div>
  </div>
</template>

<script setup lang="ts">
import SecretDisplayCase from '@/components/secrets/SecretDisplayCase.vue';
import SecretRecipientOnboardingContent from '@/components/secrets/SecretRecipientOnboardingContent.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { AsyncDataResult, SecretData, SecretDataApiResponse, SecretDetails } from '@/types/onetime';
import UnknownSecret from '@/views/secrets/UnknownSecret.vue';
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import SecretConfirmationForm from './SecretConfirmationForm.vue';

interface Props {
  secretKey: string;
}

defineProps<Props>();
const route = useRoute();

const initialData = computed(() => route.meta.initialData as AsyncDataResult<SecretDataApiResponse>);
const record = ref<SecretData | null>(initialData.value?.data?.record ?? null);
const details = ref<SecretDetails | null>(initialData.value?.data?.details ?? null);

const handleSecretLoaded = (data: { record: SecretData; details: SecretDetails; }) => {
  record.value = data.record;
  details.value = data.details;
};

const displayPoweredBy = computed(() => !!(true));

const closeWarning = (event: Event) => {
  const element = event.target as HTMLElement;
  element.closest('.bg-amber-50, .bg-brand-50')?.remove();
};
</script>
