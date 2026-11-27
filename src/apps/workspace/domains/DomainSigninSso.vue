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
  import { useEntitlements } from '@/shared/composables/useEntitlements';
  import { useTenantSsoPermissions } from '@/shared/composables/useResourcePermissions';
  import { useSigninConfig } from '@/shared/composables/useSigninConfig';
  import { useSsoConfig } from '@/shared/composables/useSsoConfig';
  import { useUnsavedRouteGuard } from '@/shared/composables/useUnsavedRouteGuard';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { ENTITLEMENTS } from '@/types/organization';
  import { isOrgsSsoEnabled, isSamlEnabled } from '@/utils/features';
  import { useEventListener } from '@vueuse/core';
  import { storeToRefs } from 'pinia';
  import { computed, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRouter } from 'vue-router';

  const { t } = useI18n();
  const router = useRouter();

  const props = defineProps<{
    orgid: string;
    extid: string;
  }>();

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
  const { canManageSso, canViewDomain, domain, isLoading: permissionLoading, refresh: refreshPermission } = useTenantSsoPermissions(
    () => props.orgid,
    () => props.extid
  );
  const domainHost = computed(() => domain.value?.display_domain ?? '');
  const ssoAvailableOnInstance = computed(() => isOrgsSsoEnabled());
  const canFetchSsoConfig = computed(() => ssoAvailableOnInstance.value && canManageSso.value === true);

  // ---------------------------------------------------------------------------
  // Sign-in details (tenant-SSO verdict)
  // ---------------------------------------------------------------------------

  const {
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
    if (canFetchSsoConfig.value && canCustomSignin.value) await refreshSigninDetails();
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

  const returnTarget = computed(() => {
    if (!canFetchSsoConfig.value) {
      return { to: '/dashboard', label: 'web.settings.back_to_dashboard' };
    }
    const role = organization.value?.current_user_role;
    if ((role === 'owner' || role === 'admin') && canViewDomain.value && canCustomSignin.value) {
      return { to: { name: 'DomainSignin', params: { orgid: props.orgid, extid: props.extid } },
        label: 'web.domains.sso.back_to_signin' };
    }
    return { to: { name: 'Organization Settings', params: { extid: props.orgid, tab: 'sso' } },
      label: 'web.organizations.sso.domain_sso_title' };
  });

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
    router.push(returnTarget.value.to);
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
    if (!canFetchSsoConfig.value || !ssoIsConfigured.value) return;
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
    router.push(returnTarget.value.to);
  };

  // Unsaved changes guard: the form saves only on an explicit action.
  useUnsavedRouteGuard(ssoHasUnsavedChanges);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  // Sign-in details supply the runtime verdict and have a separate feature gate.
  watch(() => canFetchSsoConfig.value && canCustomSignin.value, (allowed) => {
    if (allowed) void initializeSigninConfig();
  }, { immediate: true });

  watch(canFetchSsoConfig, (allowed) => {
    if (allowed) void initializeSsoConfig();
  }, { immediate: true });
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Return to settings the current member can open. -->
    <div class="sticky top-[var(--stale-session-notice-height,0px)] z-30">
      <DomainHeader
        :display-domain="domainHost"
        :has-unsaved-changes="ssoHasUnsavedChanges"
        :orgid="props.orgid"
        external-path="/signin"
        back-visible
        :back-label="returnTarget.label"
        @back="handleBack" />
    </div>

    <!-- Content -->
    <div
      class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8"
      data-testid="domain-signin-sso-page">
      <!-- A denied member never fetches the record, so only wait for an allowed read. -->
      <SettingsSkeleton v-if="(ssoAvailableOnInstance && permissionLoading) || (canFetchSsoConfig && ssoConfigLoading)" />

      <!-- Error from the record's initial fetch. A failed
           save, check or test also sets the composable's error, but by then
           the record has loaded (ssoInitialized): the form stays up with what
           the admin typed, and the failure is reported by the notification
           and the check panel. Replacing the form here would throw that away. -->
      <div
        v-else-if="canFetchSsoConfig && ssoConfigError && !ssoInitialized"
        class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
        <BasicFormAlerts :error="ssoConfigError.message" />
      </div>

      <!-- Old links can still point to tenant SSO after it is disabled. -->
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
        <p v-if="domainHost" class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.sso.unavailable_on_instance_hint', { domain: domainHost }) }}
        </p>
        <RouterLink
          :to="returnTarget.to"
          class="mt-4 inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
          <OIcon
            collection="heroicons"
            name="arrow-left"
            class="size-4"
            aria-hidden="true" />
          {{ t(returnTarget.label) }}
        </RouterLink>
      </div>

      <div
        v-else-if="canManageSso === undefined"
        role="status"
        class="rounded-lg bg-white p-8 text-center dark:bg-gray-800">
        <p>{{ t('web.domains.sso.access_unconfirmed') }}</p>
        <button
          type="button"
          class="mt-4 text-brand-600 hover:underline dark:text-brand-400"
          @click="refreshPermission()">
          {{ t('web.domains.sso.retry_access') }}
        </button>
      </div>
      <div
        v-else-if="!canManageSso"
        class="rounded-lg border border-gray-200 bg-white p-8 text-center dark:border-gray-700 dark:bg-gray-800">
        <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.domains.sso.access_denied') }}
        </h3>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.sso.access_denied_description') }}
        </p>
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
              :domain-verified="domain?.verified === true"
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
