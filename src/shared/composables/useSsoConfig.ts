// src/shared/composables/useSsoConfig.ts

/**
 * Composable for managing per-domain SSO configuration.
 *
 * Follows the useEmailConfig lifecycle pattern:
 * - initialize: fetch current config (404 = unconfigured, not error)
 * - saveConfig: auto-selects PUT (new) vs PATCH (update) via SsoService
 * - deleteConfig: removes config
 * - testConnection: validates IdP connectivity before saving
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
} from '@/schemas/shapes/domains/sso-config';
import {
  SsoService,
  type TestSsoConnectionRequest,
  type TestSsoConnectionResponse,
} from '@/services/sso.service';
import { useNotificationsStore } from '@/shared/stores';
import { computed, ref } from 'vue';
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
 */
export interface SsoConfigFormState {
  provider_type: SsoProviderType;
  display_name: string;
  client_id: string;
  client_secret: string;
  tenant_id: string;
  issuer: string;
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
 */
function providerFields(state: SsoConfigFormState): {
  client_id?: string;
  tenant_id?: string;
  issuer?: string;
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
  };
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
      ssoConfig.value = response.record;

      if (response.record) {
        formState.value = configToFormState(response.record);
      } else {
        formState.value = createDefaultFormState();
      }
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
   */
  const saveConfig = async () => {
    isSaving.value = true;
    error.value = null;

    try {
      const result = await wrapAction(async () => {
        const payload: PutSsoConfigRequest | PatchSsoConfigRequest = {
          provider_type: formState.value.provider_type,
          display_name: formState.value.display_name.trim(),
          ...providerFields(formState.value),
          allowed_domains: formState.value.allowed_domains,
          enabled: formState.value.enabled,
          enforce_sso_only: formState.value.enforce_sso_only,
          grant_org_scope: formState.value.grant_org_scope,
        };

        // Only include client_secret if provided (non-empty). Never for saml,
        // which has no client credential: the API discards it anyway, and
        // its presence is what routes the save to PUT (see SsoService).
        if (usesClientCredentials(formState.value) && formState.value.client_secret.trim()) {
          (payload as PutSsoConfigRequest).client_secret = formState.value.client_secret.trim();
        }

        return await SsoService.saveConfigForDomain(domainExtId, payload);
      });

      if (result?.record) {
        ssoConfig.value = result.record;
        formState.value = configToFormState(result.record);
        savedFormState.value = {
          ...formState.value,
          allowed_domains: [...formState.value.allowed_domains],
        };
        notifications.show(t('web.domains.sso.update_success'), 'success', 'top');
      }
    } finally {
      isSaving.value = false;
    }
  };

  const disableConfig = async () => {
    if (
      !ssoConfig.value?.enabled ||
      isLoading.value ||
      isSaving.value ||
      isDeleting.value ||
      isTesting.value
    )
      return;
    isSaving.value = true;
    error.value = null;
    try {
      // Recovery contract: existing record, exactly these two flags; never form edits.
      const result = await wrapAction(() =>
        SsoService.patchConfigForDomain(domainExtId, {
          enabled: false,
          enforce_sso_only: false,
        })
      );
      if (result?.record) {
        ssoConfig.value = result.record;
        savedFormState.value = configToFormState(result.record);
        formState.value = {
          ...formState.value,
          enabled: result.record.enabled,
          enforce_sso_only: result.record.enforce_sso_only,
        };
        testResult.value = null;
        testError.value = '';
        notifications.show(t('web.domains.sso.update_success'), 'success', 'top');
      }
    } finally {
      isSaving.value = false;
    }
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
        ssoConfig.value = null;
        formState.value = createDefaultFormState();
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
    testResult.value = null;
    testError.value = '';

    try {
      const result = await wrapAction(async () => {
        const payload: TestSsoConnectionRequest = {
          provider_type: formState.value.provider_type,
          ...providerFields(formState.value),
        };

        return await SsoService.testConnectionForDomain(domainExtId, payload);
      });

      if (result) {
        testResult.value = result;
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
    error,
    ssoConfig,
    formState,
    testResult,
    testError,

    // Computed
    isConfigured,
    isEnabled,
    clientSecretMasked,
    unreadableFields,
    hasUnsavedChanges,

    // Actions
    initialize,
    saveConfig,
    disableConfig,
    deleteConfig,
    testConnection,
    discardChanges,
  };
}
