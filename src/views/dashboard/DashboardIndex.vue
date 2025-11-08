<!-- src/views/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import RecentSecretsTable from '@/components/secrets/RecentSecretsTable.vue';
  import { WindowService } from '@/services/window.service';
  import { computed } from 'vue';

  const cust = WindowService.get('cust');

  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">

    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <!-- Space divider -->
    <div class="mb-6"></div>

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
