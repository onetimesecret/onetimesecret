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
import { useSecret } from '@/composables/useSecret';
// import { useValidatedWindowProp } from '@/composables/useWindowProps';
import { onMounted, Ref } from 'vue';
import { onBeforeRouteUpdate } from 'vue-router';

import UnknownSecret from './UnknownSecret.vue';

interface Props {
  secretKey: string;
}

const props = defineProps<Props>();

const { record, details, isLoading, error, load, reveal } = useSecret(props.secretKey);

// const domain_strategy = useValidatedWindowProp('domain_strategy', z.string());
// const display_domain = useValidatedWindowProp('display_domain', z.string());
// const domainId = useValidatedWindowProp('domain_id', z.string());
// const siteHost = useValidatedWindowProp('site_host', z.string());

const handleUserConfirmed = (passphrase: Ref) => {
  console.debug('[ShowSecret] User confirmed', typeof(passphrase));
  reveal(passphrase);
};

onBeforeRouteUpdate((to, from, next) => {
  console.debug('[ShowSecret] Loading secret', to.params.secretKey);
  load();
  next();
});

onMounted(() => {
  console.debug('[ShowSecret] Loading secret', props.secretKey);
  load();
});

const closeWarning = (event: Event) => {
  const element = event.target as HTMLElement;
  const warning = element.closest('.bg-amber-50, .bg-brand-50');
  if (warning) {
    warning.remove();
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
          :secret-key="secretKey"
          :record="record"
          :details="details"
          :error="error"
          :is-submitting="isLoading"
          @user-confirmed="handleUserConfirmed"
        />

        <div v-if="!record.verification">
          <SecretRecipientOnboardingContent
            :display-powered-by="true"
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
          aria-labelledby="secret-heading"
          :display-powered-by="true"
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
  </main>
</template>

<style scoped>
/* Ensure focus outline is visible in all color schemes */
:focus {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}
</style>
