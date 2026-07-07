<!-- src/apps/secret/conceal/IncomingForm.vue -->

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue';
  import { storeToRefs } from 'pinia';
  import { useIncomingSecret } from '@/shared/composables/useIncomingSecret';
  import { useIncomingStore } from '@/shared/stores/incomingStore';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import IncomingSecretFormBody from '@/apps/secret/components/incoming/IncomingSecretFormBody.vue';
  import LoadingOverlay from '@/shared/components/common/LoadingOverlay.vue';
  import EmptyState from '@/shared/components/ui/EmptyState.vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const incomingStore = useIncomingStore();
  const { isFeatureEnabled, loadConfig } = useIncomingSecret();

  // Custom-domain brand logo. The top masthead is suppressed on custom domains
  // (see guards.routes.ts), so the page body owns the logo — mirroring
  // BrandedHomepage. Hidden when no logo is configured or the asset 404s, so
  // the no-logo page stays title + subtitle + form with no placeholder box.
  const { logoUri, displayName } = storeToRefs(useProductIdentity());
  const logoError = ref(false);
  const handleLogoError = () => {
    logoError.value = true;
  };

  const isLoading = ref(true);

  const showEntitlementBlocked = computed(
    () => !isLoading.value && incomingStore.isEntitlementBlocked
  );
  const showFeatureDisabled = computed(
    () =>
      !isLoading.value &&
      !showEntitlementBlocked.value &&
      !incomingStore.configError &&
      !isFeatureEnabled.value
  );

  onMounted(async () => {
    await loadConfig();
    isLoading.value = false;
  });
</script>

<template>
  <div class="container mx-auto mt-16 max-w-3xl px-4 pb-16 sm:mt-20 sm:pb-16">
    <!-- Entitlement Required (custom domain without incoming_secrets) -->
    <EmptyState
      v-if="showEntitlementBlocked"
      :show-action="false">
      <template #title>
        {{ t('incoming.upgrade_required_title') }}
      </template>
      <template #description>
        {{ t('incoming.upgrade_required_description') }}
      </template>
    </EmptyState>

    <!-- Feature Disabled (no header) -->
    <EmptyState
      v-else-if="showFeatureDisabled"
      :show-action="false"
      testid="incoming-feature-disabled">
      <template #title>
        {{ t('incoming.feature_disabled_title') }}
      </template>
      <template #description>
        {{ t('incoming.feature_disabled_description') }}
      </template>
    </EmptyState>

    <!-- Normal flow: header + content (feature enabled, not blocked) -->
    <template v-else>
      <!-- Header -->
      <div class="mb-10">
        <!-- Brand logo (custom domains) — hidden if unconfigured or 404s -->
        <img
          v-if="logoUri && !logoError"
          :src="logoUri"
          :alt="displayName"
          class="mb-6 h-16 max-w-[200px] object-contain"
          @error="handleLogoError" />
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white sm:text-4xl">
          {{ t('incoming.page_title') }}
        </h1>
        <p class="mt-3 text-base text-gray-600 dark:text-gray-400 sm:text-lg">
          {{ t('incoming.page_description') }}
        </p>
      </div>

      <!-- Loading State -->
      <LoadingOverlay
        :show="isLoading"
        :message="t('incoming.loading_config')" />

      <!-- Error State -->
      <EmptyState
        v-if="incomingStore.configError"
        :show-action="false"
        testid="incoming-config-error">
        <template #title>
          {{ t('incoming.config_error_title') }}
        </template>
        <template #description>
          {{ incomingStore.configError }}
        </template>
      </EmptyState>

      <!-- Form -->
      <IncomingSecretFormBody v-else-if="!isLoading" />
    </template>
  </div>
</template>
