<!-- src/apps/workspace/domains/DomainSignup.vue -->

<script setup lang="ts">
/**
 * Domain Signup Validation Configuration Page
 *
 * Page-level component that wires together the signup config composable and
 * form component. Follows the DomainSso page structure: header ->
 * entitlement gate -> form.
 *
 * There is exactly ONE availability concept on this page: the effective
 * state (ADR-024). The banner shows the resolver's output; the form's
 * signup-enabled control is the single input. The explicit-override flag
 * (`enabled`) is not user-facing — every save materializes it, and the
 * form's delete ("remove config") unpins.
 */
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainAuthOverrideBanner from '@/apps/workspace/components/domains/DomainAuthOverrideBanner.vue';
import DomainSignupConfigForm from '@/apps/workspace/components/domains/DomainSignupConfigForm.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useDomain } from '@/shared/composables/useDomain';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { useSignupConfig } from '@/shared/composables/useSignupConfig';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { ENTITLEMENTS } from '@/types/organization';
import { storeToRefs } from 'pinia';
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, onBeforeRouteLeave, RouterLink } from 'vue-router';

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

// The dormant-policy warning (site-level signups off) now comes from the
// banner's globalEnabled, fed by the API's resolution details (ADR-024) —
// the same source the runtime gate uses — instead of a separate bootstrap
// read that could disagree with it.
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
  globalEnabled,
  effectiveEnabled,
  isWorkspaceDefault,
  initialize: initializeSignupConfig,
  saveConfig,
  deleteConfig,
  discardChanges,
} = useSignupConfig(props.extid);

// The primary Save ("Update") lives in the page header. The form owns validity,
// so it emits `can-save`; the header's Save button is disabled unless it's true.
const formCanSave = ref(false);

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
    <!-- Header Section. Back folded into the header row (opt-in affordance),
         so there's no separate Back row above it. -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        :domain="customDomainRecord"
        :has-unsaved-changes="hasUnsavedChanges"
        :orgid="props.orgid"
        external-path="/signup"
        back-visible
        :save-visible="canCustomSignup && isInitialized"
        :save-disabled="!formCanSave"
        :save-loading="isSaving"
        @back="handleBack"
        @save="saveConfig" />
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State -->
      <!-- signupLoading defaults to true and only resolves once the config is
           fetched; for unentitled users we skip that fetch, so it must not gate
           the skeleton or it would spin forever instead of showing the guard. -->
      <SettingsSkeleton v-if="domainLoading || (canCustomSignup && signupLoading)" />

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

        <div class="space-y-6 p-6">
          <!-- Effective state (ADR-024): resolver output + workspace-default
               badge + dormant warning. Replaces the old site-signups-disabled
               warning and not-configured notice. -->
          <DomainAuthOverrideBanner
            feature="signup"
            :effective-enabled="effectiveEnabled"
            :global-enabled="globalEnabled"
            :workspace-default="isWorkspaceDefault" />

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
            @discard="discardChanges"
            @can-save="formCanSave = $event" />
        </div>
      </div>
    </div>
  </div>
</template>
