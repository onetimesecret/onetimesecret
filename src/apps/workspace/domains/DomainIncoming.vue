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
import { computed, watch } from 'vue';
import { useRouter, RouterLink } from 'vue-router';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainIncomingConfigForm from '@/apps/workspace/components/domains/DomainIncomingConfigForm.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import { useDomain } from '@/shared/composables/useDomain';

import { useIncomingConfig } from '@/shared/composables/useIncomingConfig';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useTargetDomainPermissions } from '@/shared/composables/useResourcePermissions';
import { useUnsavedRouteGuard } from '@/shared/composables/useUnsavedRouteGuard';
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

const { permission, isLoading: permissionLoading } = useTargetDomainPermissions(() => props.orgid, () => props.extid);
const bootstrapStore = useBootstrapStore();
const canManageIncoming = computed(() => permission.value?.permissions.can_manage_incoming);
const canViewDomain = computed(() => permission.value?.permissions.can_view === true);
const featureRequired = computed(() => canManageIncoming.value === false &&
  permission.value?.permissions.incoming_feature_required === true);
const billingRoute = computed(() => `/billing/${props.orgid}/plans`);
const canUpgrade = computed(() => permission.value?.membership.role === 'owner');
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
  const role = permission.value?.membership.role;
  const canOpenDetail = canViewDomain.value && (role === 'owner' || role === 'admin');
  router.push(canOpenDetail ? `/org/${props.orgid}/domains/${props.extid}` : '/dashboard');
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
useUnsavedRouteGuard(hasUnsavedChanges, 'web.domains.unsaved_changes_confirmation');

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// The workspace router mounts a fresh page for each domain.
watch(canViewDomain, allowed => { if (allowed) void initializeDomain(); }, { immediate: true });
watch(canManageIncoming, allowed => {
  if (allowed && incomingSecretsEnabled.value) void initializeIncomingConfig();
}, { immediate: true });
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section. Back folded into the header row (opt-in affordance),
         so there's no separate Back row above it. Recipients + the enabled
         toggle auto-save, so there's no header Save (the in-form Save is a
         retry affordance after a failed auto-save). -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        :domain="customDomainRecord"
        :has-unsaved-changes="hasUnsavedChanges"
        :orgid="props.orgid"
        external-path="/incoming"
        back-visible
        @back="handleBack" />
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State -->
      <SettingsSkeleton v-if="permissionLoading || domainLoading" />

      <!-- Error State -->
      <div v-else-if="domainError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="domainError.message" />
      </div>

      <!-- Feature Disabled at Install Level -->
      <div
        v-else-if="!incomingSecretsEnabled || (featureRequired && !bootstrapStore.billing_enabled)"
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
          {{ t(incomingSecretsEnabled ? 'incoming.feature_disabled_description' : 'web.domains.incoming.feature_disabled_description') }}
        </p>
      </div>

      <!-- Upgrade Required: org plan lacks incoming_secrets entitlement -->
      <div
        v-else-if="featureRequired"
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
          {{ t(canUpgrade ? 'web.domains.incoming.upgrade_to_configure' : 'web.domains.entitlement_required_member') }}
        </p>
        <RouterLink
          v-if="canUpgrade"
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
        v-else-if="canManageIncoming !== true"
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
          {{ t(canManageIncoming === undefined ? 'web.organizations.access_unconfirmed_notice' : 'web.domains.incoming.access_denied_description') }}
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
