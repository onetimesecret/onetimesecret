<!-- src/apps/workspace/domains/DomainSignin.vue -->

<script setup lang="ts">
/**
 * Domain Sign-In Configuration Page
 *
 * Page-level component that wires together the signin config composable and
 * form component. Controls which auth methods are available on the
 * domain's signin page: password, email_auth, webauthn, SSO, or restrict
 * to a single method.
 *
 * There is exactly ONE availability concept on this page: the effective
 * state (ADR-024). The banner shows the resolver's output; the form's mode
 * switch is the single control. The explicit-override flag (`enabled`) is
 * not user-facing — every save materializes it, and "Reset to defaults"
 * unpins.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { storeToRefs } from 'pinia';
import OIcon from '@/shared/components/icons/OIcon.vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
import DomainAuthOverrideBanner from '@/apps/workspace/components/domains/DomainAuthOverrideBanner.vue';
import DomainSigninConfigForm from '@/apps/workspace/components/domains/DomainSigninConfigForm.vue';
import SsoCredentialsModal from '@/apps/workspace/components/domains/SsoCredentialsModal.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import { useDomain } from '@/shared/composables/useDomain';

import {
  resolveGlobalMethodAvailability,
  useSigninConfig,
} from '@/shared/composables/useSigninConfig';
import { useSsoConfig } from '@/shared/composables/useSsoConfig';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { ENTITLEMENTS } from '@/types/organization';
import { useOrganizationStore } from '@/shared/stores/organizationStore';

const { t } = useI18n();
const route = useRoute();
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
// Organization
// ---------------------------------------------------------------------------

const organizationStore = useOrganizationStore();
const { organizations } = storeToRefs(organizationStore);
const organization = computed(() =>
  organizations.value.find((o) => o.extid === props.orgid) ?? null
);
const { can } = useEntitlements(organization);
const canCustomSignin = computed(() => can(ENTITLEMENTS.CUSTOM_SIGNIN_CONFIG));
const canManageSso = computed(() => can(ENTITLEMENTS.MANAGE_SSO));
const billingRoute = computed(() => `/billing/${props.orgid}/plans`);

// ---------------------------------------------------------------------------
// Global method availability (install-level config)
// ---------------------------------------------------------------------------

// Single definition in useSigninConfig (also seeds unconfigured domains);
// wrapped in a computed so bootstrap feature reads stay reactive.
const globalAvailability = computed(() => resolveGlobalMethodAvailability());

// ---------------------------------------------------------------------------
// Signin config composable
// ---------------------------------------------------------------------------

const {
  isLoading: signinLoading,
  isInitialized,
  isSaving,
  isDeleting,
  error: signinError,
  formState,
  savingField,
  isConfigured,
  hasUnsavedChanges,
  globalEnabled,
  effectiveEnabled,
  isWorkspaceDefault,
  initialize: initializeSigninConfig,
  autoSaveFields,
  deleteConfig,
} = useSigninConfig(props.extid);

// ---------------------------------------------------------------------------
// SSO config composable
// ---------------------------------------------------------------------------

const {
  isLoading: ssoConfigLoading,
  isInitialized: ssoInitialized,
  isSaving: ssoSaving,
  isDeleting: ssoDeleting,
  isTesting,
  error: _ssoConfigError,
  ssoConfig,
  formState: ssoFormState,
  testResult,
  testError,
  isConfigured: ssoIsConfigured,
  hasUnsavedChanges: ssoHasUnsavedChanges,
  clientSecretMasked,
  initialize: initializeSsoConfig,
  saveConfig: saveSsoConfig,
  deleteConfig: deleteSsoConfig,
  testConnection,
  discardChanges: discardSsoChanges,
} = useSsoConfig(props.extid);

const showSsoModal = ref(false);

// Deep link support: `?modal=sso` opens the SSO credentials modal on load,
// e.g. from the org SSO tab's Configure link.
const wantsSsoModal = computed(() => route.query.modal === 'sso');

const handleOpenSsoModal = () => {
  showSsoModal.value = true;
};

const handleCloseSsoModal = () => {
  showSsoModal.value = false;
  // Strip the deep-link param so a refresh doesn't reopen the modal.
  if (wantsSsoModal.value) {
    const { modal: _modal, ...query } = route.query;
    router.replace({ query });
  }
};

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

const handleBack = () => {
  router.push(`/org/${props.orgid}/domains/${props.extid}`);
};

// Unsaved changes guard. The signin form auto-saves, so its hasUnsavedChanges
// is effectively always false; this now guards the SSO modal's pending edits.
onBeforeRouteLeave((_to, _from, next) => {
  if (ssoHasUnsavedChanges.value) {
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

  // Only fetch the signin config when the entitlement is available. Fetching
  // without it returns a server error, which would surface as an inline alert
  // instead of the access-denied upgrade prompt below.
  if (canCustomSignin.value) {
    await initializeSigninConfig();
  }

  if (canManageSso.value) {
    await initializeSsoConfig();
    if (wantsSsoModal.value) showSsoModal.value = true;
  }
});

// Handle race condition: organizations (and thus entitlements) may load after
// onMounted runs. Watch for the entitlement to become true and initialize then.
watch(canCustomSignin, async (entitled) => {
  if (entitled && !isInitialized.value) {
    await initializeSigninConfig();
  }
});

watch(canManageSso, async (entitled) => {
  if (entitled && !ssoInitialized.value) {
    await initializeSsoConfig();
    if (wantsSsoModal.value) showSsoModal.value = true;
  }
});
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section. Back folded into the header row (opt-in affordance),
         so there's no separate Back row above it. Signin auto-saves each field,
         so there's no header Save. -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        :domain="customDomainRecord"
        :has-unsaved-changes="hasUnsavedChanges"
        :orgid="props.orgid"
        external-path="/signin"
        back-visible
        @back="handleBack" />
    </div>

    <!-- Content -->
    <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Loading State -->
      <!-- signinLoading defaults to true and only resolves once the config is
           fetched; for unentitled users we skip that fetch, so it must not gate
           the skeleton or it would spin forever instead of showing the guard. -->
      <SettingsSkeleton v-if="domainLoading || (canCustomSignin && signinLoading)" />

      <!-- Error State -->
      <div v-else-if="domainError || signinError" class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="(domainError?.message ?? signinError?.message) ?? ''" />
      </div>

      <!-- Access Denied / Upgrade Banner -->
      <div
        v-else-if="!canCustomSignin"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.signin.access_denied') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.signin.upgrade_to_configure') }}
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

      <!-- Signin Configuration Form -->
      <div
        v-else
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center gap-3">
            <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="arrow-right-on-rectangle"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div class="flex-1">
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.domains.signin.title') }}
              </h2>
              <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.domains.signin.config_description') }}
              </p>
            </div>
          </div>
        </div>

        <div class="space-y-6 p-6">
          <!-- Effective state (ADR-024): resolver output + workspace-default
               badge + dormant warning. Replaces the old header enabled-toggle
               and not-configured notice. -->
          <DomainAuthOverrideBanner
            feature="signin"
            :effective-enabled="effectiveEnabled"
            :global-enabled="globalEnabled"
            :workspace-default="isWorkspaceDefault" />

          <DomainSigninConfigForm
            :domain-ext-id="props.extid"
            :form-state="formState"
            :is-loading="signinLoading"
            :is-saving="isSaving"
            :is-deleting="isDeleting"
            :is-configured="isConfigured"
            :workspace-default="isWorkspaceDefault"
            :sso-configured="ssoIsConfigured"
            :can-manage-sso="canManageSso"
            :global-availability="globalAvailability"
            :saving-field="savingField"
            @auto-save="autoSaveFields"
            @delete="deleteConfig"
            @configure-sso="handleOpenSsoModal" />
        </div>
      </div>

      <!-- SSO Credentials Modal -->
      <SsoCredentialsModal
        :is-open="showSsoModal"
        :domain-ext-id="props.extid"
        :domain-host="customDomainRecord?.display_domain ?? ''"
        :org-id="props.orgid"
        v-model:form-state="ssoFormState"
        :sso-config="ssoConfig"
        :is-loading="ssoConfigLoading"
        :is-saving="ssoSaving"
        :is-deleting="ssoDeleting"
        :is-testing="isTesting"
        :has-unsaved-changes="ssoHasUnsavedChanges"
        :is-configured="ssoIsConfigured"
        :client-secret-masked="clientSecretMasked"
        :test-result="testResult"
        :test-error="testError"
        @close="handleCloseSsoModal"
        @save="saveSsoConfig"
        @delete="deleteSsoConfig"
        @test="testConnection"
        @discard="discardSsoChanges" />
    </div>
  </div>
</template>
