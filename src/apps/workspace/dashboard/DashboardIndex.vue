<!-- src/apps/workspace/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import PrivacyOptionsBar from '@/apps/workspace/components/forms/PrivacyOptionsBar.vue';
  import WorkspaceSecretForm from '@/apps/workspace/components/forms/WorkspaceSecretForm.vue';
  import UpgradeBanner from '@/apps/workspace/dashboard/components/UpgradeBanner.vue';
  import { useDomainContext } from '@/shared/composables/useDomainContext';
  import { computed, ref } from 'vue';

  // Domain context management
  const { isContextActive } = useDomainContext();

  // Form ref for accessing exposed state
  const secretFormRef = ref<InstanceType<typeof WorkspaceSecretForm> | null>(null);

  // Recent secrets table ref for refreshing after creation
  const recentSecretsTableRef = ref<InstanceType<typeof RecentSecretsTable> | null>(null);

  // Computed values that read from form's exposed state
  const currentTtl = computed(() => secretFormRef.value?.currentTtl ?? 604800);
  const currentPassphrase = computed(() => secretFormRef.value?.currentPassphrase ?? '');
  const isSubmitting = computed(() => secretFormRef.value?.isSubmitting ?? false);

  // Handlers for privacy options updates
  const handleTtlUpdate = (value: number) => {
    secretFormRef.value?.updateTtl(value);
  };

  const handlePassphraseUpdate = (value: string) => {
    secretFormRef.value?.updatePassphrase(value);
  };

  // Refresh recent secrets table after a secret is created
  const handleSecretCreated = () => {
    recentSecretsTableRef.value?.fetch();
  };
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
    <!-- Upgrade Banner (shown for free plan users when billing is enabled) -->
    <UpgradeBanner />

    <!-- Privacy Options Bar (interactive chips for TTL and passphrase) -->
    <PrivacyOptionsBar
      v-if="isContextActive"
      :current-ttl="currentTtl"
      :current-passphrase="currentPassphrase"
      :is-submitting="isSubmitting"
      class="mb-6 rounded-lg"
      @update:ttl="handleTtlUpdate"
      @update:passphrase="handlePassphraseUpdate" />

    <WorkspaceSecretForm
      ref="secretFormRef"
      class="mb-12"
      @created="handleSecretCreated" />

    <RecentSecretsTable
      ref="recentSecretsTableRef"
      :show-workspace-mode-toggle="false" />
  </div>
</template>
