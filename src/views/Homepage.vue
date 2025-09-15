<!-- src/views/Homepage.vue -->

<script setup lang="ts">
  import HomepageTaglines from '@/components/HomepageTaglines.vue';
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import RecentSecretsTable from '@/components/secrets/RecentSecretsTable.vue';
  import { WindowService } from '@/services/window.service';

  const windowProps = WindowService.getMultiple([
    'authenticated',
    'authentication',
    'plans_enabled',
    'ui',
  ]);

</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-4">
    <HomepageTaglines
      v-if="!windowProps.authenticated"
      class="mb-6" />

    <SecretForm
      v-if="windowProps.ui?.enabled !== false"
      class="mb-12"
      :with-recipient="false"
      :with-asterisk="true"
      :with-generate="true" />

    <!-- Space divider -->
    <div class="mb-6 "></div>

    <RecentSecretsTable
      v-if="false" />
  </div>
</template>
