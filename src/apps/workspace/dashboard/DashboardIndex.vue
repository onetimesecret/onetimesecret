<!-- src/apps/workspace/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import RecentSecretsTable from '@/apps/secret/components/RecentSecretsTable.vue';
  import PrivacyDefaultsBar from '@/apps/workspace/components/domains/PrivacyDefaultsBar.vue';
  import UpgradeBanner from '@/apps/workspace/dashboard/components/UpgradeBanner.vue';
  import { useDomainScope } from '@/shared/composables/useDomainScope';
  import { useBranding } from '@/shared/composables/useBranding';
  import { WindowService } from '@/services/window.service';
  import type { BrandSettings } from '@/schemas/models';
  import { computed, onMounted, watch } from 'vue';

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

  // Initialize branding on mount
  onMounted(() => {
    if (isScopeActive.value && !currentScope.value.isCanonical) {
      initBranding();
    }
  });

  // Re-initialize when domain scope changes
  watch(
    () => currentScope.value.domain,
    () => {
      if (isScopeActive.value && !currentScope.value.isCanonical) {
        initBranding();
      }
    }
  );

  // Handle privacy defaults update
  const handlePrivacyUpdate = async (settings: Partial<BrandSettings>) => {
    await saveBranding(settings, currentScope.value.domain);
  };

  // Only show privacy bar for custom domains (not canonical)
  const showPrivacyBar = computed(() =>
    isScopeActive.value && !currentScope.value.isCanonical
  );
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <!-- Upgrade Banner (shown for free plan users when billing is enabled) -->
    <UpgradeBanner />

    <!-- Privacy Defaults Bar (only shown when custom domain scope is active) -->
    <PrivacyDefaultsBar
      v-if="showPrivacyBar"
      :brand-settings="brandSettings"
      :is-loading="isLoading"
      class="mb-6 rounded-lg"
      @update="handlePrivacyUpdate" />

    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
