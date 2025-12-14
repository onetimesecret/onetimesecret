<!-- src/apps/workspace/dashboard/DashboardBasic.vue -->

<!-- Basic dashboard for free tier users (no team entitlements) -->

<script setup lang="ts">
  import UpgradePrompt from '@/apps/workspace/components/billing/UpgradePrompt.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import { WindowService } from '@/services/window.service';
  import { useEntitlements } from '@/shared/composables/useEntitlements';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';

  const cust = WindowService.get('cust');
  const organizationStore = useOrganizationStore();
  const { currentOrganization } = storeToRefs(organizationStore);

  // Entitlement checking
  const { can, ENTITLEMENTS } = useEntitlements(currentOrganization);

  // Show beta features if enabled
  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);

  // Only show upgrade prompt on dashboard if user has NO team capability at all.
  // If user has CREATE_TEAM (single) or CREATE_TEAMS (multiple), don't nag on dashboard.
  // The Teams page handles its own upgrade prompts contextually.
  const showTeamsUpgrade = computed(() => {
    // Don't show upgrade prompt if we haven't loaded org data yet
    if (!currentOrganization.value) return false;
    // If user can create at least one team, don't show upgrade on dashboard
    if (can(ENTITLEMENTS.CREATE_TEAM) || can(ENTITLEMENTS.CREATE_TEAMS)) return false;
    return true;
  });
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <!-- Upgrade Prompt - only shown if user lacks multi-team entitlement -->
    <UpgradePrompt
      v-if="showTeamsUpgrade"
      class="mb-8"
      entitlement="create_teams"
      upgrade-plan="multi_team_v1" />

    <!-- Space divider -->
    <div class="mb-6"></div>

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
