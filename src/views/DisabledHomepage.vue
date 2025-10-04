<!-- src/views/DisabledHomepage.vue -->

<script setup lang="ts">
  import DisabledHomepageTaglines from '@/components/DisabledHomepageTaglines.vue';
  import { WindowService } from '@/services/window.service';

  const windowProps = WindowService.getMultiple([
    'authenticated',
    'authentication',
    'ui',
  ]);

</script>

<template>
  <div class="min-h-screen flex flex-col justify-center items-center px-4">
    <div class="container mx-auto min-w-[320px] max-w-2xl">
      <!--

      Purpose: Landing page for self-hosted installs when UI is configured to be disabled
      OR when UI is enabled but homepage secret form is disabled unless logged in.

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
        :tagline1="$t('web.homepage.authonly.tagline1')"
        :tagline2="$t('web.homepage.authonly.tagline2')"
        v-if="!windowProps.ui?.enabled"
        class="mb-6" />

      <!-- Space divider -->
      <div class="mb-6 "></div>
    </div>
  </div>
</template>
