// src/shared/composables/useSsoConfig.ts

/**
 * Composable for managing per-domain SSO configuration.
 *
 * Follows the useEmailConfig lifecycle pattern:
 * - initialize: fetch current config (404 = unconfigured, not error)
 * - saveConfig: auto-selects PUT (new) vs PATCH (update) via SsoService;
 *   never sends the form's `enabled` (PATCH omits it, PUT carries the stored value)
 * - deleteConfig: removes config
 * - testConnection: validates IdP connectivity before saving; the result is
 *   bound to the fields it was run against and cleared when any of them change
 * - runDiagnostics: checks the SAVED record (stored fields, discovery,
 *   certificate or stored client secret); the result describes the record as
 *   last saved and is cleared whenever that record changes (save, delete),
 *   never by an unsaved edit. A record that is off asks for activation: a
 *   passing run turns it on, and nothing else does.
 * - saveAndRunDiagnostics: saves unsaved edits (or a new record) first, then
 *   runs the check
 * - refreshLastSignIn: re-reads only the record's last sign-in outcome
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * @param domainExtId - Domain external ID for API calls
 */

import type {
  PatchSsoConfigRequest,
  PutSsoConfigRequest,
} from '@/schemas/api/domains/requests/sso-config';
import type { ApplicationError } from '@/schemas/errors';
import {
  ssoProviderUsesClientCredentials,
  type CustomDomainSsoConfig,
  type SsoProviderType,
  type SsoTokenEndpointAuthMethodRequest,
} from '@/schemas/shapes/domains/sso-config';
import {
  SsoService,
  type SsoDiagnosticsResponse,
  type TestSsoConnectionRequest,
  type TestSsoConnectionResponse,
} from '@/services/sso.service';
import { useNotificationsStore } from '@/shared/stores';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';

/**
 * Form state for SSO configuration.
 *
 * Note: client_secret is write-only. It's never populated from API responses
 * (which return a masked value), only from user input.
 *
 * The SAML trio (#4450) is NOT write-only: the API returns it in plaintext
 * (none is a secret; an IdP publishes all three), so the form is seeded with
 * the stored values and re-sends them. A field the API names in
 * `unreadable_fields` is seeded EMPTY so the admin has to re-enter it — the
 * error state lives on ssoConfig.unreadable_fields, not here.
 *
 * token_endpoint_auth_method (#4764, oidc only) is '' for "Automatic" (the
 * record's null); the select only ever writes a contract value.
 *
 * `enabled` mirrors the stored record and has no control: the record is
 * created off and only a passing saved-configuration check turns it on. It
 * stays here so the snapshot comparison and hydration keep one shape.
 */
export interface SsoConfigFormState {
  provider_type: SsoProviderType;
  display_name: string;
  client_id: string;
  client_secret: string;
  tenant_id: string;
  issuer: string;
  token_endpoint_auth_method: SsoTokenEndpointAuthMethodRequest;
  idp_sso_service_url: string;
  idp_entity_id: string;
  idp_cert: string;
  allowed_domains: string[];
  enabled: boolean;
  enforce_sso_only: boolean;
  grant_org_scope: boolean;
}

/**
 * Every scalar form field, compared by identity for unsaved-change detection.
 * allowed_domains is the one array and is compared order-insensitively.
 */
const SCALAR_FORM_FIELDS = [
  'provider_type',
  'display_name',
  'client_id',
  'client_secret',
  'tenant_id',
  'issuer',
  'token_endpoint_auth_method',
  'idp_sso_service_url',
  'idp_entity_id',
  'idp_cert',
  'enabled',
  'enforce_sso_only',
  'grant_org_scope',
] as const satisfies readonly Exclude<keyof SsoConfigFormState, 'allowed_domains'>[];

function createDefaultFormState(): SsoConfigFormState {
  return {
    provider_type: 'entra_id',
    display_name: '',
    client_id: '',
    client_secret: '',
    tenant_id: '',
    issuer: '',
    token_endpoint_auth_method: '',
    idp_sso_service_url: '',
    idp_entity_id: '',
    idp_cert: '',
    allowed_domains: [],
    enabled: false,
    enforce_sso_only: false,
    grant_org_scope: false,
  };
}

/**
 * Order-insensitive array equality check for string arrays.
 */
function arraysEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const sortedA = [...a].sort();
  const sortedB = [...b].sort();
  return sortedA.every((val, idx) => val === sortedB[idx]);
}

/**
 * Convert API response to form state.
 *
 * CRITICAL: Never populate client_secret from API response.
 * The API returns a masked value (e.g., "********1234") which would
 * corrupt the credential if saved back.
 *
 * The SAML trio is plaintext on the wire and is seeded as stored. A null the
 * API ALSO lists in unreadable_fields is a reveal failure, not "unset"; the
 * `?? ''` here is the same either way, which is what we want — a blank input
 * plus the error state rendered from unreadable_fields, so the only way
 * forward is to re-enter the value (the API refuses a blank trio field on
 * PATCH unless the stored one is readable).
 */
function configToFormState(config: CustomDomainSsoConfig): SsoConfigFormState {
  return {
    provider_type: config.provider_type,
    display_name: config.display_name,
    client_id: config.client_id,
    client_secret: '', // Never populate from API
    tenant_id: config.tenant_id ?? '',
    issuer: config.issuer ?? '',
    token_endpoint_auth_method: config.token_endpoint_auth_method ?? '',
    idp_sso_service_url: config.idp_sso_service_url ?? '',
    idp_entity_id: config.idp_entity_id ?? '',
    idp_cert: config.idp_cert ?? '',
    allowed_domains: config.allowed_domains ?? [],
    enabled: config.enabled,
    enforce_sso_only: config.enforce_sso_only,
    grant_org_scope: config.grant_org_scope,
  };
}

function usesClientCredentials(state: SsoConfigFormState): boolean {
  return ssoProviderUsesClientCredentials(state.provider_type);
}

/**
 * The exact payload `testConnection` sends, as a comparable string. A test
 * result is only meaningful for the fields the test was run against, so this
 * is also the definition of "test-affecting": any edit that changes it makes
 * the last result stale (see the watcher in useSsoConfig). display_name,
 * enabled, enforce_sso_only, grant_org_scope, allowed_domains and
 * client_secret are not sent to the test and so do not count.
 */
function testFingerprint(state: SsoConfigFormState): string {
  return JSON.stringify({ provider_type: state.provider_type, ...providerFields(state) });
}

/**
 * Whether a diagnostics result is about `record`. The API checks whatever is
 * stored when the request lands, so a save from another tab after this page
 * loaded makes the result about credentials the page has never seen.
 * configuration_revision is SsoConfig#updated in whole seconds, the value the
 * record carries as updated_at; a save within the same second as the loaded
 * one is not told apart.
 */
function diagnosticsDescribeRecord(
  result: SsoDiagnosticsResponse,
  record: CustomDomainSsoConfig
): boolean {
  return (
    result.provider_type === record.provider_type &&
    result.configuration_revision === String(Math.floor(record.updated_at.getTime() / 1000))
  );
}

/**
 * The provider-scoped request fields for the current provider type, trimmed,
 * with blanks omitted. Shared by save and test so the two cannot disagree.
 *
 * Only the side the provider uses is sent: the API clears the other side on
 * write regardless (an unvalidated trust anchor must not sit on the record
 * waiting for a provider_type flip), so sending it would only be noise — and
 * for saml, a client_id would be validated as "required" by the zod PUT
 * schema for the wrong provider. Blank SAML fields are omitted rather than
 * sent as '' so that on an existing saml record PATCH preserves the stored
 * value (a listed unreadable field is blank here and the API then refuses
 * with a `missing` error naming it — the intended re-entry loop).
 *
 * token_endpoint_auth_method (#4764) is the one blank that is NOT dropped:
 * on PATCH a present '' clears the stored method back to the default while
 * an absent key keeps it, so "Automatic" has to travel as ''. oidc only —
 * the API clears it for the other types and the select is not shown.
 */
function providerFields(state: SsoConfigFormState): {
  client_id?: string;
  tenant_id?: string;
  issuer?: string;
  token_endpoint_auth_method?: SsoTokenEndpointAuthMethodRequest;
  idp_sso_service_url?: string;
  idp_entity_id?: string;
  idp_cert?: string;
} {
  if (state.provider_type === 'saml') {
    return {
      idp_sso_service_url: state.idp_sso_service_url.trim() || undefined,
      idp_entity_id: state.idp_entity_id.trim() || undefined,
      idp_cert: state.idp_cert.trim() || undefined,
    };
  }

  return {
    client_id: state.client_id.trim(),
    tenant_id: state.tenant_id.trim() || undefined,
    issuer: state.issuer.trim() || undefined,
    ...(state.provider_type === 'oidc'
      ? { token_endpoint_auth_method: state.token_endpoint_auth_method }
      : {}),
  };
}

/**
 * The PUT/PATCH body for a save. `enabled` is passed in: it is the stored
 * record's value, never the form's (see saveConfig).
 *
 * client_secret is included only when entered (non-empty), and never for
 * saml, which has no client credential: the API discards it anyway, and its
 * presence is what routes the save to PUT (see SsoService).
 */
function savePayload(
  state: SsoConfigFormState,
  enabled: boolean
): PutSsoConfigRequest | PatchSsoConfigRequest {
  const payload: PutSsoConfigRequest | PatchSsoConfigRequest = {
    provider_type: state.provider_type,
    display_name: state.display_name.trim(),
    ...providerFields(state),
    allowed_domains: state.allowed_domains,
    enforce_sso_only: state.enforce_sso_only,
    grant_org_scope: state.grant_org_scope,
  };
  if (usesClientCredentials(state) && state.client_secret.trim()) {
    (payload as PutSsoConfigRequest).client_secret = state.client_secret.trim();
    // PUT replaces the record and defaults an absent `enabled` to false, so
    // it carries the stored value. PATCH omits it and the server keeps what
    // it holds, which a copy older than an activation elsewhere cannot undo.
    payload.enabled = enabled;
  }
  return payload;
}

/* eslint max-lines-per-function: off */
export function useSsoConfig(domainExtId: string) {
  const notifications = useNotificationsStore();
  const { t } = useI18n();
  const router = useRouter();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /** Whether the initial config fetch is in progress. */
  const isLoading = ref(true);
  /** Whether `initialize` has completed at least once. */
  const isInitialized = ref(false);
  /** Whether a save (PUT/PATCH) request is in flight. */
  const isSaving = ref(false);
  /** Whether a delete request is in flight. */
  const isDeleting = ref(false);
  /** Whether a test connection request is in flight. */
  const isTesting = ref(false);
  /** Whether a saved-configuration diagnostics request is in flight. */
  const isDiagnosing = ref(false);
  /** The most recent API error, or null. */
  const error = ref<ApplicationError | null>(null);

  /** The full config object from the API. Null = unconfigured (404). */
  const ssoConfig = ref<CustomDomainSsoConfig | null>(null);

  /** Current form state (editable). */
  const formState = ref<SsoConfigFormState>(createDefaultFormState());

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<SsoConfigFormState | null>(null);

  /** Result from the last test connection attempt. */
  const testResult = ref<TestSsoConnectionResponse | null>(null);

  /** Error message from the last failed test connection attempt. */
  const testError = ref<string>('');

  /**
   * Fingerprint of the form fields the last test was run against, or null
   * when there is no result to protect. Compared, not flagged: a change to
   * any other field leaves the result alone, and a hydration that lands on
   * the same test payload (a save of what was just tested) keeps it too.
   */
  const testedFingerprint = ref<string | null>(null);

  const clearTestResult = () => {
    testResult.value = null;
    testError.value = '';
    testedFingerprint.value = null;
  };

  /** Result from the last saved-configuration diagnostics run. */
  const diagnosticsResult = ref<SsoDiagnosticsResponse | null>(null);

  /** Passing checks survive flag-only saves, independently of the displayed verdict. */
  const checkedCredentialsFingerprint = ref<string | null>(null);

  /**
   * A save in this session changed the stored credentials (a new secret, or
   * a different credential field on the returned record) and no passing run
   * has covered them since. Drives the advisory "not checked" warning on a
   * connection that is already on: after such a save the form matches the
   * record again, so the form alone cannot tell. Cleared by a passing run,
   * a reload and a delete.
   */
  const savedCredentialsUnchecked = ref(false);

  /** Error message from the last diagnostics run that produced no result. */
  const diagnosticsError = ref<string>('');

  /** Whether a last-sign-in refresh is in flight. */
  const isRefreshingLastSignIn = ref(false);

  /**
   * A diagnostics result is about the saved record, so it is cleared when
   * that record changes (save, delete) — not by a form edit, which the
   * test-result fingerprint watcher handles for Test Connection.
   */
  /**
   * Runs are numbered. Every clear (a new run, or the saved record changing
   * under save / delete) advances the number, and a response from
   * an earlier run is dropped when it lands: it describes a record that is
   * no longer the saved one. Save and delete are not blocked while a run is
   * in flight, so this is what keeps a late response from repopulating the
   * result after the record it checked was replaced or removed.
   */
  let diagnosticsRun = 0;

  const clearDiagnosticsResult = () => {
    diagnosticsRun += 1;
    diagnosticsResult.value = null;
    diagnosticsError.value = '';
  };

  /**
   * Advanced when the record may have been replaced wholesale (a reload, a
   * delete), so a last-sign-in refresh that was in flight is not merged into
   * a different record.
   */
  let recordGeneration = 0;

  /**
   * Replace the form with a record from the API (load, save). A result in
   * view survives only when the record carries the fields it was tested
   * against (a save of what was just tested, a reload of the same record).
   * The watcher below judges the hydrated values exactly as it judges an
   * edit, so a record that differs in a tested field (a method or issuer
   * saved elsewhere, a value the server rewrote) clears the result rather
   * than letting it describe settings the form no longer shows.
   */
  const hydrateFormState = (next: SsoConfigFormState) => {
    formState.value = next;
  };

  watch(
    formState,
    (state) => {
      if (testedFingerprint.value === null) return;
      if (testFingerprint(state) !== testedFingerprint.value) clearTestResult();
    },
    // sync: an edit invalidates before anything else (a hydration in the same
    // tick, a render) can observe a result that no longer matches the form.
    { deep: true, flush: 'sync' }
  );

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity, 'top'),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      if (err.code === 404) {
        return router.push({ name: 'NotFound' });
      }
      error.value = err;
    },
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  // A second handler for save/delete/test actions that should NOT toggle
  // isLoading (which controls the full-page loading state). These actions
  // manage their own loading flags (isSaving, isDeleting, isTesting).
  const { wrap: wrapAction } = useAsyncHandler({
    ...defaultAsyncHandlerOptions,
    setLoading: undefined,
  });

  // A third for the last-sign-in refresh: it often runs without anyone
  // asking (focus, visibility), so a failure keeps what is shown — no toast,
  // no page error, no NotFound redirect.
  const { wrap: wrapRefresh } = useAsyncHandler({
    notify: false,
  });

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /** Whether an SSO config exists for this domain. */
  const isConfigured = computed(() => ssoConfig.value !== null);

  /** Whether SSO is both configured AND enabled. */
  const isEnabled = computed(() => ssoConfig.value?.enabled ?? false);

  /** The masked client secret from the existing config (for display purposes). */
  const clientSecretMasked = computed(() => ssoConfig.value?.client_secret_masked ?? null);

  /**
   * Encrypted fields the API could not reveal for the stored record (#4450).
   * Empty for a healthy record. A named field's value is unknown, not unset:
   * the form must show an error state and demand re-entry.
   */
  const unreadableFields = computed(() => ssoConfig.value?.unreadable_fields ?? []);

  const savedCredentialsChecked = computed(
    () =>
      ssoConfig.value !== null &&
      checkedCredentialsFingerprint.value !== null &&
      testFingerprint(configToFormState(ssoConfig.value)) === checkedCredentialsFingerprint.value
  );

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    const current = formState.value;
    const saved = savedFormState.value;
    return (
      SCALAR_FORM_FIELDS.some((field) => current[field] !== saved[field]) ||
      !arraysEqual(current.allowed_domains, saved.allowed_domains)
    );
  });

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /**
   * Load the current SSO config for this domain.
   * 404 is treated as "unconfigured" (ssoConfig = null), not an error.
   */
  const initialize = () =>
    wrap(async () => {
      const response = await SsoService.getConfigForDomain(domainExtId);
      recordGeneration += 1;
      ssoConfig.value = response.record;
      // A reload may include a secret changed elsewhere; its value is never returned.
      checkedCredentialsFingerprint.value = null;
      savedCredentialsUnchecked.value = false;
      clearDiagnosticsResult();

      hydrateFormState(
        response.record ? configToFormState(response.record) : createDefaultFormState()
      );
      savedFormState.value = {
        ...formState.value,
        allowed_domains: [...formState.value.allowed_domains],
      };
      isInitialized.value = true;
    });

  /**
   * Save the current form state.
   * Uses SsoService.saveConfigForDomain which auto-selects PUT vs PATCH
   * based on whether client_secret is provided (so a saml save is always a
   * PATCH; PATCH creates when no record exists).
   *
   * A save keeps the connection as it is and never sends the form's
   * `enabled`. PATCH omits the field, so the server keeps what it holds.
   * PUT, the path a new secret takes, defaults an absent `enabled` to false,
   * so it carries the stored record's value (false for a new record).
   *
   * @returns true when the API returned the saved record
   */
  const saveConfig = async (): Promise<boolean> => {
    if (isSaving.value || isDeleting.value) return false;
    isSaving.value = true;
    error.value = null;
    const sendsSecret =
      usesClientCredentials(formState.value) && formState.value.client_secret.trim() !== '';
    const preservesCredentialCheck =
      savedCredentialsChecked.value &&
      testFingerprint(formState.value) === checkedCredentialsFingerprint.value &&
      !sendsSecret;
    const previousCredentials = ssoConfig.value
      ? testFingerprint(configToFormState(ssoConfig.value))
      : null;

    try {
      const result = await wrapAction(() =>
        SsoService.saveConfigForDomain(
          domainExtId,
          savePayload(formState.value, ssoConfig.value?.enabled ?? false)
        )
      );
      if (!result?.record) return false;

      applySavedRecord(result.record, {
        keepsCredentialCheck: preservesCredentialCheck,
        credentialsChanged:
          sendsSecret || testFingerprint(configToFormState(result.record)) !== previousCredentials,
      });
      notifications.show(t('web.domains.sso.update_success'), 'success', 'top');
      return true;
    } finally {
      isSaving.value = false;
    }
  };

  /**
   * Adopt the record a save returned. A passing check survives only a save
   * that kept the credentials it covered; a save that changed them leaves
   * them unchecked until the next passing run.
   */
  const applySavedRecord = (
    record: CustomDomainSsoConfig,
    outcome: { keepsCredentialCheck: boolean; credentialsChanged: boolean }
  ) => {
    ssoConfig.value = record;
    if (!outcome.keepsCredentialCheck || !savedCredentialsChecked.value) {
      checkedCredentialsFingerprint.value = null;
    }
    if (outcome.credentialsChanged) savedCredentialsUnchecked.value = true;
    hydrateFormState(configToFormState(record));
    savedFormState.value = {
      ...formState.value,
      allowed_domains: [...formState.value.allowed_domains],
    };
    clearDiagnosticsResult();
  };

  /**
   * Delete the SSO config for this domain.
   */
  const deleteConfig = async () => {
    isDeleting.value = true;
    error.value = null;

    try {
      await wrapAction(async () => {
        await SsoService.deleteConfigForDomain(domainExtId);
        recordGeneration += 1;
        ssoConfig.value = null;
        formState.value = createDefaultFormState();
        clearTestResult();
        clearDiagnosticsResult();
        checkedCredentialsFingerprint.value = null;
        savedCredentialsUnchecked.value = false;
        savedFormState.value = {
          ...formState.value,
          allowed_domains: [...formState.value.allowed_domains],
        };
        notifications.show(t('web.domains.sso.delete_success'), 'success', 'top');
      });
    } finally {
      isDeleting.value = false;
    }
  };

  /**
   * Test the SSO connection using current form credentials.
   * Tests against the IdP without saving the configuration.
   */
  const testConnection = async () => {
    isTesting.value = true;
    clearTestResult();

    try {
      // Snapshot what is sent: a result is only shown if the form still
      // matches it when the response lands (an edit made while the request
      // was in flight discards it, the same as an edit made afterwards).
      const tested: TestSsoConnectionRequest = {
        provider_type: formState.value.provider_type,
        ...providerFields(formState.value),
      };
      const fingerprint = JSON.stringify(tested);
      const result = await wrapAction(() =>
        SsoService.testConnectionForDomain(domainExtId, tested)
      );

      if (result && testFingerprint(formState.value) === fingerprint) {
        testResult.value = result;
        testedFingerprint.value = fingerprint;
        if (result.success) {
          notifications.show(t('web.domains.sso.test_success'), 'success', 'top');
        } else {
          testError.value = result.message || t('web.domains.sso.test_failed');
          notifications.show(testError.value, 'error', 'top');
        }
      }
    } finally {
      isTesting.value = false;
    }
  };

  /**
   * Check the SAVED configuration: the API reloads the stored record and
   * reports each layer (stored fields, discovery, certificate, or the stored
   * client secret for Entra) separately. Nothing from the form is sent.
   *
   * A transport failure (the request itself failed, so there is no verdict)
   * is reported through diagnosticsError; a result whose overall is "failed"
   * is a verdict and lives in diagnosticsResult.
   *
   * A record that is off asks for activation (`activate: true`): the API
   * turns it on when the run passes and the stored credentials are still the
   * ones checked. A record that is on does not ask; no run turns one off.
   * The response's `enabled` is copied onto the record and both form
   * snapshots, so the next save re-sends the state the server now holds.
   */
  const runDiagnostics = async () => {
    if (isDiagnosing.value) return;
    isDiagnosing.value = true;
    clearDiagnosticsResult();
    checkedCredentialsFingerprint.value = null;
    const record = ssoConfig.value;
    const fingerprint = record ? testFingerprint(configToFormState(record)) : null;
    const activate = record !== null && !record.enabled;
    const run = diagnosticsRun;
    // The handler records the failure here; a stale one must not be read
    // as this run's.
    error.value = null;

    try {
      const result = await wrapAction(() =>
        activate
          ? SsoService.runDiagnosticsForDomain(domainExtId, { activate: true })
          : SsoService.runDiagnosticsForDomain(domainExtId)
      );

      // The saved record changed while this run was in flight (see
      // clearDiagnosticsResult): the response is about the old record.
      if (run !== diagnosticsRun) return;

      if (result) {
        diagnosticsResult.value = result;
        // A pass for a record saved elsewhere is not evidence for the loaded
        // one: the credentials-unchecked state stays until a reload and recheck.
        if (result.overall === 'passed' && record && diagnosticsDescribeRecord(result, record)) {
          checkedCredentialsFingerprint.value = fingerprint;
          savedCredentialsUnchecked.value = false;
        }
        applyEnabledFromRun(result.enabled);
        notifyDiagnosticsOutcome(result.overall);
      } else {
        diagnosticsError.value = diagnosticsFailureMessage(error.value);
      }
    } finally {
      isDiagnosing.value = false;
    }
  };

  /**
   * Mirror the stored `enabled` a run reported. Only that field changes:
   * unsaved edits in the form stay as they are, and the saved snapshot moves
   * with it so the change does not read as an unsaved edit.
   */
  const applyEnabledFromRun = (enabled: boolean | undefined) => {
    if (typeof enabled !== 'boolean' || !ssoConfig.value) return;
    if (ssoConfig.value.enabled === enabled) return;
    ssoConfig.value = { ...ssoConfig.value, enabled };
    formState.value = { ...formState.value, enabled };
    if (savedFormState.value) {
      savedFormState.value = { ...savedFormState.value, enabled };
    }
  };

  /**
   * The dialog's one primary action: save a new record or unsaved edits
   * first, then run the saved-configuration check (which turns a record that
   * is off on when it passes). A save that fails or is refused stops here,
   * so the check never runs against a record the admin did not mean to keep.
   */
  const saveAndRunDiagnostics = async () => {
    if (isDiagnosing.value) return;
    if (ssoConfig.value === null || hasUnsavedChanges.value) {
      const saved = await saveConfig();
      if (!saved) return;
    }
    await runDiagnostics();
  };

  /**
   * Re-read the record's last sign-in outcome while the dialog is open, so
   * an admin who just signed in through the custom domain sees the result
   * without reloading. Only `last_sign_in` is taken from the response:
   * form edits, the saved snapshot and every other field stay as they are.
   *
   * `passive` marks a refresh no person asked for (the window regaining
   * focus or visibility) so it does not count as session activity (see
   * src/types/declarations/axios.d.ts). A refresh already in flight is
   * shared rather than repeated: focus and visibility often fire together.
   */
  let lastSignInRefresh: Promise<void> | null = null;

  const refreshLastSignIn = (options: { passive?: boolean } = {}): Promise<void> => {
    if (lastSignInRefresh) return lastSignInRefresh;
    if (!ssoConfig.value) return Promise.resolve();
    const generation = recordGeneration;
    isRefreshingLastSignIn.value = true;
    lastSignInRefresh = (async () => {
      try {
        const response = await wrapRefresh(() =>
          options.passive
            ? SsoService.getConfigForDomain(domainExtId, { passive: true })
            : SsoService.getConfigForDomain(domainExtId)
        );
        const record = response?.record;
        // A reload or delete landed meanwhile; that path set the record.
        if (!record || !ssoConfig.value || generation !== recordGeneration) return;
        ssoConfig.value = { ...ssoConfig.value, last_sign_in: record.last_sign_in };
      } finally {
        isRefreshingLastSignIn.value = false;
        lastSignInRefresh = null;
      }
    })();
    return lastSignInRefresh;
  };

  const notifyDiagnosticsOutcome = (overall: SsoDiagnosticsResponse['overall']) => {
    if (overall === 'passed') {
      notifications.show(t('web.domains.sso.diagnostics_passed'), 'success', 'top');
    } else if (overall === 'failed') {
      notifications.show(t('web.domains.sso.diagnostics_failed'), 'error', 'top');
    } else {
      notifications.show(t('web.domains.sso.diagnostics_inconclusive'), 'warning', 'top');
    }
  };

  /**
   * The inline message for a run that produced no verdict. A 429 is the
   * per-customer run limit (the API's LimitExceeded body carries
   * retry_after in seconds); everything else is a generic transport failure.
   */
  const diagnosticsFailureMessage = (failure: ApplicationError | null): string => {
    if (failure?.code !== 429) return t('web.domains.sso.diagnostics_error');

    const retryAfter = Number(failure.details?.retry_after);
    if (!Number.isFinite(retryAfter) || retryAfter <= 0) {
      return t('web.domains.sso.diagnostics_rate_limited');
    }
    return t('web.domains.sso.diagnostics_rate_limited_retry', {
      minutes: Math.max(1, Math.ceil(retryAfter / 60)),
    });
  };

  /**
   * Reset form to last-saved state.
   */
  const discardChanges = () => {
    if (savedFormState.value) {
      formState.value = {
        ...savedFormState.value,
        allowed_domains: [...savedFormState.value.allowed_domains],
      };
    }
  };

  return {
    // State
    isLoading,
    isInitialized,
    isSaving,
    isDeleting,
    isTesting,
    isDiagnosing,
    error,
    ssoConfig,
    formState,
    testResult,
    testError,
    diagnosticsResult,
    diagnosticsError,
    savedCredentialsUnchecked,
    isRefreshingLastSignIn,

    // Computed
    isConfigured,
    isEnabled,
    clientSecretMasked,
    unreadableFields,
    savedCredentialsChecked,
    hasUnsavedChanges,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    testConnection,
    runDiagnostics,
    saveAndRunDiagnostics,
    refreshLastSignIn,
    discardChanges,
  };
}
