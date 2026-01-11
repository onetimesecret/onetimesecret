<!-- src/apps/workspace/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import PrivacyOptionsBar from '@/apps/workspace/components/domains/PrivacyOptionsBar.vue';
  import WorkspaceSecretForm from '@/apps/workspace/components/forms/WorkspaceSecretForm.vue';
  import UpgradeBanner from '@/apps/workspace/dashboard/components/UpgradeBanner.vue';
  import { useDomainScope } from '@/shared/composables/useDomainScope';
  import { WindowService } from '@/services/window.service';
  import { computed, ref } from 'vue';

  const cust = WindowService.get('cust');
  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);

  // Domain scope management
  const { isScopeActive } = useDomainScope();

  // Form ref for accessing exposed state
  const secretFormRef = ref<InstanceType<typeof WorkspaceSecretForm> | null>(null);

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
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-4xl px-4">
    <!-- Upgrade Banner (shown for free plan users when billing is enabled) -->
    <UpgradeBanner />

    <!-- Privacy Options Bar (interactive chips for TTL and passphrase) -->
    <PrivacyOptionsBar
      v-if="isScopeActive"
      :current-ttl="currentTtl"
      :current-passphrase="currentPassphrase"
      :is-submitting="isSubmitting"
      class="mb-6 rounded-lg"
      @update:ttl="handleTtlUpdate"
      @update:passphrase="handlePassphraseUpdate" />

    <WorkspaceSecretForm
      ref="secretFormRef"
      class="mb-12" />

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
