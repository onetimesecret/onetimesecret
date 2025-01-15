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
 import SecretConfirmationForm from '@/components/secrets/branded/SecretConfirmationForm.vue';
 import SecretDisplayCase from '@/components/secrets/branded/SecretDisplayCase.vue';
 import ThemeToggle from '@/components/ThemeToggle.vue';
 import { useProductIdentity } from '@/stores/identityStore';
 import UnknownSecret from './UnknownSecret.vue';

 interface Props {
   secretKey: string;
   domainId: string;
   displayDomain: string;
   siteHost: string;
 }

 const productIdentity = useProductIdentity();
 const brandSettings = productIdentity.brand; // Not reactive

 defineProps<Props>();
 </script>

<template>
  <BaseShowSecret :secret-key="secretKey"
                  :branded="true"
                  class="container mx-auto mt-24 px-4">

    <!-- Loading slot -->
    <template #loading="{}">
      <div class="flex justify-center">
        <div class="size-32 animate-spin
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
    <template #confirmation="{ secretKey, record, details }">
      <div
        :class="{
          'rounded-lg': brandSettings?.corner_style === 'rounded',
          'rounded-2xl': brandSettings?.corner_style === 'pill',
          'rounded-none': brandSettings?.corner_style === 'square',
          'mx-auto max-w-2xl space-y-20': true,
        }"
        >
        <SecretConfirmationForm :secret-key="secretKey"
                                :record="record"
                                :details="details"
                                :domain-id="domainId"
                                :display-powered-by="true" />
      </div>
    </template>

    <!-- Reveal slot -->
    <template #reveal="{ record, details }">
      <div class="mx-auto max-w-2xl w-full">

        <SecretDisplayCase aria-labelledby="secret-heading"
                           :secret-key="secretKey"
                           :record="record"
                           :details="details"
                           :domain-id="domainId"
                           :display-powered-by="true"
                           class="w-full" />
      </div>
    </template>

    <!-- Unknown secret slot -->
    <template #unknown="{ }">
      <div class="mx-auto max-w-2xl">
        <UnknownSecret :branded="true"
                       :brand-settings="brandSettings ?? undefined" />
      </div>
    </template>

    <!-- Footer slot -->
    <template #footer>
      <div class="mx-auto max-w-2xl">
        <footer class="pt-20 text-center text-xs text-gray-400 dark:text-gray-600"
                role="contentinfo">
          <nav class="space-x-2"
               aria-label="Footer navigation">
            <a :href="`https://${siteHost}`"
               class="hover:underline
                focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
               rel="noopener noreferrer"
               aria-label="Visit Onetime Secret homepage">
              Powered by Onetime Secret
            </a>
            <span aria-hidden="true">·</span>
            <router-link to="/info/terms"
                         class="hover:underline
                focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
                         aria-label="View Terms of Service">
              Terms
            </router-link>
            <span aria-hidden="true">·</span>
            <router-link to="/info/privacy"
                         class="hover:underline
                focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
                         aria-label="View Privacy Policy">
              Privacy
            </router-link>
          </nav>
        </footer>

        <div class="flex justify-center pt-16">
          <ThemeToggle />
        </div>
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
