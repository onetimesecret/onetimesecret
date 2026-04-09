<!-- src/apps/workspace/domains/DomainSso.vue -->

<script setup lang="ts">
/**
 * Domain SSO Configuration Page
 *
 * Page-level component that wires together the SSO config composable and
 * form component. Follows the DomainEmail page structure: header ->
 * entitlement gate -> form.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted, watch } from 'vue';
import { useRouter, onBeforeRouteLeave, RouterLink } from 'vue-router';
import { storeToRefs } from 'pinia';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainSsoConfigForm from '@/apps/workspace/components/domains/DomainSsoConfigForm.vue';
import { useDomain } from '@/shared/composables/useDomain';

import { useSsoConfig } from '@/shared/composables/useSsoConfig';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';

const { t } = useI18n();
const router = useRouter();

const props = defineProps<{
  orgid: string;
  extid: string;
}>();

// ---------------------------------------------------------------------------
// Domain data
// ---------------------------------------------------------------------------

const {
  domain: customDomainRecord,
  isLoading: domainLoading,
  error: domainError,
  initialize: initializeDomain,
} = useDomain(props.extid);

// ---------------------------------------------------------------------------
// Entitlement check
// ---------------------------------------------------------------------------

const organizationStore = useOrganizationStore();
const { organizations } = storeToRefs(organizationStore);
const organization = computed(() =>
  organizations.value.find((o) => o.extid === props.orgid) ?? null
);
const { can } = useEntitlements(organization);
const canManageSso = computed(() => can(ENTITLEMENTS.MANAGE_SSO));
const billingRoute = computed(() => `/billing/${props.orgid}/plans`);

// ---------------------------------------------------------------------------
// SSO config composable
// ---------------------------------------------------------------------------

const {
  isLoading: ssoLoading,
  isInitialized,
  isSaving,
  isDeleting,
  isTesting,
  error: ssoError,
  ssoConfig,
  formState,
  testResult,
  testError,
  isConfigured,
  hasUnsavedChanges,
  clientSecretMasked,
  initialize: initializeSsoConfig,
  saveConfig,
  deleteConfig,
  testConnection,
  discardChanges,
} = useSsoConfig(props.extid);

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains/${props.extid}`);
};

// Unsaved changes guard
onBeforeRouteLeave((_to, _from, next) => {
  if (hasUnsavedChanges.value) {
    const answer = window.confirm(t('web.branding.you_have_unsaved_changes_are_you_sure'));
    if (answer) next();
    else next(false);
  } else {
    next();
  }
});

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

onMounted(async () => {
  await initializeDomain();

  // Initialize SSO config if entitlement is already available
  if (canManageSso.value) {
    await initializeSsoConfig();
  }
});

// Handle race condition: organizations may load after onMounted runs.
// Watch for entitlement to become true and initialize if needed.
watch(canManageSso, async (entitled) => {
  if (entitled && !isInitialized.value) {
    await initializeSsoConfig();
  }
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Back button -->
    <div class="mx-auto max-w-4xl px-4 pt-4 sm:px-6 lg:px-8">
      <div class="mb-4">
        <button
          type="button"
          class="inline-flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          @click="handleBack">
          <OIcon
            collection="heroicons"
            name="arrow-left"
            class="size-5"
            aria-hidden="true" />
          {{ t('web.COMMON.back') }}
        </button>
      </div>
    </div>

    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        v-if="!domainLoading"
        :domain="customDomainRecord"
        :has-unsaved-changes="hasUnsavedChanges"
        :orgid="props.orgid" />
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State (domain or SSO config) -->
      <div v-if="domainLoading || ssoLoading" class="flex items-center justify-center py-12">
        <div class="text-center">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            class="mx-auto size-8 animate-spin text-gray-400"
            aria-hidden="true" />
          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.COMMON.loading') }}
          </p>
        </div>
      </div>

      <!-- Error State -->
      <div v-else-if="domainError || ssoError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="(domainError?.message ?? ssoError?.message) ?? ''" />
      </div>

      <!-- Access Denied / Upgrade Banner -->
      <div
        v-else-if="!canManageSso"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.sso.access_denied') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.sso.upgrade_to_configure') }}
        </p>
        <RouterLink
          :to="billingRoute"
          class="mt-4 inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
          {{ t('web.billing.overview.view_plans_action') }}
          <OIcon
            collection="heroicons"
            name="arrow-right"
            class="size-4"
            aria-hidden="true" />
        </RouterLink>
      </div>

      <!-- SSO Configuration Form -->
      <div
        v-else
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="shield-check"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.domains.sso.title') }}
              </h2>
              <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.domains.sso.config_description') }}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6 space-y-6">
          <!-- Not configured notice -->
          <div
            v-if="!isConfigured"
            class="flex items-start gap-3 rounded-md bg-blue-50 px-4 py-3 dark:bg-blue-900/20">
            <OIcon
              collection="heroicons"
              name="information-circle"
              class="mt-0.5 size-5 flex-shrink-0 text-blue-500 dark:text-blue-400"
              aria-hidden="true" />
            <p class="flex-1 text-sm text-blue-700 dark:text-blue-300">
              {{ t('web.domains.sso.not_configured_notice') }}
            </p>
          </div>

          <DomainSsoConfigForm
            :domain-ext-id="props.extid"
            v-model:form-state="formState"
            :sso-config="ssoConfig"
            :is-loading="ssoLoading"
            :is-saving="isSaving"
            :is-deleting="isDeleting"
            :is-testing="isTesting"
            :has-unsaved-changes="hasUnsavedChanges"
            :is-configured="isConfigured"
            :client-secret-masked="clientSecretMasked"
            :test-result="testResult"
            :test-error="testError"
            @save="saveConfig"
            @delete="deleteConfig"
            @test="testConnection"
            @discard="discardChanges" />
        </div>
      </div>
    </div>
  </div>
</template>
