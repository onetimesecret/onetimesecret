<!-- src/apps/secret/reveal/branded/ShowSecret.vue -->

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

  import BrandedHero from '@/apps/secret/components/branded/BrandedHero.vue';
  import SecretConfirmationForm from '@/apps/secret/components/branded/SecretConfirmationForm.vue';
  import SecretDisplayCase from '@/apps/secret/components/branded/SecretDisplayCase.vue';
  import FooterAttribution from '@/apps/secret/components/layout/SecretFooterAttribution.vue';
  import BaseShowSecret from '@/shared/components/base/BaseShowSecret.vue';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { storeToRefs } from 'pinia';

  import UnknownSecret from './UnknownSecret.vue';

  interface Props {
    secretIdentifier: string;
    domainId: string;
    displayDomain: string;
    siteHost: string;
  }

  const productIdentity = useProductIdentity();
  // Reactive ref: brand settings can arrive after mount (bootstrap
  // re-hydration), so a plain property read here would freeze the
  // pre-brand snapshot into the corner/font bindings below.
  const { brand: brandSettings, cornerClass } = storeToRefs(productIdentity);

  defineProps<Props>();
</script>

<template>
  <BaseShowSecret
    :secret-identifier="secretIdentifier"
    :branded="true"
    :site-host="siteHost"
    class="container mx-auto px-4">
    <!--
      No #loading slot: BaseShowSecret renders its own <SecretSkeleton> for the
      secret fetch (see BaseShowSecret template). A #loading slot here never
      rendered (the base has no <slot name="loading">), so the old spinner was
      dead markup.

      The brand logo is rendered INSIDE the confirmation/reveal content (stacked
      above the card via BrandedHero), not in BaseShowSecret's #header slot.
      #header is a separate grid row; filling it turns the base's 3-row stretch
      grid into three occupied rows and steals the empty trailing row that
      balances the card-to-footer gap — the footer then either glues to the card
      or (with a 1fr override) pins to the viewport bottom. Keeping the logo in
      the content row preserves the original, moderate footer spacing.
    -->

    <!-- Error slot -->
    <template #error="{ error }">
      <div class="w-full max-w-xl rounded-lg bg-red-50 p-4 text-red-700">
        {{ error }}
      </div>
    </template>

    <!-- Confirmation slot -->
    <template #confirmation="{ record, details, error, isLoading, onConfirm }">
      <div :class="[cornerClass, 'mx-auto max-w-2xl']">
        <!-- Brand logo above the case, matching homepage/create/receipt. Logo
             only — the case owns its own "You have a message" heading. -->
        <BrandedHero
          logo-link-to="/"
          class="mb-8" />
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
        <BrandedHero
          logo-link-to="/"
          class="mb-8" />
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
        <FooterAttribution
          :site-host="siteHost"
          :show-nav="true"
          :show-terms="true" />
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
