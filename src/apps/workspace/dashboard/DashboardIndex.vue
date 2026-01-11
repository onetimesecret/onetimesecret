<!-- src/apps/workspace/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import PrivacyDefaultsBar from '@/apps/workspace/components/domains/PrivacyDefaultsBar.vue';
  import UpgradeBanner from '@/apps/workspace/dashboard/components/UpgradeBanner.vue';
  import { useWorkspacePrivacyDefaults } from '@/apps/workspace/composables/useWorkspacePrivacyDefaults';
  import { useDomainScope } from '@/shared/composables/useDomainScope';
  import { useBranding } from '@/shared/composables/useBranding';
  import { WindowService } from '@/services/window.service';
  import type { BrandSettings } from '@/schemas/models';
  import { computed, onMounted, ref, watch } from 'vue';

  const cust = WindowService.get('cust');
  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);

  // Domain scope management
  const { currentScope, isScopeActive } = useDomainScope();

  // Get brand settings for current domain
  const {
    brandSettings,
    isLoading,
    initialize: initBranding,
    saveBranding
  } = useBranding(currentScope.value.domain);

  // Computed for canonical check
  const isCanonical = computed(() => currentScope.value.isCanonical);

  // Get unified privacy defaults from the workspace composable
  const { isEditable } = useWorkspacePrivacyDefaults({
    brandSettings: ref(brandSettings.value),
    isCanonical
  });

  // Initialize branding on mount (only for custom domains)
  onMounted(() => {
    if (isScopeActive.value && !currentScope.value.isCanonical) {
      initBranding();
    }
  });

  // Re-initialize when domain scope changes (only for custom domains)
  watch(
    () => currentScope.value.domain,
    () => {
      if (isScopeActive.value && !currentScope.value.isCanonical) {
        initBranding();
      }
    }
  );

  // Handle privacy defaults update (only for custom domains)
  const handlePrivacyUpdate = async (settings: Partial<BrandSettings>) => {
    if (!isEditable.value) return;
    await saveBranding(settings, currentScope.value.domain);
  };

  // Show privacy bar when domain scope is active (for all domains now)
  const showPrivacyBar = computed(() => isScopeActive.value);
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <!-- Upgrade Banner (shown for free plan users when billing is enabled) -->
    <UpgradeBanner />

    <!-- Privacy Defaults Bar (shown when domain scope is active) -->
    <PrivacyDefaultsBar
      v-if="showPrivacyBar"
      :brand-settings="brandSettings"
      :is-loading="isLoading"
      :is-canonical="isCanonical"
      :is-editable="isEditable"
      class="mb-6 rounded-lg"
      @update="handlePrivacyUpdate" />

    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
