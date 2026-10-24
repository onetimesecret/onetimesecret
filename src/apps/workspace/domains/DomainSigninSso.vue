<!-- src/apps/workspace/domains/DomainSigninSso.vue -->

<script setup lang="ts">
  /**
   * Domain Single Sign-On Configuration Page
   *
   * Page-level host for DomainSsoConfigForm. Setup is a multi-system task
   * (copy the callback URL into the IdP, enter credentials, run the saved-
   * configuration check, sign in from another browser, come back for the
   * last-sign-in outcome), so it lives on its own route under the sign-in
   * settings rather than in a dialog. The page owns the SSO composable, the
   * sign-in details re-read that keeps the tenant-SSO verdict current, and
   * the return-to-window refresh of the last sign-in outcome.
   *
   * The one SSO on/off control stays on the sign-in page (the method control);
   * a record is turned on only by a passing saved-configuration check.
   */
  import DomainHeader from '@/apps/workspace/components/dashboard/DomainHeader.vue';
  import DomainSsoConfigForm from '@/apps/workspace/components/domains/DomainSsoConfigForm.vue';
  import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { BACKGROUND_REFRESH_THROTTLE_MS } from '@/shared/composables/useBackgroundRefresh';
  import { useDomain } from '@/shared/composables/useDomain';
  import { useEntitlements } from '@/shared/composables/useEntitlements';
  import { useSigninConfig } from '@/shared/composables/useSigninConfig';
  import { useSsoConfig } from '@/shared/composables/useSsoConfig';
  import { useUnsavedRouteGuard } from '@/shared/composables/useUnsavedRouteGuard';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { ENTITLEMENTS } from '@/types/organization';
  import { isOrgsSsoEnabled, isSamlEnabled } from '@/utils/features';
  import { useEventListener } from '@vueuse/core';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

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

  const domainHost = computed(() => customDomainRecord.value?.display_domain ?? '');

  // ---------------------------------------------------------------------------
  // Organization and entitlements
  // ---------------------------------------------------------------------------

  const organizationStore = useOrganizationStore();
  const { organizations } = storeToRefs(organizationStore);
  const organization = computed(
    () => organizations.value.find((o) => o.extid === props.orgid) ?? null
  );
  const { can } = useEntitlements(organization);
  /** Gates the sign-in details fetch (never fetched without it). */
  const canCustomSignin = computed(() => can(ENTITLEMENTS.CUSTOM_SIGNIN_CONFIG));
  /**
   * Entitlement only: "upgrade to configure". The install flag
   * (ORGS_SSO_ENABLED) is a separate condition the form reports through the
   * tenant-SSO verdict, so the two are not fused here either.
   */
  const canManageSso = computed(() => can(ENTITLEMENTS.MANAGE_SSO));
  /**
   * The install flag (ORGS_SSO_ENABLED). Off, the page has nothing to offer:
   * every tenant-SSO endpoint refuses, whatever the entitlement, so the page
   * says so instead of showing a form (or an upgrade hint that would not help).
   */
  const ssoAvailableOnInstance = computed(() => isOrgsSsoEnabled());
  /**
   * Both gates the tenant-SSO endpoints enforce. Fetching credentials without
   * the install flag returns "Organization SSO is not enabled on this instance"
   * (DomainsAPI::Logic::SsoConfig::Base), so don't ask.
   */
  const canFetchSsoConfig = computed(() => ssoAvailableOnInstance.value && canManageSso.value);
  const billingRoute = computed(() => `/billing/${props.orgid}/plans`);

  // ---------------------------------------------------------------------------
  // Sign-in details (tenant-SSO verdict)
  // ---------------------------------------------------------------------------

  const {
    isInitialized: signinInitialized,
    tenantSso,
    initialize: initializeSigninConfig,
    refreshDetails: refreshSigninDetails,
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
    isDiagnosing,
    error: ssoConfigError,
    ssoConfig,
    formState: ssoFormState,
    testResult,
    testError,
    diagnosticsResult,
    savedCredentialsChecked,
    savedCredentialsUnchecked,
    diagnosticsError,
    isRefreshingLastSignIn,
    isConfigured: ssoIsConfigured,
    hasUnsavedChanges: ssoHasUnsavedChanges,
    clientSecretMasked,
    metadataFetchUrl,
    metadataPreview,
    isFetchingMetadata,
    metadataFetchFailure,
    canApplyMetadata,
    initialize: initializeSsoConfig,
    saveConfig: saveSsoConfig,
    deleteConfig: deleteSsoConfig,
    testConnection,
    saveAndRunDiagnostics,
    refreshLastSignIn,
    fetchMetadata,
    selectMetadataCertificate,
    applyMetadata,
    discardChanges: discardSsoChanges,
  } = useSsoConfig(props.extid);

  /**
   * The provider's display name once a record exists; the generic title
   * before that (the picker on the create form names the provider).
   */
  const pageHeading = computed(
    () => ssoConfig.value?.display_name?.trim() || t('web.domains.sso.title')
  );

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  /**
   * The tenant-SSO verdict (`details.tenant_sso`) reads the SSO record: it
   * exists, it is on, its provider type can run. An action that may have
   * changed the record is followed by a re-read of the sign-in details, so the
   * form's Confirm sign-in step never acts on the verdict from before it.
   * Skipped without the sign-in entitlement (never fetched).
   */
  const refreshAfterSsoChange = async () => {
    if (canCustomSignin.value) await refreshSigninDetails();
  };

  const handleSsoSave = async () => {
    await saveSsoConfig();
    await refreshAfterSsoChange();
  };

  /** Save (when needed), check, and turn on a passing record that is off. */
  const handleSsoDiagnostics = async () => {
    await saveAndRunDiagnostics();
    await refreshAfterSsoChange();
  };

  const signinRoute = computed(() => ({
    name: 'DomainSignin',
    params: { orgid: props.orgid, extid: props.extid },
  }));

  /**
   * A failed delete keeps the record (useAsyncHandler reports and swallows),
   * so "the record is gone" is the success signal. Only then is there nothing
   * left to show here, and the sign-in page is where the SSO row now reads
   * "not configured".
   */
  const handleSsoDelete = async () => {
    const hadRecord = ssoIsConfigured.value;
    await deleteSsoConfig();
    if (!hadRecord || ssoIsConfigured.value) return;
    await refreshAfterSsoChange();
    router.push(signinRoute.value);
  };

  // Delete is the one destructive action, so it lives in the page's Careful
  // Consideration Zone below the card (as DomainDetail lays out domain
  // removal), with an inline confirm rather than a dialog.
  const showDeleteConfirm = ref(false);

  const confirmSsoDelete = async () => {
    if (ssoDeleting.value) return;
    await handleSsoDelete();
    showDeleteConfirm.value = false;
  };

  const handleRefreshLastSignIn = (passive: boolean) => refreshLastSignIn({ passive });

  /**
   * Confirm sign-in happens in another window (a private window on the
   * custom domain). When the admin comes back to this one, ask for the last
   * sign-in outcome again so it shows without a reload. Throttled because
   * focus and visibility fire together and repeatedly on window switches;
   * the composable also shares an in-flight refresh.
   */
  let lastFocusRefresh = 0;
  const refreshOnReturn = () => {
    if (!ssoIsConfigured.value) return;
    if (document.visibilityState !== 'visible') return;
    const now = Date.now();
    if (now - lastFocusRefresh < BACKGROUND_REFRESH_THROTTLE_MS) return;
    lastFocusRefresh = now;
    handleRefreshLastSignIn(true);
  };

  useEventListener(window, 'focus', refreshOnReturn);
  useEventListener(document, 'visibilitychange', refreshOnReturn);

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  const handleBack = () => {
    router.push(signinRoute.value);
  };

  // Unsaved changes guard: the form saves only on an explicit action.
  useUnsavedRouteGuard(ssoHasUnsavedChanges);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  onMounted(async () => {
    await initializeDomain();

    if (canCustomSignin.value) {
      await initializeSigninConfig();
    }

    if (canFetchSsoConfig.value) {
      await initializeSsoConfig();
    }
  });

  // Handle race condition: organizations (and thus entitlements) may load after
  // onMounted runs. Watch for the entitlement to become true and initialize then.
  watch(canCustomSignin, async (entitled) => {
    if (entitled && !signinInitialized.value) {
      await initializeSigninConfig();
    }
  });

  watch(canFetchSsoConfig, async (allowed) => {
    if (allowed && !ssoInitialized.value) {
      await initializeSsoConfig();
    }
  });
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Header Section. Back returns to the sign-in settings this page hangs
         off; the form's sticky footer owns the actions, so no header Save. -->
    <div class="sticky top-0 z-30">
      <DomainHeader
        :domain="customDomainRecord"
        :has-unsaved-changes="ssoHasUnsavedChanges"
        :orgid="props.orgid"
        external-path="/signin"
        back-visible
        back-label="web.domains.sso.back_to_signin"
        @back="handleBack" />
    </div>

    <!-- Content -->
    <div
      class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8"
      data-testid="domain-signin-sso-page">
      <!-- Loading State. ssoConfigLoading defaults to true and only resolves
           once the record is fetched; for unentitled users we skip that fetch,
           so it must not gate the skeleton or it would spin forever. -->
      <SettingsSkeleton v-if="domainLoading || (canFetchSsoConfig && ssoConfigLoading)" />

      <!-- Error State: the domain, or the record's initial fetch. A failed
           save, check or test also sets the composable's error, but by then
           the record has loaded (ssoInitialized): the form stays up with what
           the admin typed, and the failure is reported by the notification
           and the check panel. Replacing the form here would throw that away. -->
      <div
        v-else-if="domainError || (ssoConfigError && !ssoInitialized)"
        class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="domainError?.message ?? ssoConfigError?.message ?? ''" />
      </div>

      <!-- Tenant SSO off on this install (bookmark, or the redirected old deep
           link). Not an entitlement matter, so it comes before the upgrade
           banner; a form here would only be refused by the API. -->
      <div
        v-else-if="!ssoAvailableOnInstance"
        data-testid="sso-unavailable-on-instance"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <OIcon
          collection="heroicons"
          name="lock-closed"
          class="mx-auto size-12 text-gray-400"
          aria-hidden="true" />
        <h3 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.sso.unavailable_on_instance') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.sso.unavailable_on_instance_hint', { domain: domainHost }) }}
        </p>
        <RouterLink
          :to="signinRoute"
          class="mt-4 inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
          <OIcon
            collection="heroicons"
            name="arrow-left"
            class="size-4"
            aria-hidden="true" />
          {{ t('web.domains.sso.back_to_signin') }}
        </RouterLink>
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

      <!-- SSO Configuration -->
      <template v-else>
        <div class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center gap-3">
              <div
                class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  collection="heroicons"
                  name="shield-check"
                  class="size-5 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0 flex-1">
                <h2
                  class="truncate text-lg font-semibold text-gray-900 dark:text-white"
                  data-testid="sso-page-heading">
                  {{ pageHeading }}
                </h2>
                <p class="mt-0.5 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.domains.sso.page_description', { domain: domainHost }) }}
                </p>
              </div>
            </div>
          </div>

          <!-- No bottom padding: the form's sticky footer sits flush with the
               card's bottom edge. -->
          <div class="px-6 pt-6">
            <DomainSsoConfigForm
              :domain-ext-id="props.extid"
              :org-id="props.orgid"
              :domain-host="domainHost"
              :domain-verified="customDomainRecord?.verified === true"
              v-model:form-state="ssoFormState"
              :sso-config="ssoConfig"
              :is-loading="ssoConfigLoading"
              :is-saving="ssoSaving"
              :is-deleting="ssoDeleting"
              :is-testing="isTesting"
              :is-diagnosing="isDiagnosing"
              :has-unsaved-changes="ssoHasUnsavedChanges"
              :is-configured="ssoIsConfigured"
              :client-secret-masked="clientSecretMasked"
              :test-result="testResult"
              :test-error="testError"
              :diagnostics-result="diagnosticsResult"
              :saved-credentials-checked="savedCredentialsChecked"
              :saved-credentials-unchecked="savedCredentialsUnchecked"
              :diagnostics-error="diagnosticsError"
              :is-refreshing-last-sign-in="isRefreshingLastSignIn"
              :tenant-sso="tenantSso"
              :saml-enabled="isSamlEnabled()"
              v-model:metadata-fetch-url="metadataFetchUrl"
              :metadata-preview="metadataPreview"
              :is-fetching-metadata="isFetchingMetadata"
              :metadata-fetch-failure="metadataFetchFailure"
              :can-apply-metadata="canApplyMetadata"
              @fetch-metadata="fetchMetadata"
              @select-metadata-certificate="selectMetadataCertificate"
              @apply-metadata="applyMetadata"
              @save="handleSsoSave"
              @test="testConnection"
              @diagnostics="handleSsoDiagnostics"
              @refresh-last-sign-in="handleRefreshLastSignIn(false)"
              @discard="discardSsoChanges" />
          </div>
        </div>

        <!-- Careful Consideration Zone: outside and below the card, only once
             there is a record to delete. -->
        <template v-if="ssoIsConfigured">
          <hr class="my-10 border-gray-200 dark:border-gray-700/50" />
          <section
            data-testid="sso-caution-zone"
            aria-labelledby="sso-caution-zone-title">
            <h2
              id="sso-caution-zone-title"
              class="mb-4 text-sm font-medium text-red-600 dark:text-red-400">
              {{ t('web.COMMON.caution_zone') }}
            </h2>
            <div
              class="rounded-lg border border-red-200 bg-red-50/50 dark:border-red-900/50 dark:bg-red-950/20">
              <div
                class="flex flex-col items-start gap-4 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
                <div class="flex min-w-0 items-center gap-4">
                  <div
                    class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-red-100 dark:bg-red-900/30">
                    <OIcon
                      collection="heroicons"
                      name="trash"
                      class="size-5 text-red-600 dark:text-red-400"
                      aria-hidden="true" />
                  </div>
                  <div class="min-w-0">
                    <h3 class="font-brand text-sm font-semibold text-gray-900 dark:text-white">
                      {{ t('web.organizations.sso.delete_config') }}
                    </h3>
                    <p class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                      {{ t('web.organizations.sso.delete_config_hint') }}
                    </p>
                  </div>
                </div>
                <!-- The box title names the action in full; the button carries
                     the short verb, as DomainDetail pairs "Remove domain" with
                     "Remove". -->
                <button
                  v-if="!showDeleteConfirm"
                  type="button"
                  data-testid="sso-delete"
                  :disabled="ssoDeleting || ssoSaving"
                  class="shrink-0 rounded-md border border-red-300 bg-white px-3 py-1.5 text-sm font-medium text-red-600 transition-colors hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-700 dark:bg-transparent dark:text-red-400 dark:hover:bg-red-950/50 dark:focus:ring-offset-gray-900"
                  @click="showDeleteConfirm = true">
                  {{ t('web.COMMON.delete') }}
                </button>
                <div
                  v-else
                  class="flex flex-wrap items-center gap-2">
                  <span class="text-sm text-gray-600 dark:text-gray-400">
                    {{ t('web.organizations.sso.delete_confirm') }}
                  </span>
                  <button
                    type="button"
                    data-testid="sso-delete-confirm"
                    :disabled="ssoDeleting"
                    class="inline-flex items-center rounded-md bg-red-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-500 dark:hover:bg-red-400"
                    @click="confirmSsoDelete">
                    {{ ssoDeleting ? t('web.COMMON.processing') : t('web.COMMON.yes_delete') }}
                  </button>
                  <button
                    type="button"
                    data-testid="sso-delete-cancel"
                    :disabled="ssoDeleting"
                    class="inline-flex items-center rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600"
                    @click="showDeleteConfirm = false">
                    {{ t('web.COMMON.word_cancel') }}
                  </button>
                </div>
              </div>
            </div>
          </section>
        </template>
      </template>
    </div>
  </div>
</template>
