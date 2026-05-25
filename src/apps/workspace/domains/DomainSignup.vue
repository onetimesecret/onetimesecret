<!-- src/apps/workspace/domains/DomainSignup.vue -->

<script setup lang="ts">
/**
 * Domain Signup Validation Configuration Page
 *
 * Page-level component that wires together the signup config composable and
 * form component. Follows the DomainSso page structure: header ->
 * entitlement gate -> form.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted, watch } from 'vue';
import { useRouter, onBeforeRouteLeave, RouterLink } from 'vue-router';
import { storeToRefs } from 'pinia';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainSignupConfigForm from '@/apps/workspace/components/domains/DomainSignupConfigForm.vue';
import { useDomain } from '@/shared/composables/useDomain';

import { useSignupConfig } from '@/shared/composables/useSignupConfig';
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
const canCustomSignup = computed(() => can(ENTITLEMENTS.CUSTOM_SIGNUP_VALIDATION));
const billingRoute = computed(() => `/billing/${props.orgid}/plans`);

// ---------------------------------------------------------------------------
// Signup config composable
// ---------------------------------------------------------------------------

const {
  isLoading: signupLoading,
  isInitialized,
  isSaving,
  isDeleting,
  error: signupError,
  signupConfig,
  formState,
  isConfigured,
  hasUnsavedChanges,
  initialize: initializeSignupConfig,
  saveConfig,
  deleteConfig,
  discardChanges,
} = useSignupConfig(props.extid);

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

  if (canCustomSignup.value) {
    await initializeSignupConfig();
  }
});

// Handle race condition: organizations may load after onMounted runs.
watch(canCustomSignup, async (entitled) => {
  if (entitled && !isInitialized.value) {
    await initializeSignupConfig();
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
          <span class="sr-only">{{ t('web.COMMON.back') }}</span>
        </button>
      </div>
    </div>

    <!-- Header Section -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        :domain="customDomainRecord"
        :has-unsaved-changes="hasUnsavedChanges"
        :orgid="props.orgid" />
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State -->
      <div v-if="domainLoading || signupLoading" class="flex items-center justify-center py-12">
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
      <div v-else-if="domainError || signupError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="(domainError?.message ?? signupError?.message) ?? ''" />
      </div>

      <!-- Access Denied / Upgrade Banner -->
      <div
        v-else-if="!canCustomSignup"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.signup.access_denied') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.signup.upgrade_to_configure') }}
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

      <!-- Signup Configuration Form -->
      <div
        v-else
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="user-plus"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <h2 data-testid="signup-config-title" class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.domains.signup.title') }}
              </h2>
              <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.domains.signup.config_description') }}
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
              {{ t('web.domains.signup.not_configured_notice') }}
            </p>
          </div>

          <DomainSignupConfigForm
            :domain-ext-id="props.extid"
            v-model:form-state="formState"
            :signup-config="signupConfig"
            :is-loading="signupLoading"
            :is-saving="isSaving"
            :is-deleting="isDeleting"
            :has-unsaved-changes="hasUnsavedChanges"
            :is-configured="isConfigured"
            @save="saveConfig"
            @delete="deleteConfig"
            @discard="discardChanges" />
        </div>
      </div>
    </div>
  </div>
</template>
