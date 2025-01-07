<!-- BrandedShowSecret.vue -->
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
 import { useBranding } from '@/composables/useBranding';
 import UnknownSecret from './UnknownSecret.vue';

 interface Props {
   secretKey: string;
   domainId: string;
   displayDomain: string;
   siteHost: string;
 }

 const { brandSettings } = useBranding();

 defineProps<Props>();
 </script>

<template>
  <BaseShowSecret
    :secret-key="secretKey"
    :branded="true"
    class="flex min-h-screen items-center justify-center
      bg-gray-50 px-4 py-12 dark:bg-gray-900 sm:px-6 lg:px-8">
    <!-- Loading slot -->
    <template
      #loading="{}">
      <div class="flex justify-center">
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

    <!-- Header slot -->
    <template #header>
      <div class="w-full max-w-xl space-y-8">
        <!-- Header content if needed -->
      </div>
    </template>

    <!-- Confirmation slot -->
    <template #confirmation="{ secretKey, record, details }">
      <SecretConfirmationForm
        :secret-key="secretKey"
        :record="record"
        :details="details"
        :domain-id="domainId"
        :display-powered-by="true"
      />
    </template>

    <!-- Reveal slot -->
    <template #reveal="{ record, details }">
      <SecretDisplayCase
        :secret-key="secretKey"
        :record="record"
        :details="details"
        :domain-id="domainId"
        :display-powered-by="true"
      />
    </template>

    <!-- Unknown secret slot -->
    <template #unknown="{ }">
      <UnknownSecret
        :branded="true"
        :brand-settings="brandSettings"
      />
    </template>

    <!-- Footer slot -->
    <template #footer>
      <footer
        class="pt-20 text-center text-xs text-gray-400 dark:text-gray-600"
        role="contentinfo">
        <nav
          class="space-x-2"
          aria-label="Footer navigation">
          <a
            :href="`https://${siteHost}`"
            class="hover:underline
              focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
            rel="noopener noreferrer"
            aria-label="Visit Onetime Secret homepage">
            Powered by Onetime Secret
          </a>
          <span aria-hidden="true">·</span>
          <router-link
            to="/info/terms"
            class="hover:underline
              focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2"
            aria-label="View Terms of Service">
            Terms
          </router-link>
          <span aria-hidden="true">·</span>
          <router-link
            to="/info/privacy"
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
