<template>
  <div class="container mx-auto mt-24 px-4">
    <div
      v-if="secretStore.record && secretStore.details"
      class="space-y-20"
    >
      <!-- Owner warnings -->
      <template v-if="!secretStore.record.verification">
        <div
          v-if="secretStore.details.is_owner && !secretStore.details.show_secret"
          class="mb-4 border-l-4 border-amber-400 bg-amber-50 p-4 text-amber-700 dark:border-amber-500 dark:bg-amber-900 dark:text-amber-100"
          role="alert"
        >
          <button
            type="button"
            class="float-right hover:text-amber-900 dark:hover:text-amber-50"
            @click="closeWarning"
            aria-label="Close warning"
          >
            &times;
          </button>
          <strong class="font-medium">{{ $t('web.COMMON.warning') }}</strong>
          {{ $t('web.shared.you_created_this_secret') }}
        </div>

        <div
          v-if="secretStore.details.is_owner && secretStore.details.show_secret"
          class="mb-4 border-l-4 border-brand-400 bg-brand-50 p-4 text-brand-700 dark:border-brand-500 dark:bg-brand-900 dark:text-brand-100"
          role="alert"
        >
          <button
            type="button"
            class="float-right hover:text-brand-900 dark:hover:text-brand-50"
            @click="closeWarning"
            aria-label="Close notification"
          >
            &times;
          </button>
          {{ $t('web.shared.viewed_own_secret') }}
        </div>
      </template>

      <div v-if="!secretStore.details.show_secret">
        <SecretConfirmationForm
          :secret-key="secretKey"
          :record="secretStore.record"
          :details="secretStore.details"
        />

        <div v-if="!secretStore.record.verification">
          <SecretRecipientOnboardingContent :display-powered-by="displayPoweredBy" />
        </div>
      </div>

      <div
        v-else
        class="space-y-4"
      >
        <h2 class="text-gray-600 dark:text-gray-400">
          {{ $t('web.shared.this_message_for_you') }}
        </h2>

        <SecretDisplayCase
          :secret="secretStore.record"
          :details="secretStore.details"
        />
      </div>
    </div>

    <UnknownSecret
      v-else
      :branded="false"
    />

    <div class="flex justify-center pt-16">
      <ThemeToggle />
    </div>
  </div>
</template>

<script setup lang="ts">
import SecretConfirmationForm from '@/components/secrets/canonical/SecretConfirmationForm.vue';
import SecretDisplayCase from '@/components/secrets/canonical/SecretDisplayCase.vue';
import SecretRecipientOnboardingContent from '@/components/secrets/SecretRecipientOnboardingContent.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useSecretsStore } from '@/stores/secretsStore';
import { computed, onMounted } from 'vue';

import UnknownSecret from './UnknownSecret.vue';

interface Props {
  secretKey: string;
  domainId: string | null;
  displayDomain: string;
  siteHost: string;
}

const props = defineProps<Props>();
const secretStore = useSecretsStore();

const displayPoweredBy = computed(() => !!(true));

const closeWarning = (event: Event) => {
  const element = event.target as HTMLElement;
  element.closest('.bg-amber-50, .bg-brand-50')?.remove();
};
</script>
