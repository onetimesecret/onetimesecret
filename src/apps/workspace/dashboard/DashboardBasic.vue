<!-- src/apps/workspace/dashboard/DashboardBasic.vue -->

<!-- Basic dashboard for free tier users -->

<script setup lang="ts">
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import { WindowService } from '@/services/window.service';
  import { computed } from 'vue';

  const cust = WindowService.get('cust');

  // Show beta features if enabled
  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
