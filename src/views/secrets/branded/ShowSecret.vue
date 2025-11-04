<!-- src/views/secrets/branded/ShowSecret.vue -->

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

  import BaseShowSecret from '@/components/base/BaseShowSecret.vue';
  import FooterAttribution from '@/components/layout/SecretFooterAttribution.vue';
  import FooterControls from '@/components/layout/SecretFooterControls.vue';
  import SecretConfirmationForm from '@/components/secrets/branded/SecretConfirmationForm.vue';
  import SecretDisplayCase from '@/components/secrets/branded/SecretDisplayCase.vue';
  import { useProductIdentity } from '@/stores/identityStore';

  import UnknownSecret from './UnknownSecret.vue';

  interface Props {
    secretIdentifier: string;
    domainId: string;
    displayDomain: string;
    siteHost: string;
  }

  const productIdentity = useProductIdentity();
  const brandSettings = productIdentity.brand; // Not reactive

  defineProps<Props>();
</script>

<template>
  <BaseShowSecret
    :secret-identifier="secretIdentifier"
    :branded="true"
    :site-host="siteHost"
    class="container mx-auto mt-24 px-4">
    <!-- Loading slot -->
    <template #loading="{}">
      <div class="flex justify-center">
        <!-- prettier-ignore-attribute class -->
        <div
          class="size-32 animate-spin
          rounded-full border-4 border-brand-500 border-t-transparent"></div>
      </div>
    </template>

    <!-- Error slot -->
    <template #error="{ error }">
      <div class="w-full max-w-xl rounded-lg bg-red-50 p-4 text-red-700">
        {{ error }}
      </div>
    </template>

    <!-- Confirmation slot -->
    <template #confirmation="{ record, details, error, isLoading, onConfirm }">
      <div
        :class="{
          'rounded-lg': brandSettings?.corner_style === 'rounded',
          'rounded-2xl': brandSettings?.corner_style === 'pill',
          'rounded-none': brandSettings?.corner_style === 'square',
          'mx-auto max-w-2xl space-y-20': true,
        }">
        <SecretConfirmationForm
          :secret-identifier="secretIdentifier"
          :record="record"
          :details="details"
          :domain-id="domainId"
          :error="error"
          :is-submitting="isLoading"
          @user-confirmed="onConfirm" />
      </div>
    </template>

    <!-- Reveal slot -->
    <template #reveal="{ record, details }">
      <div class="mx-auto w-full max-w-2xl">
        <SecretDisplayCase
          aria-labelledby="secret-heading"
          :secret-identifier="secretIdentifier"
          :record="record"
          :details="details"
          :domain-id="domainId"
          class="w-full" />
      </div>
    </template>

    <!-- Unknown secret slot -->
    <template #unknown="{}">
      <div class="mx-auto max-w-2xl">
        <UnknownSecret
          :branded="true"
          :brand-settings="brandSettings ?? undefined" />
      </div>
    </template>

    <!-- Footer slot -->
    <template #footer="{ }">
      <div class="flex flex-col items-center space-y-8 py-8">
        <FooterControls :show-language="true" />
        <FooterAttribution
          :site-host="siteHost"
          :show-nav="true"
          :show-terms="true" />
      </div>
    </template>
  </BaseShowSecret>
</template>

<style scoped>
  .logo-container {
  transition: all 0.3s ease;
}

.logo-container img {
  max-width: 100%;
  height: auto;
}

:focus {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}
</style>
