<!-- ShowSecret.vue -->
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
  import BaseShowSecret, { type Props } from '@/components/base/BaseShowSecret.vue';
  import SecretConfirmationForm from '@/components/secrets/canonical/SecretConfirmationForm.vue';
  import SecretDisplayCase from '@/components/secrets/canonical/SecretDisplayCase.vue';
  import SecretRecipientOnboardingContent from '@/components/secrets/SecretRecipientOnboardingContent.vue';
  import ThemeToggle from '@/components/ThemeToggle.vue';
  import LanguageToggle from '@/components/LanguageToggle.vue';

  import UnknownSecret from './UnknownSecret.vue';

  defineProps<Props>();

  const closeWarning = (event: Event) => {
    const element = event.target as HTMLElement;
    const warning = element.closest('.bg-amber-50, .bg-brand-50');
    if (warning) {
      warning.remove();
    }
  };
</script>

<template>
  <BaseShowSecret
    :secret-key="secretKey"
    :branded="false"
    class="container mx-auto mt-24 px-4">
    <!-- Loading slot -->
    <template #loading="{}">
      <div class="flex justify-center">
        <div
          class="size-32 animate-spin rounded-full border-4 border-brand-500 border-t-transparent"></div>
      </div>
    </template>

    <!-- Error slot -->
    <template #error="{ error }">
      <div class="rounded-lg border-l-4 border-red-500 bg-red-50 p-4 text-red-700">
        {{ error }}
      </div>
    </template>

    <!-- Alerts slot -->
    <template #alerts="{ record, isOwner, showSecret }">
      <template v-if="!record.verification">
        <div
          v-if="isOwner && !showSecret"
          class="mb-4 border-l-4 border-amber-400 bg-amber-50 p-4 text-amber-700 dark:border-amber-500 dark:bg-amber-900 dark:text-amber-100"
          role="alert"
          aria-live="polite">
          <button
            type="button"
            class="float-right hover:text-amber-900 focus:outline-none focus:ring-2 focus:ring-amber-500 dark:hover:text-amber-50"
            @click="closeWarning"
            :aria-label="$t('dismiss-warning')">
            <span aria-hidden="true">&times;</span>
          </button>
          <strong class="font-medium">{{ $t('web.COMMON.warning') }}:</strong>
          {{ $t('web.shared.you_created_this_secret') }}
        </div>

        <div
          v-if="isOwner && showSecret"
          class="mb-4 border-l-4 border-brand-400 bg-brand-50 p-4 text-brand-700 dark:border-brand-500 dark:bg-brand-900 dark:text-brand-100"
          role="alert"
          aria-live="polite">
          <button
            type="button"
            class="float-right hover:text-brand-900 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:hover:text-brand-50"
            @click="closeWarning"
            :aria-label="$t('dismiss-notification')">
            <span aria-hidden="true">&times;</span>
          </button>
          {{ $t('web.shared.viewed_own_secret') }}
        </div>
      </template>
    </template>

    <!-- Confirmation slot -->
    <template #confirmation="{ record, details, error, isLoading, onConfirm }">
      <div class="mx-auto max-w-2xl space-y-20">
        <SecretConfirmationForm
          :secret-key="secretKey"
          :record="record"
          :details="details"
          :error="error"
          :is-submitting="isLoading"
          @user-confirmed="onConfirm" />
      </div>
    </template>

    <!-- Onboarding slot -->
    <template #onboarding="{ record }">
      <div v-if="!record.verification">
        <SecretRecipientOnboardingContent :display-powered-by="true" />
      </div>
    </template>

    <!-- Reveal slot -->
    <template #reveal="{ record, details }">
      <div class="space-y-4">
        <h2
          class="text-brand-600 dark:text-brand-100"
          id="secret-heading">
          {{ $t('web.shared.this_message_for_you') }}
        </h2>

        <SecretDisplayCase
          aria-labelledby="secret-heading"
          class="w-full"
          :display-powered-by="true"
          :record="record"
          :details="details" />
      </div>
    </template>

    <!-- Unknown secret slot -->
    <template #unknown="{ branded }">

      <UnknownSecret :branded="branded" />
    </template>

    <!-- Footer slot -->
    <template #footer="{}">
      <div class="flex justify-center pt-16">
        <ThemeToggle />
        <LanguageToggle :compact="true" />
      </div>
    </template>
  </BaseShowSecret>
</template>

<style scoped>
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
