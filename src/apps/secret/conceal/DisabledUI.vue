<!-- src/apps/secret/conceal/DisabledUI.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import DisabledHomepageTaglines from '@/apps/secret/components/conceal/DisabledHomepageTaglines.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { storeToRefs } from 'pinia';

  const { t } = useI18n();

  const bootstrapStore = useBootstrapStore();
  const { ui } = storeToRefs(bootstrapStore);

</script>

<template>
  <div class="flex min-h-screen flex-col items-center justify-center px-4">
    <div class="container mx-auto min-w-[320px] max-w-2xl">
      <!--

      Purpose: Landing page for self-hosted installs when UI is configured to be disabled.

      This page serves two key functions:
      1. Shows the current availability status of the secure messaging service
      2. Provides context for recipients who follow links to the domain

      Key audiences:
      - Recipients: People who received/viewed a secure message and are curious about the service
      - Internal teams: Company employees who need to know how to share sensitive info
      - Admins: People managing the service who need to understand its current state

      Design notes:
      - Maintains professional appearance even when disabled
      - Uses company branding while keeping security/trust as primary focus
      - Messaging must work for all audiences simultaneously since authentication state is unknown
      -->
      <DisabledHomepageTaglines
        :tagline1="t('web.homepage.disabled.tagline1')"
        :tagline2="t('web.homepage.disabled.tagline2')"
        v-if="!ui?.enabled"
        class="mb-6" />

      <!-- Space divider -->
      <div class="mb-6 "></div>
    </div>
  </div>
</template>
