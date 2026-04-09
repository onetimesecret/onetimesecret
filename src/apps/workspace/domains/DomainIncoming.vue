<!-- src/apps/workspace/domains/DomainIncoming.vue -->

<script setup lang="ts">
/**
 * Domain Incoming Secrets Configuration Page
 *
 * Page-level component that wires together the incoming config composable
 * and form component. Follows the DomainEmail page structure: header ->
 * entitlement gate -> form.
 *
 * Note: Individual removal of existing recipients is not supported because
 * emails are hashed after save - we cannot reconstruct the list without all
 * original emails. Users should use "Delete All" to clear recipients.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted, watch } from 'vue';
import { useRouter, onBeforeRouteLeave, RouterLink } from 'vue-router';
import { storeToRefs } from 'pinia';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainIncomingConfigForm from '@/apps/workspace/components/domains/DomainIncomingConfigForm.vue';
import { useDomain } from '@/shared/composables/useDomain';

import { useIncomingConfig } from '@/shared/composables/useIncomingConfig';
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
const canManageIncoming = computed(() => can(ENTITLEMENTS.INCOMING_SECRETS));
const billingRoute = computed(() => `/billing/${props.orgid}/plans`);

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
  serverState,
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

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains/${props.extid}`);
};

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
        v-else-if="!canManageIncoming"
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
        <RouterLink
          :to="billingRoute"
          class="mt-4 inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
          {{ t('web.domains.incoming.upgrade_to_configure') }}
          <OIcon
            collection="heroicons"
            name="arrow-right"
            class="size-4"
            aria-hidden="true" />
        </RouterLink>
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
          <!-- Incoming config loading -->
          <div v-if="incomingLoading && !isInitialized" class="flex items-center justify-center py-12">
            <OIcon
              collection="heroicons"
              name="arrow-path"
              class="size-8 animate-spin text-gray-400"
              aria-hidden="true" />
            <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
          </div>

          <template v-else>
            <DomainIncomingConfigForm
              :form-state="formState"
              :server-state="serverState"
              :is-loading="incomingLoading"
              :is-saving="isSaving"
              :is-deleting="isDeleting"
              :has-unsaved-changes="hasUnsavedChanges"
              :max-recipients="maxRecipients"
              :error="incomingError?.message"
              @save="saveConfig"
              @delete="deleteConfig"
              @discard="discardChanges"
              @add-recipient="(email, name) => addRecipient(email, name)"
              @remove-recipient="removeRecipient"
              @update:enabled="updateEnabled" />
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
