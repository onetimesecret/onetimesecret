<!-- src/apps/workspace/domains/DomainIncoming.vue -->

<script setup lang="ts">
/**
 * Domain Incoming Secrets Configuration Page
 *
 * Page-level component that wires together the incoming config composable
 * and form component. Follows the DomainEmail page structure: header ->
 * entitlement gate -> form.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted, watch } from 'vue';
import { useRouter, onBeforeRouteLeave, RouterLink } from 'vue-router';
import { storeToRefs } from 'pinia';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainIncomingConfigForm from '@/apps/workspace/components/domains/DomainIncomingConfigForm.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import { useDomain } from '@/shared/composables/useDomain';

import { useIncomingConfig } from '@/shared/composables/useIncomingConfig';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import { isOrgsIncomingSecretsEnabled } from '@/utils/features';

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
// Plan entitlement: does org subscription include incoming secrets?
const hasIncomingEntitlement = computed(() => can(ENTITLEMENTS.INCOMING_SECRETS));
// Role capability: does user have permission to manage org settings?
const hasManageOrgCapability = computed(() => can(ENTITLEMENTS.MANAGE_ORG));
// Both required to configure
const canManageIncoming = computed(
  () => hasManageOrgCapability.value && hasIncomingEntitlement.value
);
const billingRoute = computed(() => `/billing/${props.orgid}/plans`);
const incomingSecretsEnabled = computed(() => isOrgsIncomingSecretsEnabled());

// ---------------------------------------------------------------------------
// Incoming config composable
// ---------------------------------------------------------------------------

const {
  isLoading: incomingLoading,
  isInitialized,
  isSaving,
  isDeleting,
  error: incomingError,
  formState,
  savedFormState,
  hasUnsavedChanges,
  maxRecipients,
  initialize: initializeIncomingConfig,
  saveConfig,
  deleteConfig,
  addRecipient,
  removeRecipient,
  discardChanges,
  updateEnabled,
} = useIncomingConfig(props.extid);

// ---------------------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------------------

// Adding a recipient, removing one, and toggling enabled are all deliberate
// actions, so they persist immediately instead of waiting for a manual Save.
// Success toasts are suppressed (silent) to avoid one-per-action noise; the
// updated list is its own feedback. On failure the error surfaces and
// hasUnsavedChanges flips true, re-exposing the Save button as a retry.

const handleAddRecipient = async (email: string, name?: string) => {
  if (addRecipient(email, name)) {
    await saveConfig({ silent: true });
  }
};

const handleRemoveRecipient = async (index: number) => {
  removeRecipient(index);
  await saveConfig({ silent: true });
};

const handleUpdateEnabled = async (enabled: boolean) => {
  if (isSaving.value) return;
  updateEnabled(enabled);
  await saveConfig({ silent: true });
};

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains/${props.extid}`);
};

/**
 * The domain's public homepage currently presents the incoming form.
 * Surfaced as a notice because edits here can un-ready incoming (disable,
 * remove all recipients, delete config) — the write is deliberately
 * allowed, and the public homepage then degrades to the private landing
 * page until incoming is ready again.
 */
const homepageUsesIncoming = computed(() => {
  const config = customDomainRecord.value?.homepage_config;
  return (config?.enabled ?? false) && config?.secrets_mode === 'incoming';
});

// Unsaved changes guard
onBeforeRouteLeave((_to, _from, next) => {
  if (hasUnsavedChanges.value) {
    const answer = window.confirm(t('web.domains.unsaved_changes_confirmation'));
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

  // Initialize incoming config if entitlement is already available
  if (canManageIncoming.value) {
    await initializeIncomingConfig();
  }
});

// Handle race condition: organizations may load after onMounted runs.
// Watch for entitlement to become true and initialize if needed.
watch(canManageIncoming, async (entitled) => {
  if (entitled && !isInitialized.value) {
    await initializeIncomingConfig();
  }
});

// Re-initialize when domain extid changes (e.g., navigating between domains)
watch(() => props.extid, async () => {
  if (canManageIncoming.value) {
    await initializeIncomingConfig();
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
        :domain="customDomainRecord"
        :has-unsaved-changes="hasUnsavedChanges"
        :orgid="props.orgid"
        external-path="/incoming" />
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State -->
      <SettingsSkeleton v-if="domainLoading" />

      <!-- Error State -->
      <div v-else-if="domainError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="domainError.message" />
      </div>

      <!-- Feature Disabled at Install Level -->
      <div
        v-else-if="!incomingSecretsEnabled"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="x-circle"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.incoming.feature_disabled') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.incoming.feature_disabled_description') }}
        </p>
      </div>

      <!-- Upgrade Required: org plan lacks incoming_secrets entitlement -->
      <div
        v-else-if="!hasIncomingEntitlement"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="sparkles"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('incoming.upgrade_required_title') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.incoming.upgrade_to_configure') }}
        </p>
        <RouterLink
          :to="billingRoute"
          class="mt-4 inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
          {{ t('web.billing.invoices.view_plans') }}
          <OIcon
            collection="heroicons"
            name="arrow-right"
            class="size-4"
            aria-hidden="true" />
        </RouterLink>
      </div>

      <!-- Access Denied: user lacks manage_org capability (has plan, but not owner) -->
      <div
        v-else-if="!hasManageOrgCapability"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.incoming.access_denied') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.incoming.access_denied_description') }}
        </p>
      </div>

      <!-- Incoming Secrets Configuration Form -->
      <div
        v-else
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="inbox-arrow-down"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.domains.incoming.title') }}
              </h2>
            </div>
          </div>
        </div>

        <div class="p-6 space-y-6">
          <!-- Homepage coupling notice: this domain's public homepage presents
               the incoming form, so un-readying incoming degrades it -->
          <div
            v-if="homepageUsesIncoming"
            class="flex items-start gap-3 rounded-md bg-amber-50 px-4 py-3 dark:bg-amber-900/20"
            data-testid="homepage-incoming-coupling-notice">
            <OIcon
              collection="heroicons"
              name="information-circle"
              class="mt-0.5 size-5 shrink-0 text-amber-500 dark:text-amber-400"
              aria-hidden="true" />
            <p class="text-sm text-amber-800 dark:text-amber-200">
              {{ t('web.domains.homepage.homepage_uses_incoming_warning') }}
            </p>
          </div>

          <!-- Incoming config loading -->
          <SettingsSkeleton
            v-if="incomingLoading && !isInitialized"
            :heading="false" />

          <template v-else>
            <DomainIncomingConfigForm
              :form-state="formState"
              :saved-form-state="savedFormState"
              :is-loading="incomingLoading"
              :is-saving="isSaving"
              :is-deleting="isDeleting"
              :has-unsaved-changes="hasUnsavedChanges"
              :max-recipients="maxRecipients"
              :error="incomingError?.message"
              @save="saveConfig"
              @delete="deleteConfig"
              @discard="discardChanges"
              @add-recipient="handleAddRecipient"
              @remove-recipient="handleRemoveRecipient"
              @update:enabled="handleUpdateEnabled" />
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
