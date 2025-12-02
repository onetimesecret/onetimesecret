<!-- src/views/dashboard/DashboardBasic.vue -->
<!-- Basic dashboard for free tier users (no team capabilities) -->

<script setup lang="ts">
  import UpgradePrompt from '@/apps/workspace/components/billing/UpgradePrompt.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import { WindowService } from '@/services/window.service';
  import { computed } from 'vue';
  const cust = WindowService.get('cust');

  // Show beta features if enabled
  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);

  // Only show upgrade prompts in SaaS mode (billing enabled)
  const billingEnabled = computed(() => WindowService.get('billing_enabled') || false);
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <!-- Upgrade Prompt (SaaS only) -->
    <UpgradePrompt
      class="mb-8"
      capability="create_teams"
      upgrade-plan="team_v1" />

    <!-- Space divider -->
    <div class="mb-6"></div>

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
