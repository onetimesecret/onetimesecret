<!-- src/apps/workspace/domains/DomainEmail.vue -->

<script setup lang="ts">
/**
 * Domain Email Configuration Page
 *
 * Page-level component that wires together the email config composable,
 * form component, and DNS records display. Follows the DomainSso page
 * structure: header -> entitlement gate -> fallback notice -> form -> DNS.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainEmailConfigForm from '@/apps/workspace/components/domains/DomainEmailConfigForm.vue';
import DomainEmailDnsRecords from '@/apps/workspace/components/domains/DomainEmailDnsRecords.vue';
import { useDomain } from '@/shared/composables/useDomain';

import { useEmailConfig } from '@/shared/composables/useEmailConfig';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import { onBeforeRouteLeave } from 'vue-router';

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
const hasEntitlement = computed(() => can(ENTITLEMENTS.CUSTOM_MAIL_SENDER));
const hasFlexibleFromDomain = computed(() => can(ENTITLEMENTS.FLEXIBLE_FROM_DOMAIN));
const billingRoute = computed(() => `/billing/${props.orgid}/plans`);

// ---------------------------------------------------------------------------
// Email config composable
// ---------------------------------------------------------------------------

const {
  isLoading: emailLoading,
  isInitialized,
  isSaving,
  isValidating,
  isDeleting,
  isTesting,
  testResult,
  testError,
  error: emailError,
  emailConfig,
  formState,
  isConfigured,
  usesFallbackSender,
  dnsRecords,
  validationStatus,
  lastValidatedAt,
  dnsCheckCompletedAt,
  providerCheckCompletedAt,
  lastError,
  hasUnsavedChanges,
  initialize: initializeEmailConfig,
  saveConfig,
  deleteConfig,
  validateDomain,
  sendTestEmail,
  discardChanges,
} = useEmailConfig(props.extid);

// ---------------------------------------------------------------------------
// Form state handler
// ---------------------------------------------------------------------------

import type { EmailConfigFormState } from '@/shared/composables/useEmailConfig';

const handleFormStateUpdate = (state: EmailConfigFormState) => {
  formState.value = state;
};

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

  // Initialize email config if entitlement is already available
  if (hasEntitlement.value) {
    await initializeEmailConfig();
  }
});

// Handle race condition: organizations may load after onMounted runs.
// Watch for entitlement to become true and initialize if needed.
watch(hasEntitlement, async (entitled) => {
  if (entitled && !isInitialized.value) {
    await initializeEmailConfig();
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
      <!-- Loading State -->
      <div v-if="domainLoading" class="flex items-center justify-center py-12">
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
      <div v-else-if="domainError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="domainError.message" />
      </div>

      <!-- Access Denied / Upgrade Banner -->
      <div
        v-else-if="!hasEntitlement"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.email.access_denied') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.email.upgrade_to_configure') }}
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

      <!-- Main Content (entitled users) -->
      <template v-else>
        <!-- Card wrapper -->
        <div class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <!-- Card header -->
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center gap-3">
              <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  collection="heroicons"
                  name="envelope"
                  class="size-5 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div>
                <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                  {{ t('web.domains.email.title') }}
                </h2>
                <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.domains.email.config_description') }}
                </p>
              </div>
            </div>
          </div>

          <div class="p-6 space-y-8">
            <!-- Email config loading -->
            <div v-if="emailLoading && !isInitialized" class="flex items-center justify-center py-12">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                class="size-8 animate-spin text-gray-400"
                aria-hidden="true" />
              <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
            </div>

            <template v-else>
              <!-- Fallback sender notice -->
              <div
                v-if="usesFallbackSender"
                class="flex items-center gap-3 rounded-md bg-amber-50 px-4 py-3 dark:bg-amber-900/20">
                <OIcon
                  collection="heroicons"
                  name="information-circle"
                  class="size-5 flex-shrink-0 text-amber-500 dark:text-amber-400"
                  aria-hidden="true" />
                <p class="flex-1 text-sm text-amber-700 dark:text-amber-300">
                  {{ t('web.domains.email.default_sender_notice') }}
                </p>
              </div>

              <!-- Email Configuration Form -->
              <DomainEmailConfigForm
                :form-state="formState"
                :is-configured="isConfigured"
                :is-saving="isSaving"
                :is-deleting="isDeleting"
                :is-testing="isTesting"
                :has-unsaved-changes="hasUnsavedChanges"
                :provider="emailConfig?.provider"
                :test-result="testResult"
                :test-error="testError"
                :error="emailError?.message"
                :display-domain="displayDomain"
                :flexible-from-domain="hasFlexibleFromDomain"
                @update:form-state="handleFormStateUpdate"
                @save="saveConfig"
                @discard="discardChanges"
                @delete="deleteConfig"
                @test="sendTestEmail" />

              <!-- DNS Records Section (shown when config exists) -->
              <DomainEmailDnsRecords
                v-if="isConfigured"
                :dns-records="dnsRecords"
                :validation-status="validationStatus"
                :last-validated-at="lastValidatedAt"
                :dns-check-completed-at="dnsCheckCompletedAt"
                :provider-check-completed-at="providerCheckCompletedAt"
                :last-error="lastError"
                :is-validating="isValidating"
                @validate="validateDomain" />
            </template>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
