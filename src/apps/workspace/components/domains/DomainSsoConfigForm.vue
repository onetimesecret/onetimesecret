<!-- src/apps/workspace/components/domains/DomainSsoConfigForm.vue -->

<script setup lang="ts">
/**
 * Domain SSO Configuration Form
 *
 * Presentational component that receives SSO config state via props
 * and emits events for actions. The host page (DomainSigninSso.vue)
 * manages state via the useSsoConfig composable. Laid out as a settings
 * page: flat sections top to bottom, the primary action in a sticky
 * footer, delete in a danger zone.
 */
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
import CopyToClipboardButton from '@/shared/components/ui/CopyToClipboardButton.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import { useClipboard } from '@/shared/composables/useClipboard';
import type { TenantSsoVerdict } from '@/schemas/api/domains/responses/signin-config';
import {
  SSO_PROVIDER_ROUTE_NAMES,
  SSO_TOKEN_ENDPOINT_AUTH_METHODS,
  ssoProviderUsesClientCredentials,
  tokenEndpointAuthMethodSchema,
  type CustomDomainSsoConfig,
  type SsoProviderType,
  type SsoTokenEndpointAuthMethod,
  type SsoTokenEndpointAuthMethodRequest,
} from '@/schemas/shapes/domains/sso-config';
import type { SsoConfigFormState } from '@/shared/composables/useSsoConfig';
import type {
  SsoDiagnosticActivation,
  SsoDiagnosticCheck,
  SsoDiagnosticOverall,
  SsoDiagnosticStatus,
  SsoDiagnosticsResponse,
  TestSsoConnectionResponse,
} from '@/services/sso.service';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

const props = defineProps<{
  domainExtId: string;
  domainHost: string;
  domainVerified: boolean;
  orgId: string;
  formState: SsoConfigFormState;
  ssoConfig: CustomDomainSsoConfig | null;
  isLoading: boolean;
  isSaving: boolean;
  isDeleting: boolean;
  isTesting: boolean;
  /** Whether a saved-configuration diagnostics request is in flight. */
  isDiagnosing: boolean;
  hasUnsavedChanges: boolean;
  isConfigured: boolean;
  clientSecretMasked: string | null;
  testResult: TestSsoConnectionResponse | null;
  testError: string;
  /** Result of the last "Check saved configuration" run; null until one ran. */
  diagnosticsResult: SsoDiagnosticsResponse | null;
  /** Passing saved-credential checks, retained across activation-only saves. */
  savedCredentialsChecked: boolean;
  /**
   * A save in this session changed the stored credentials and no passing
   * run has covered them since (useSsoConfig). After that save the form
   * matches the record, so this is the only trace of the change.
   */
  savedCredentialsUnchecked: boolean;
  /** Transport failure of the last run (no verdict), '' otherwise. */
  diagnosticsError: string;
  /** Whether a last-sign-in refresh is in flight. */
  isRefreshingLastSignIn: boolean;
  /**
   * The page's tenant-SSO verdict (#4111, `details.tenant_sso`), rendered
   * verbatim. Absent or null until the sign-in details have loaded; nothing
   * is claimed without it.
   */
  tenantSso?: TenantSsoVerdict | null;
  /**
   * The install-wide SAML switch (SAML_ENABLED, #4604; features.isSamlEnabled
   * on the bootstrap payload). While false the API refuses to save or edit
   * provider_type saml, so the selector does not offer it.
   */
  samlEnabled: boolean;
}>();

// ---------------------------------------------------------------------------
// Emits
// ---------------------------------------------------------------------------

const emit = defineEmits<{
  /** Save only: the footer button, for a record that already exists. */
  (e: 'save'): void;
  (e: 'delete'): void;
  (e: 'test'): void;
  /**
   * The primary action: run the saved-configuration check, saving a new
   * record or unsaved edits first. A record that is off is turned on when
   * the check passes (useSsoConfig.saveAndRunDiagnostics).
   */
  (e: 'diagnostics'): void;
  (e: 'discard'): void;
  (e: 'refresh-last-sign-in'): void;
  (e: 'update:formState', value: SsoConfigFormState): void;
}>();

const { t } = useI18n();

// ---------------------------------------------------------------------------
// Provider options
// ---------------------------------------------------------------------------

// Every tenant provider must carry a tenant-distinguishing issuer: issuerless
// providers (GitHub, Google) cannot satisfy per-tenant identity partitioning
// keyed (provider, issuer, uid) and are refused on tenant surfaces (#3902,
// PR #3900). SAML qualifies — its issuer is the IdP's own EntityID (#4450).
const providerOptions: { value: SsoProviderType; label: string; description: string }[] = [
  {
    value: 'entra_id',
    label: 'Microsoft Entra ID',
    description: 'Azure Active Directory / Microsoft 365',
  },
  {
    value: 'oidc',
    label: 'Generic OIDC',
    description: 'Any OpenID Connect provider',
  },
  {
    value: 'saml',
    label: 'SAML 2.0',
    description: 'Any SAML 2.0 identity provider (Okta, ADFS, Keycloak, …)',
  },
];

/**
 * The options the selector offers for a NEW config. SAML is dropped while the
 * install-wide switch is off (#4604): the API would refuse the save on
 * provider_type. `providerOptions` stays complete so a saved saml record
 * (provider type locked while editing) still resolves its label through
 * `currentProviderOption`; deleting such a record stays possible.
 */
const selectableProviderOptions = computed(() =>
  providerOptions.filter((option) => option.value !== 'saml' || props.samlEnabled)
);

/**
 * Encrypted record fields the API may name in `unreadable_fields` (#4450),
 * with the label key used to name each in the alert. A listed field's stored
 * value could not be decrypted — the form seeds it blank, marks the input
 * invalid and demands re-entry; it must never read as "unset".
 */
const UNREADABLE_FIELD_LABELS: Record<string, string> = {
  client_id: 'web.organizations.sso.client_id',
  client_secret: 'web.organizations.sso.client_secret',
  idp_sso_service_url: 'web.organizations.sso.idp_sso_service_url',
  idp_entity_id: 'web.organizations.sso.idp_entity_id',
  idp_cert: 'web.organizations.sso.idp_cert',
};

/**
 * Token endpoint client authentication (#4764, oidc only). '' is the
 * "Automatic" option — the gem default — and is what the composable sends
 * so a PATCH clears a stored choice. Labels are keyed per contract value so
 * a method added to the contract fails type-check here until it has one.
 */
const TOKEN_ENDPOINT_AUTH_METHOD_LABELS: Record<SsoTokenEndpointAuthMethod, string> = {
  client_secret_basic: 'web.organizations.sso.token_endpoint_auth_method_client_secret_basic',
  client_secret_post: 'web.organizations.sso.token_endpoint_auth_method_client_secret_post',
};

const tokenEndpointAuthMethodOptions: {
  value: SsoTokenEndpointAuthMethodRequest;
  labelKey: string;
}[] = [
  { value: '', labelKey: 'web.organizations.sso.token_endpoint_auth_method_automatic' },
  ...SSO_TOKEN_ENDPOINT_AUTH_METHODS.map((method) => ({
    value: method,
    labelKey: TOKEN_ENDPOINT_AUTH_METHOD_LABELS[method],
  })),
];

// ---------------------------------------------------------------------------
// Local UI state
// ---------------------------------------------------------------------------

const showDeleteConfirm = ref(false);
const showClientSecret = ref(false);
const newDomain = ref('');
const domainInputError = ref('');

/**
 * The Advanced disclosure is collapsed by default, but a saved record that
 * carries a non-default token endpoint auth method opens it so the choice
 * is never hidden from the admin editing it.
 */
const advancedOpen = ref(false);
watch(
  () => props.ssoConfig?.token_endpoint_auth_method ?? null,
  (stored) => {
    if (stored) advancedOpen.value = true;
  },
  { immediate: true }
);

/**
 * The provider discovery check is an advanced disclosure, collapsed by
 * default. A result (or transport error) opens it so what the admin asked
 * for is never hidden behind a closed summary; closing it again is theirs.
 */
const providerCheckOpen = ref(false);
watch(
  () => !!props.testResult || !!props.testError,
  (hasResult) => {
    if (hasResult) providerCheckOpen.value = true;
  },
  { immediate: true }
);

// ---------------------------------------------------------------------------
// Form state helpers (emit updates to parent)
// ---------------------------------------------------------------------------

function updateField<K extends keyof SsoConfigFormState>(
  field: K,
  value: SsoConfigFormState[K]
): void {
  emit('update:formState', {
    ...props.formState,
    [field]: value,
  });
}

/** A select value is a string; only a contract value (or '') reaches the state. */
function updateTokenEndpointAuthMethod(raw: string): void {
  const parsed = tokenEndpointAuthMethodSchema.safeParse(raw);
  updateField('token_endpoint_auth_method', parsed.success ? parsed.data : '');
}

// ---------------------------------------------------------------------------
// Computed: form validation and display logic
// ---------------------------------------------------------------------------

const isEditing = computed(() => props.isConfigured);

const isSaml = computed(() => props.formState.provider_type === 'saml');

const requiresTenantId = computed(() => props.formState.provider_type === 'entra_id');

const requiresIssuer = computed(() => props.formState.provider_type === 'oidc');

/**
 * Test Connection (#4764): the advertised token endpoint auth methods, and
 * whether the selected one is among them. `false` keeps the test successful
 * (an IdP may accept a method it does not list) but turns the API's note
 * into a warning rather than a confirmation.
 */
const advertisedTokenEndpointAuthMethods = computed(
  () => props.testResult?.details?.token_endpoint_auth_methods_supported ?? null
);

const tokenEndpointAuthMethodUnadvertised = computed(
  () => props.testResult?.details?.token_endpoint_auth_method_supported === false
);

// OAuth-family providers only; SAML's trust anchor is the IdP certificate.
const requiresClientCredentials = computed(() =>
  ssoProviderUsesClientCredentials(props.formState.provider_type)
);

// OIDC supports public clients (PKCE); SAML has no secret at all.
const requiresClientSecret = computed(
  () => requiresClientCredentials.value && props.formState.provider_type !== 'oidc'
);

/**
 * Encrypted fields whose stored value the API could not reveal (#4450). The
 * composable seeds each blank, so the required guards below already block
 * the save until it is re-entered; this drives the alert and aria-invalid.
 */
const unreadableFields = computed(() => props.ssoConfig?.unreadable_fields ?? []);

const isUnreadable = (field: string) => unreadableFields.value.includes(field);

const unreadableFieldNames = computed(() =>
  unreadableFields.value
    .map((field) => t(UNREADABLE_FIELD_LABELS[field] ?? field))
    .join(', ')
);

/**
 * The public origin + route for this domain's SSO URLs, PREVIEWED from the
 * domain host: always https and the default route from the contract (pinned
 * to the Ruby PROVIDER_ROUTE_MAP by sso-config-metadata-contract.spec.ts).
 * An operator route override (SAML_ROUTE_NAME etc.) or site.ssl=false is
 * invisible here, so the preview can differ from the real path; plumbing the
 * configured route through bootstrap config is tracked in #3932. Until then
 * the SP block labels host-derived values as a preview (spDetailsArePreview)
 * rather than hiding them — IdPs such as Okta and Entra demand the ACS URL
 * and Audience at app creation, before any record can exist here.
 *
 * Built for an unverified host too (#4579): tenant SSO is refused on that
 * host until verification completes (sso_domain_unverified), and verification
 * does not change these URLs, so the unverified notice says only that. It
 * makes no claim that they are ready to register: the preview caveat above
 * applies on a verified domain and an unverified one alike.
 */
const ssoRouteBase = computed(() => {
  if (!props.domainHost) return null;
  const route = SSO_PROVIDER_ROUTE_NAMES[props.formState.provider_type];
  return `https://${props.domainHost}/auth/sso/${route}`;
});

/**
 * For a saved saml record the API composes the SP identifiers itself
 * (sp_entity_id / acs_url), verified domain or not; the provider type is
 * locked while editing, so the record's values are for the type shown.
 * Before a record exists (or when the API could not derive them — the
 * domain could not be loaded) they are previewed from the host.
 */
const savedSamlRecord = computed(() =>
  isEditing.value && props.ssoConfig?.provider_type === 'saml' ? props.ssoConfig : null
);

/**
 * ACS URL shown in the SP block: the API's acs_url for a saved record,
 * otherwise the host preview (see ssoRouteBase for why that is labelled a
 * preview and #3932 for the real-route plumbing).
 */
const callbackUrl = computed(
  () => savedSamlRecord.value?.acs_url ?? (ssoRouteBase.value ? `${ssoRouteBase.value}/callback` : null)
);

/**
 * True when either SP identifier shown is host-derived rather than
 * API-composed: no saml record has been saved yet, or the API could not
 * derive the value. The block then swaps the "register these" hint for one
 * that says the values are a preview of the default route and asks the admin
 * to save and confirm them here first (#3932 — an operator route override
 * would make the preview wrong, and a wrong ACS URL at the IdP fails every
 * login with an opaque IdP-side error). Independent of verification: an
 * unverified domain's API-composed values are the real ones, just not live.
 */
const spDetailsArePreview = computed(
  () => !savedSamlRecord.value?.sp_entity_id || !savedSamlRecord.value?.acs_url
);

/** Days before expiry at which the softer "expiring soon" notice appears. */
const CERT_EXPIRY_NOTICE_DAYS = 30;

/**
 * Validity of the SAVED SAML record's IdP certificate (#4450). The API
 * reports cert_expires_at / cert_expired; an expired certificate stays
 * advertised on the sign-in page while every login through it is refused,
 * so this form is where the admin learns why. Null once the admin has
 * pasted a different certificate — the warning is about the stored one.
 */
const storedCertExpiry = computed(() => {
  const record = savedSamlRecord.value;
  if (!record?.cert_expires_at) return null;
  if (props.formState.idp_cert.trim() !== (record.idp_cert ?? '').trim()) return null;
  const date = new Date(record.cert_expires_at);
  if (Number.isNaN(date.getTime())) return null;
  const msLeft = date.getTime() - Date.now();
  const expired = record.cert_expired === true || msLeft <= 0;
  return {
    date: date.toLocaleDateString(),
    expired,
    expiringSoon: !expired && msLeft <= CERT_EXPIRY_NOTICE_DAYS * 86_400_000,
  };
});

/**
 * SP Entity ID (doubles as the SP metadata URL): the API's sp_entity_id for
 * a saved record, otherwise the host preview (see ssoRouteBase; #3932).
 */
const spEntityId = computed(
  () => savedSamlRecord.value?.sp_entity_id ?? (ssoRouteBase.value ? `${ssoRouteBase.value}/metadata` : null)
);

/**
 * Whether the callback / SP block renders at all — the same conditions as
 * the two v-if guards on those blocks — so the unverified notice appears
 * exactly when there are values for it to describe.
 */
const showsRegistrationValues = computed(() =>
  isSaml.value ? !!(spEntityId.value || callbackUrl.value) : !!callbackUrl.value
);

/**
 * Unverified-domain notice (#4579). Tenant SSO is refused on a domain whose
 * ownership is not verified (auth_error=sso_domain_unverified). The notice
 * says SSO is off until verification and that verification leaves the
 * values in the callback / SP block unchanged. It does not say verification
 * turns SSO on: it also shows for a connection that is switched off or that
 * the domain's sign-in settings withhold. Whether those values are
 * ready to register is the block hint's call (spDetailsArePreview for SAML;
 * the host-derived OAuth callback URL carries the #3932 caveat on any
 * domain). Also covers a domain that lost its verification: the values
 * already registered stay shown.
 */
const showDomainUnverifiedNotice = computed(
  () => !props.domainVerified && showsRegistrationValues.value
);

const showDomainFilter = computed(() => false);

/**
 * "Grant org-wide access" is withheld from the UI pending further testing
 * (targeted for after v0.26.0) — but only for domains that don't already use
 * it. A config loaded with grant_org_scope=true keeps its toggle so the grant
 * stays revocable: hiding it outright would strand an irrevocable org-wide
 * grant that every save re-persists (configToFormState seeds it and saveConfig
 * always re-sends it). New/default configs (grant_org_scope=false) never see
 * the control.
 *
 * The latch keeps it visible for the whole edit session even after the admin
 * flips it off, so it doesn't vanish mid-edit. It is scoped per domain: a
 * host may reuse this instance across domains (no :key), so when
 * domainExtId changes the latch is recomputed from the incoming
 * grant_org_scope. A fresh domain with grant_org_scope=false therefore clears a
 * latch left true by a previously-loaded domain, rather than inheriting it.
 */
const showGrantOrgScope = ref(false);
watch(
  () => [props.domainExtId, props.formState.grant_org_scope] as const,
  ([domainExtId, granted], previous) => {
    const domainChanged = !previous || domainExtId !== previous[0];
    if (domainChanged) {
      // New domain loaded (or initial mount): recompute the latch from the
      // incoming config so a false grant clears any latch a prior domain left.
      showGrantOrgScope.value = granted;
    } else if (granted) {
      // Same domain, admin (re-)granted mid-edit: keep the toggle visible.
      showGrantOrgScope.value = true;
    }
  },
  { immediate: true }
);

const currentProviderOption = computed(() =>
  providerOptions.find((o) => o.value === props.formState.provider_type)
);

/**
 * Provider-scoped fields that must be filled before a save or a test. Mirrors
 * the API's per-provider `missing` checks (put/patch/test_connection) so the
 * buttons never offer a request the API would refuse as 422.
 */
const providerFieldsFilled = computed(() => {
  const f = props.formState;
  if (requiresClientCredentials.value && !f.client_id.trim()) return false;
  if (requiresTenantId.value && !f.tenant_id?.trim()) return false;
  if (requiresIssuer.value && !f.issuer?.trim()) return false;
  if (isSaml.value) {
    if (!f.idp_sso_service_url.trim() || !f.idp_entity_id.trim() || !f.idp_cert.trim()) return false;
  }
  return true;
});

// A secret must be entered for a new config of a provider that requires
// one, or — for EVERY credential-bearing provider, oidc included — when the
// stored one could not be read: PATCH would otherwise carry forward a value
// that does not decrypt, and the API refuses that as missing. The oidc
// public-client exemption covers an absent secret, not corrupt ciphertext.
const clientSecretMustBeEntered = computed(
  () =>
    requiresClientCredentials.value &&
    (isUnreadable('client_secret') || (requiresClientSecret.value && !isEditing.value))
);

const isFormValid = computed(() => {
  if (!props.formState.display_name.trim()) return false;
  if (!providerFieldsFilled.value) return false;
  if (clientSecretMustBeEntered.value && !props.formState.client_secret?.trim()) return false;
  return true;
});

const clientSecretPlaceholder = computed(() => {
  if (isEditing.value && props.clientSecretMasked) {
    return props.clientSecretMasked;
  }
  return t('web.organizations.sso.client_secret_placeholder');
});

// Entra shows a Secret ID (a UUID) next to the secret Value and the ID is
// never the credential; a Value is never UUID-shaped. Warn before the save,
// the way the saved-configuration check flags a stored one (secret_shape).
const UUID_SHAPE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const clientSecretLooksLikeSecretId = computed(
  () =>
    props.formState.provider_type === 'entra_id' &&
    UUID_SHAPE.test(props.formState.client_secret?.trim() ?? '')
);

const discoveryUrl = computed(() => {
  const issuer = props.formState.issuer?.trim();
  if (!issuer) return null;
  try {
    const u = new URL(issuer);
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
    return `${issuer.replace(/\/+$/, '')}/.well-known/openid-configuration`;
  } catch {
    return null;
  }
});

const { isCopied: isCallbackCopied, copyToClipboard } = useClipboard();
const { isCopied: isSpEntityIdCopied, copyToClipboard: copySpEntityId } = useClipboard();

const canTestConnection = computed(() => providerFieldsFilled.value);

/**
 * The SAML test never contacts the IdP: it parses the certificate and checks
 * the URL and EntityID locally, so its result is the certificate's subject
 * and expiry rather than discovery endpoints. Days are floored by the API.
 */
/**
 * Start of the certificate's validity window, reported beside the expiry.
 * On a `certificate_not_yet_valid` failure it is the fact that matters: the
 * certificate parses and has not expired, it just cannot be used yet.
 */
const certificateValidFrom = computed(() => {
  const raw = props.testResult?.details?.certificate_not_before;
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? raw : date.toLocaleDateString();
});

const certificateExpiry = computed(() => {
  const details = props.testResult?.details;
  if (!details?.certificate_not_after) return null;
  const date = new Date(details.certificate_not_after);
  return {
    date: Number.isNaN(date.getTime()) ? details.certificate_not_after : date.toLocaleDateString(),
    days: details.certificate_expires_in_days,
  };
});

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

const handleSave = () => {
  if (!isFormValid.value || props.isSaving || props.isDeleting) return;
  emit('save');
};

const handleDelete = () => {
  if (props.isDeleting) return;
  emit('delete');
  showDeleteConfirm.value = false;
};

/**
 * Discovery alone cannot vouch for credentials because it does not exercise
 * the saved ones, so only a passing saved-configuration check counts.
 * Compare credential fields with the saved record so a passing result
 * survives edits to other fields, but a new secret or a different client ID,
 * tenant, issuer, auth method or SAML IdP field does not.
 */
const savedCredentialsMatchForm = computed(() => {
  const record = props.ssoConfig;
  const form = props.formState;
  if (!record || form.provider_type !== record.provider_type) return false;
  if (isSaml.value) {
    return (['idp_sso_service_url', 'idp_entity_id', 'idp_cert'] as const).every(
      (field) => form[field].trim() === (record[field] ?? '').trim()
    );
  }
  if (form.client_secret.trim() || form.client_id.trim() !== (record.client_id ?? '').trim()) {
    return false;
  }
  return requiresTenantId.value
    ? form.tenant_id.trim() === (record.tenant_id ?? '').trim()
    : form.issuer.trim() === (record.issuer ?? '').trim() &&
        form.token_endpoint_auth_method === (record.token_endpoint_auth_method ?? '');
});

const savedChecksPassed = computed(
  () =>
    props.isConfigured &&
    props.savedCredentialsChecked &&
    savedCredentialsMatchForm.value
);

/** The stored record is on: sign-in through it is live (subject to the ladder). */
const connectionOn = computed(() => props.ssoConfig?.enabled === true);

/**
 * Advisory, never a gate (saving an active connection stays possible: it is
 * how a broken one is repaired). Shown on a connection that is on while
 * its credentials differ from what a passing check covered: edited in the
 * form, or saved in this session and not checked since. Opening an active
 * connection with nothing changed shows nothing, although no check has run
 * in this session.
 */
const showUncheckedCredentialsWarning = computed(
  () =>
    connectionOn.value &&
    !savedChecksPassed.value &&
    (!savedCredentialsMatchForm.value || props.savedCredentialsUnchecked)
);

const handleTestConnection = () => {
  if (!canTestConnection.value || props.isTesting) return;
  emit('test');
};

// ---------------------------------------------------------------------------
// Check saved configuration (diagnostics)
// ---------------------------------------------------------------------------

/**
 * Diagnostics run against the SAVED record (for Entra including the stored
 * client secret), so a new record or unsaved edits are saved first: a
 * result about the stored record would otherwise be read as a verdict on
 * what the form shows. One button carries both steps, so setup has one
 * save path and one primary action.
 */
const checkNeedsSave = computed(() => !props.isConfigured || props.hasUnsavedChanges);

const canRunCheck = computed(() => {
  if (props.isSaving || props.isDeleting || props.isDiagnosing) return false;
  return checkNeedsSave.value ? isFormValid.value : true;
});

/**
 * Save and check (unsaved) → Check and turn on (saved, off) → Check saved
 * configuration (saved, on; nothing to turn on).
 */
const checkButtonLabel = computed(() => {
  if (props.isSaving) return t('web.COMMON.saving');
  if (props.isDiagnosing) return t('web.organizations.sso.diagnostics_running');
  if (checkNeedsSave.value) return t('web.organizations.sso.diagnostics_save_and_check');
  if (!connectionOn.value) return t('web.organizations.sso.diagnostics_check_and_activate');
  return t('web.organizations.sso.diagnostics_button');
});

const handleRunCheck = () => {
  if (!canRunCheck.value) return;
  emit('diagnostics');
};

/**
 * Form submission. An existing record has the footer Save as its submit
 * button. A new record has none, so browsers do not submit on Enter (the
 * form has several text fields); a submit that arrives anyway runs the
 * primary action, so the first save never skips the check.
 */
const handleSubmit = () => {
  if (props.isConfigured) handleSave();
  else handleRunCheck();
};

/**
 * The provider name in the not_permitted message. A legacy record can carry
 * a type the selector no longer offers (google, github): its raw name is
 * shown rather than nothing.
 */
const providerLabel = (type: string): string =>
  providerOptions.find((option) => option.value === type)?.label ?? type;

/**
 * What the last run did to the connection, one message per outcome the API
 * reports (keyed per contract value, so a new outcome fails type-check here
 * until it has one). null = nothing to add: the record was already on, or
 * activation was not requested.
 */
const ACTIVATION_NOTICES: Record<
  SsoDiagnosticActivation,
  { key: string; tone: 'ok' | 'warn' } | null
> = {
  activated: { key: 'web.organizations.sso.diagnostics_activation_activated', tone: 'ok' },
  not_passed: { key: 'web.organizations.sso.diagnostics_activation_stays_off', tone: 'warn' },
  not_permitted: {
    key: 'web.organizations.sso.diagnostics_activation_not_permitted',
    tone: 'warn',
  },
  configuration_changed: {
    key: 'web.organizations.sso.diagnostics_activation_configuration_changed',
    tone: 'warn',
  },
  already_enabled: null,
  not_requested: null,
};

const activationNotice = computed(() => {
  const result = props.diagnosticsResult;
  if (!result) return null;
  const notice = ACTIVATION_NOTICES[result.activation] ?? null;
  if (!notice) return null;
  // Each warning says the connection stays off. A copy that was off here
  // asks for activation even when the record was turned on elsewhere, and
  // the response's `enabled` is the stored state: trust it over the copy.
  if (notice.tone === 'warn' && result.enabled) return null;
  return {
    activation: result.activation,
    tone: notice.tone,
    text: t(notice.key, { provider: providerLabel(result.provider_type) }),
  };
});

/**
 * "Next: confirm sign-in" follows a pass only when the connection is on
 * afterwards. A pass that did not turn it on (not_permitted,
 * configuration_changed) has its own message instead.
 */
const showDiagnosticsNext = computed(
  () => props.diagnosticsResult?.overall === 'passed' && props.diagnosticsResult.enabled === true
);

/**
 * The setup guide stays until the connection is on, and through the result
 * of the run that turned it on, so the page does not shift under the admin
 * reading that result.
 */
const showSetupGuide = computed(
  () => !connectionOn.value || props.diagnosticsResult?.activation === 'activated'
);

/**
 * The connection is on but the domain's sign-in settings withhold SSO, so
 * the sign-in page does not offer it and Confirm sign-in cannot work. The
 * server's verdict reports this rung only for a record that is on (it
 * checks sso_config_disabled first), so it appears once the page has
 * re-read the verdict after activation. Rendered from the verdict
 * verbatim; never derived from raw flags (ADR-024).
 */
const signInNotPermitted = computed(
  () => connectionOn.value && props.tenantSso?.unavailable_reason === 'sso_not_permitted'
);

/** Label key per check name the API emits; an unknown name renders raw. */
const DIAGNOSTIC_CHECK_LABELS: Record<string, string> = {
  stored_configuration: 'web.organizations.sso.diagnostics_check_stored_configuration',
  discovery: 'web.organizations.sso.diagnostics_check_discovery',
  certificate: 'web.organizations.sso.diagnostics_check_certificate',
  credential: 'web.organizations.sso.diagnostics_check_credential',
};

const diagnosticCheckLabel = (check: SsoDiagnosticCheck): string => {
  const key = DIAGNOSTIC_CHECK_LABELS[check.check];
  return key ? t(key) : check.check;
};

const hasDiagnosticTechnicalDetails = (check: SsoDiagnosticCheck): boolean => {
  const details = check.details;
  if (!details) return false;
  return !!(
    details.error_code ||
    details.aadsts_code ||
    details.http_status ||
    details.errors?.length ||
    details.certificate_not_after ||
    details.token_endpoint_auth_methods_supported?.length
  );
};

/**
 * Status chip per check. The colour alone never carries the meaning (WCAG
 * 1.4.1): the status word is printed in the chip. Keyed per contract status
 * so a new status fails type-check here until it has a chip.
 */
const DIAGNOSTIC_STATUS_CHIPS: Record<
  SsoDiagnosticStatus,
  { labelKey: string; classes: string }
> = {
  passed: {
    labelKey: 'web.organizations.sso.diagnostics_status_passed',
    classes: 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200',
  },
  failed: {
    labelKey: 'web.organizations.sso.diagnostics_status_failed',
    classes: 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200',
  },
  inconclusive: {
    labelKey: 'web.organizations.sso.diagnostics_status_inconclusive',
    classes: 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200',
  },
  unsupported: {
    labelKey: 'web.organizations.sso.diagnostics_status_unsupported',
    classes: 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-200',
  },
  skipped: {
    labelKey: 'web.organizations.sso.diagnostics_status_skipped',
    classes: 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-200',
  },
};

/**
 * The result container borrows the Test Connection result's look: green
 * status box for a pass, red alert for a failure, amber status box when the
 * run could not reach a verdict.
 */
const DIAGNOSTIC_OVERALL_STYLES: Record<
  SsoDiagnosticOverall,
  {
    role: 'status' | 'alert';
    live: 'polite' | 'assertive';
    box: string;
    icon: string;
    iconClass: string;
    text: string;
  }
> = {
  passed: {
    role: 'status',
    live: 'polite',
    box: 'rounded-md bg-green-50 p-4 dark:bg-green-900/20',
    icon: 'check-circle-solid',
    iconClass: 'size-5 text-green-400',
    text: 'text-green-800 dark:text-green-200',
  },
  failed: {
    role: 'alert',
    live: 'assertive',
    box: 'rounded-md bg-red-50 p-4 dark:bg-red-900/20',
    icon: 'x-circle-solid',
    iconClass: 'size-5 text-red-400',
    text: 'text-red-800 dark:text-red-200',
  },
  inconclusive: {
    role: 'status',
    live: 'polite',
    box: 'rounded-md bg-amber-50 p-4 dark:bg-amber-900/20',
    icon: 'exclamation-triangle-solid',
    iconClass: 'size-5 text-amber-500',
    text: 'text-amber-800 dark:text-amber-200',
  },
};

const diagnosticsOverallStyle = computed(() =>
  props.diagnosticsResult ? DIAGNOSTIC_OVERALL_STYLES[props.diagnosticsResult.overall] : null
);

/**
 * The last tenant sign-in outcome on the saved record (null = none
 * recorded). Timestamps are Unix epoch seconds; shown in the admin's locale.
 */
const lastSignIn = computed(() => props.ssoConfig?.last_sign_in ?? null);

const LAST_SIGN_IN_STAGE_KEYS: Record<string, string> = {
  setup: 'web.organizations.sso.last_sign_in_stage_setup',
  provider: 'web.organizations.sso.last_sign_in_stage_provider',
  callback: 'web.organizations.sso.last_sign_in_stage_callback',
  account: 'web.organizations.sso.last_sign_in_stage_account',
};

const epochToLocale = (epoch: number) => new Date(epoch * 1000).toLocaleString();

const lastSignInText = computed(() => {
  const outcome = lastSignIn.value;
  if (!outcome) return t('web.organizations.sso.last_sign_in_none');
  if (outcome.result === 'succeeded') {
    return t('web.organizations.sso.last_sign_in_succeeded', { when: epochToLocale(outcome.at) });
  }
  const stageKey = LAST_SIGN_IN_STAGE_KEYS[outcome.failure_stage ?? ''];
  const parts = [
    t('web.organizations.sso.last_sign_in_failed', {
      when: epochToLocale(outcome.at),
      stage: stageKey ? t(stageKey) : (outcome.failure_stage ?? ''),
      code: outcome.failure_code ?? '',
    }),
  ];
  if (outcome.succeeded_at !== null) {
    parts.push(
      t('web.organizations.sso.last_sign_in_last_success', {
        when: epochToLocale(outcome.succeeded_at),
      })
    );
  }
  return parts.join(' ');
});

/** checked_at is ISO 8601 UTC from the API; shown in the admin's locale. */
const diagnosticsCheckedAt = computed(() => {
  const raw = props.diagnosticsResult?.checked_at;
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? raw : date.toLocaleString();
});

/** The same date handling as the Test Connection certificate rows. */
const formatDiagnosticDate = (raw: string): string => {
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? raw : date.toLocaleDateString();
};

const addDomain = () => {
  const domain = newDomain.value.trim().toLowerCase();

  if (!domain) return;

  // Basic frontend validation for UX (backend does authoritative PublicSuffix check)
  if (!domain.includes('.') || /\s/.test(domain)) {
    domainInputError.value = t('web.organizations.sso.invalid_domain');
    return;
  }

  // Check for duplicates
  if (props.formState.allowed_domains?.includes(domain)) {
    domainInputError.value = t('web.organizations.sso.domain_exists');
    return;
  }

  updateField('allowed_domains', [...(props.formState.allowed_domains || []), domain]);
  newDomain.value = '';
  domainInputError.value = '';
};

const removeDomain = (domain: string) => {
  updateField(
    'allowed_domains',
    props.formState.allowed_domains?.filter((d) => d !== domain) ?? []
  );
};

// Clear domain input error when typing
watch(newDomain, () => {
  if (domainInputError.value) {
    domainInputError.value = '';
  }
});
</script>

<template>
  <div>
    <!-- Loading State -->
    <SettingsSkeleton
      v-if="isLoading"
      :heading="false" />

    <!-- Form. The sticky footer (bottom) and the host's sticky header (top)
         cover the edges a browser scrolls a newly focused control to, so every
         focusable descendant carries a scroll margin that clears them (WCAG
         2.4.11 Focus Not Obscured). -->
    <form
      v-else
      @submit.prevent="handleSubmit"
      class="space-y-8 [&_:is(input,select,textarea,button,summary,a)]:scroll-mt-24 [&_:is(input,select,textarea,button,summary,a)]:scroll-mb-28">
      <!-- Setup guide: one line, with the numbered stages behind a
           disclosure. Stays until the connection is on (showSetupGuide). -->
      <section
        v-if="showSetupGuide"
        data-testid="sso-setup-guide"
        aria-labelledby="sso-setup-title"
        class="text-sm">
        <p
          id="sso-setup-title"
          class="text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.setup_summary') }}
        </p>
        <details class="mt-1">
          <summary
            class="cursor-pointer font-medium text-brand-600 select-none hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('web.organizations.sso.setup_steps') }}
          </summary>
          <ol class="mt-2 list-decimal space-y-1 pl-5 text-gray-600 dark:text-gray-300">
            <li>
              {{
                t(
                  isSaml
                    ? 'web.organizations.sso.setup_register_saml'
                    : 'web.organizations.sso.setup_register'
                )
              }}
            </li>
            <li>{{ t('web.organizations.sso.setup_save_check') }}</li>
            <li>{{ t('web.organizations.sso.setup_confirm') }}</li>
          </ol>
        </details>
      </section>

      <!-- Reveal failure (#4450): a stored encrypted value that will not
           decrypt is served as null AND named in unreadable_fields. It is an
           error state, not "unset" — the inputs below are blank, marked
           invalid, and the save stays disabled until each is re-entered. -->
      <div
        v-if="unreadableFields.length > 0"
        data-testid="sso-unreadable-fields-alert"
        role="alert"
        class="flex items-start gap-2 rounded-md bg-red-50 px-3 py-2 dark:bg-red-900/20">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-4 flex-shrink-0 text-red-600 dark:text-red-400"
          aria-hidden="true" />
        <p class="text-sm text-red-700 dark:text-red-300">
          {{ t('web.organizations.sso.unreadable_fields_alert', { fields: unreadableFieldNames }) }}
        </p>
      </div>

      <!-- Stored IdP certificate validity (#4450): expired is an error — the
           connection is advertised but every sign-in through it is refused —
           and expiring soon is an advisory. Both hide once a different
           certificate is pasted. Amber is the fixed warning hue (#4132). -->
      <div
        v-if="storedCertExpiry?.expired"
        data-testid="sso-idp-cert-expired-alert"
        role="alert"
        class="flex items-start gap-2 rounded-md bg-red-50 px-3 py-2 dark:bg-red-900/20">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-4 flex-shrink-0 text-red-600 dark:text-red-400"
          aria-hidden="true" />
        <p class="text-sm text-red-700 dark:text-red-300">
          {{ t('web.organizations.sso.idp_cert_expired_alert', { date: storedCertExpiry.date }) }}
        </p>
      </div>
      <div
        v-else-if="storedCertExpiry?.expiringSoon"
        data-testid="sso-idp-cert-expiring-notice"
        role="status"
        class="flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 dark:bg-amber-900/20">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-4 flex-shrink-0 text-amber-600 dark:text-amber-400"
          aria-hidden="true" />
        <p class="text-sm text-amber-700 dark:text-amber-300">
          {{ t('web.organizations.sso.idp_cert_expiring_notice', { date: storedCertExpiry.date }) }}
        </p>
      </div>

      <!-- Provider identity: the label for a saved record (the type is
           locked while editing), the picker for a new one. -->
      <fieldset>
        <legend
          id="provider-type-legend"
          class="border-b border-gray-200 pb-2 text-sm font-medium text-gray-900 dark:border-gray-700 dark:text-white w-full">
          {{ t('web.organizations.sso.provider_type') }}
        </legend>
        <p v-if="!isEditing" class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.provider_type_description') }}
        </p>

        <!-- Locked display when editing existing config -->
        <div
          v-if="isEditing && currentProviderOption"
          class="mt-3 flex items-start gap-2">
          <OIcon
            collection="heroicons"
            name="check-circle-solid"
            class="mt-0.5 size-5 shrink-0 text-brand-600 dark:text-brand-400"
            aria-hidden="true" />
          <div class="text-sm">
            <p class="font-medium text-gray-900 dark:text-white">
              {{ currentProviderOption.label }}
              <span class="font-normal text-gray-500 dark:text-gray-400">
                · {{ currentProviderOption.description }}
              </span>
            </p>
            <p class="mt-0.5 text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.sso.provider_type_locked_hint') }}
            </p>
          </div>
        </div>

        <!-- Selectable radio group when creating new config -->
        <div
          v-else
          class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2"
          role="radiogroup"
          aria-labelledby="provider-type-legend">
          <label
            v-for="option in selectableProviderOptions"
            :key="option.value"
            :class="[
              'relative flex cursor-pointer rounded-lg border p-4 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2',
              formState.provider_type === option.value
                ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                : 'border-gray-300 bg-white hover:border-gray-400 dark:border-gray-600 dark:bg-gray-700 dark:hover:border-gray-500',
            ]">
            <input
              type="radio"
              :id="`domain-provider-${option.value}`"
              :name="'provider_type'"
              :value="option.value"
              :checked="formState.provider_type === option.value"
              @change="updateField('provider_type', option.value)"
              class="sr-only"
              :aria-describedby="`domain-provider-${option.value}-description`" />
            <span class="flex flex-1 flex-col">
              <span
                :class="[
                  'block text-sm font-medium',
                  formState.provider_type === option.value
                    ? 'text-brand-900 dark:text-brand-100'
                    : 'text-gray-900 dark:text-white',
                ]">
                {{ option.label }}
              </span>
              <span
                :id="`domain-provider-${option.value}-description`"
                class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ option.description }}
              </span>
            </span>
            <OIcon
              v-if="formState.provider_type === option.value"
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </label>
        </div>
      </fieldset>

      <!-- Unverified domain (#4579): tenant SSO is refused on this host until
           ownership verification completes; verification does not change the
           values below. Directly above the callback / SP block so an admin
           copying them reads it first. role="status"
           like the certificate advisory; amber is the fixed warning hue
           (#4132) and the text carries the meaning on its own (WCAG 1.4.1). -->
      <div
        v-if="showDomainUnverifiedNotice"
        data-testid="sso-domain-unverified-notice"
        role="status"
        class="flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 dark:bg-amber-900/20">
        <OIcon
          collection="heroicons"
          name="information-circle"
          class="mt-0.5 size-4 flex-shrink-0 text-amber-600 dark:text-amber-400"
          aria-hidden="true" />
        <p class="text-sm text-amber-700 dark:text-amber-300">
          {{ t('web.organizations.sso.domain_unverified_notice') }}
        </p>
      </div>

      <!-- Callback URL (OAuth-family providers): what the admin registers at
           the IdP, as one utility row with its copy control. -->
      <div
        v-if="callbackUrl && !isSaml"
        data-testid="sso-callback-url"
        class="sm:flex sm:items-start sm:gap-4">
        <p
          id="domain-sso-callback-url-label"
          class="text-sm font-medium text-gray-900 sm:w-44 sm:shrink-0 sm:pt-2 dark:text-white">
          {{ t('web.organizations.sso.callback_url') }}
        </p>
        <div class="mt-1 min-w-0 flex-1 sm:mt-0">
          <div class="flex items-center gap-2">
            <code
              aria-labelledby="domain-sso-callback-url-label"
              class="block flex-1 overflow-x-auto rounded-md bg-gray-100 px-3 py-2 text-sm text-gray-800 dark:bg-gray-800 dark:text-gray-200">
              {{ callbackUrl }}
            </code>
            <CopyToClipboardButton
              :is-copied="isCallbackCopied"
              @click="copyToClipboard(callbackUrl ?? '')" />
          </div>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.sso.callback_url_hint') }}
          </p>
        </div>
      </div>

      <!-- SAML service-provider identifiers (#4450), read-only: what the admin
           registers at the IdP. SP Entity ID doubles as the SP metadata URL.
           Host-derived values are labelled a preview (spDetailsArePreview)
           because the static default route may not be the deployed one (#3932). -->
      <div
        v-if="isSaml && (spEntityId || callbackUrl)"
        data-testid="sso-saml-sp-details">
        <p class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.organizations.sso.sp_details') }}
        </p>
        <p
          data-testid="sso-saml-sp-details-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{
            spDetailsArePreview
              ? t('web.organizations.sso.sp_details_preview_hint')
              : t('web.organizations.sso.sp_details_hint')
          }}
        </p>
        <dl class="mt-3 space-y-3">
          <div v-if="spEntityId" class="sm:flex sm:items-start sm:gap-4">
            <dt
              id="domain-sso-sp-entity-id-label"
              class="text-sm font-medium text-gray-900 sm:w-44 sm:shrink-0 sm:pt-2 dark:text-white">
              {{ t('web.organizations.sso.sp_entity_id') }}
            </dt>
            <dd class="mt-1 flex min-w-0 flex-1 items-center gap-2 sm:mt-0">
              <code
                data-testid="sso-saml-sp-entity-id"
                aria-labelledby="domain-sso-sp-entity-id-label"
                class="block flex-1 overflow-x-auto rounded-md bg-gray-100 px-3 py-2 text-sm text-gray-800 dark:bg-gray-800 dark:text-gray-200">
                {{ spEntityId }}
              </code>
              <CopyToClipboardButton
                :is-copied="isSpEntityIdCopied"
                @click="copySpEntityId(spEntityId ?? '')" />
            </dd>
          </div>
          <div v-if="callbackUrl" class="sm:flex sm:items-start sm:gap-4">
            <dt
              id="domain-sso-acs-url-label"
              class="text-sm font-medium text-gray-900 sm:w-44 sm:shrink-0 sm:pt-2 dark:text-white">
              {{ t('web.organizations.sso.acs_url') }}
            </dt>
            <dd class="mt-1 flex min-w-0 flex-1 items-center gap-2 sm:mt-0">
              <code
                data-testid="sso-saml-acs-url"
                aria-labelledby="domain-sso-acs-url-label"
                class="block flex-1 overflow-x-auto rounded-md bg-gray-100 px-3 py-2 text-sm text-gray-800 dark:bg-gray-800 dark:text-gray-200">
                {{ callbackUrl }}
              </code>
              <CopyToClipboardButton
                :is-copied="isCallbackCopied"
                @click="copyToClipboard(callbackUrl ?? '')" />
            </dd>
          </div>
        </dl>
      </div>

      <!-- Identity provider details: a flat form, one spacing rhythm. -->
      <section
        data-testid="sso-provider-details"
        aria-labelledby="sso-provider-details-title"
        class="space-y-5">
        <h4
          id="sso-provider-details-title"
          class="border-b border-gray-200 pb-2 text-sm font-medium text-gray-900 dark:border-gray-700 dark:text-white">
          {{ t('web.organizations.sso.provider_details_title') }}
        </h4>

      <!-- Display Name -->
      <div>
        <label
          for="domain-sso-display-name"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.display_name') }}
          <span class="text-red-500" aria-hidden="true">*</span>
        </label>
        <p
          id="domain-display-name-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.display_name_hint') }}
        </p>
        <input
          id="domain-sso-display-name"
          :value="formState.display_name"
          @input="updateField('display_name', ($event.target as HTMLInputElement).value)"
          type="text"
          required
          maxlength="100"
          :placeholder="t('web.organizations.sso.display_name_placeholder')"
          aria-describedby="domain-display-name-hint"
          class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
      </div>

      <!-- Tenant ID (Entra ID only) -->
      <div v-if="requiresTenantId">
        <label
          for="domain-sso-tenant-id"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.tenant_id') }}
          <span class="text-red-500" aria-hidden="true">*</span>
        </label>
        <p
          id="domain-tenant-id-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.tenant_id_hint') }}
        </p>
        <input
          id="domain-sso-tenant-id"
          :value="formState.tenant_id"
          @input="updateField('tenant_id', ($event.target as HTMLInputElement).value)"
          type="text"
          required
          autocomplete="off"
          :placeholder="t('web.organizations.sso.tenant_id_placeholder')"
          aria-describedby="domain-tenant-id-hint"
          class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
      </div>

      <!-- Client ID (OAuth-family providers; SAML has no client credential) -->
      <div v-if="requiresClientCredentials">
        <label
          for="domain-sso-client-id"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.client_id') }}
          <span class="text-red-500" aria-hidden="true">*</span>
        </label>
        <input
          id="domain-sso-client-id"
          :value="formState.client_id"
          @input="updateField('client_id', ($event.target as HTMLInputElement).value)"
          type="text"
          required
          autocomplete="off"
          :placeholder="t('web.organizations.sso.client_id_placeholder')"
          :aria-invalid="isUnreadable('client_id') || undefined"
          :aria-describedby="isUnreadable('client_id') ? 'domain-sso-client-id-error' : undefined"
          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
        <p
          v-if="isUnreadable('client_id')"
          id="domain-sso-client-id-error"
          class="mt-1 text-sm text-red-600 dark:text-red-400">
          {{ t('web.organizations.sso.unreadable_field') }}
        </p>
      </div>

      <!-- Client Secret -->
      <div v-if="requiresClientCredentials">
        <label
          for="domain-sso-client-secret"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.client_secret') }}
          <span v-if="clientSecretMustBeEntered"
class="text-red-500"
aria-hidden="true">*</span>
        </label>
        <p
          v-if="isUnreadable('client_secret')"
          id="domain-client-secret-hint"
          class="mt-1 text-sm text-red-600 dark:text-red-400">
          {{ t('web.organizations.sso.unreadable_field') }}
        </p>
        <p
          v-else-if="isEditing"
          id="domain-client-secret-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.client_secret_update_hint') }}
        </p>
        <div class="relative mt-1">
          <input
            id="domain-sso-client-secret"
            :value="formState.client_secret"
            @input="updateField('client_secret', ($event.target as HTMLInputElement).value)"
            :type="showClientSecret ? 'text' : 'password'"
            :required="clientSecretMustBeEntered"
            autocomplete="new-password"
            :placeholder="clientSecretPlaceholder"
            :aria-invalid="isUnreadable('client_secret') || undefined"
            :aria-describedby="isEditing ? 'domain-client-secret-hint' : undefined"
            class="block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
          <button
            type="button"
            @click="showClientSecret = !showClientSecret"
            class="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
            :aria-label="showClientSecret ? t('web.COMMON.hide_password') : t('web.COMMON.show_password')">
            <OIcon
              collection="heroicons"
              :name="showClientSecret ? 'eye-slash' : 'eye'"
              class="size-5"
              aria-hidden="true" />
          </button>
        </div>
        <p
          v-if="clientSecretLooksLikeSecretId"
          data-testid="sso-client-secret-shape-hint"
          role="status"
          class="mt-1 text-sm text-amber-700 dark:text-amber-300">
          {{ t('web.organizations.sso.client_secret_looks_like_secret_id') }}
        </p>
      </div>

      <!-- Issuer URL (OIDC only) -->
      <div v-if="requiresIssuer">
        <label
          for="domain-sso-issuer"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.issuer') }}
          <span class="text-red-500" aria-hidden="true">*</span>
        </label>
        <p
          id="domain-issuer-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.issuer_hint') }}
        </p>
        <input
          id="domain-sso-issuer"
          :value="formState.issuer"
          @input="updateField('issuer', ($event.target as HTMLInputElement).value)"
          type="url"
          required
          autocomplete="off"
          :placeholder="t('web.organizations.sso.issuer_placeholder')"
          aria-describedby="domain-issuer-hint"
          class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
        <a
          v-if="discoveryUrl"
          :href="discoveryUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="mt-1 inline-block text-xs text-brand-500 hover:text-brand-600 dark:text-brand-400 dark:hover:text-brand-300">
          {{ t('web.organizations.sso.view_discovery_document') }}
        </a>
      </div>

      <!-- Advanced (OIDC only, #4764): token endpoint client authentication.
           Collapsed unless the saved record carries a non-default method. -->
      <details
        v-if="requiresIssuer"
        :open="advancedOpen"
        @toggle="advancedOpen = ($event.target as HTMLDetailsElement).open"
        data-testid="sso-advanced-oidc">
        <summary
          class="cursor-pointer text-sm font-medium text-gray-700 select-none hover:text-gray-900 dark:text-gray-300 dark:hover:text-white">
          {{ t('web.organizations.sso.advanced_section') }}
        </summary>
        <div class="mt-3">
          <label
            for="domain-sso-token-endpoint-auth-method"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.organizations.sso.token_endpoint_auth_method') }}
          </label>
          <p
            id="domain-token-endpoint-auth-method-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.sso.token_endpoint_auth_method_hint') }}
          </p>
          <select
            id="domain-sso-token-endpoint-auth-method"
            :value="formState.token_endpoint_auth_method"
            @change="updateTokenEndpointAuthMethod(($event.target as HTMLSelectElement).value)"
            aria-describedby="domain-token-endpoint-auth-method-hint"
            class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-white">
            <option
              v-for="option in tokenEndpointAuthMethodOptions"
              :key="option.value"
              :value="option.value">
              {{ t(option.labelKey) }}
            </option>
          </select>
        </div>
      </details>

      <!-- SAML IdP trust anchor (#4450): SSO URL, EntityID, signing cert.
           None is a secret (the IdP publishes all three), so the stored values
           are shown and re-sent as-is; the API stores them AAD-bound to the
           domain for integrity, hence the unreadable_fields error state. -->
      <template v-if="isSaml">
        <!-- IdP SSO service URL -->
        <div>
          <label
            for="domain-sso-idp-sso-service-url"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.organizations.sso.idp_sso_service_url') }}
            <span class="text-red-500" aria-hidden="true">*</span>
          </label>
          <p
            id="domain-sso-idp-sso-service-url-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.sso.idp_sso_service_url_hint') }}
          </p>
          <input
            id="domain-sso-idp-sso-service-url"
            :value="formState.idp_sso_service_url"
            @input="updateField('idp_sso_service_url', ($event.target as HTMLInputElement).value)"
            type="url"
            required
            autocomplete="off"
            pattern="https://.*"
            :placeholder="t('web.organizations.sso.idp_sso_service_url_placeholder')"
            :aria-invalid="isUnreadable('idp_sso_service_url') || undefined"
            :aria-describedby="
              isUnreadable('idp_sso_service_url')
                ? 'domain-sso-idp-sso-service-url-hint domain-sso-idp-sso-service-url-error'
                : 'domain-sso-idp-sso-service-url-hint'
            "
            class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
          <p
            v-if="isUnreadable('idp_sso_service_url')"
            id="domain-sso-idp-sso-service-url-error"
            class="mt-1 text-sm text-red-600 dark:text-red-400">
            {{ t('web.organizations.sso.unreadable_field') }}
          </p>
        </div>

        <!-- IdP EntityID -->
        <div>
          <label
            for="domain-sso-idp-entity-id"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.organizations.sso.idp_entity_id') }}
            <span class="text-red-500" aria-hidden="true">*</span>
          </label>
          <p
            id="domain-sso-idp-entity-id-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.sso.idp_entity_id_hint') }}
          </p>
          <input
            id="domain-sso-idp-entity-id"
            :value="formState.idp_entity_id"
            @input="updateField('idp_entity_id', ($event.target as HTMLInputElement).value)"
            type="text"
            required
            autocomplete="off"
            spellcheck="false"
            :placeholder="t('web.organizations.sso.idp_entity_id_placeholder')"
            :aria-invalid="isUnreadable('idp_entity_id') || undefined"
            :aria-describedby="
              isUnreadable('idp_entity_id')
                ? 'domain-sso-idp-entity-id-hint domain-sso-idp-entity-id-error'
                : 'domain-sso-idp-entity-id-hint'
            "
            class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
          <p
            v-if="isUnreadable('idp_entity_id')"
            id="domain-sso-idp-entity-id-error"
            class="mt-1 text-sm text-red-600 dark:text-red-400">
            {{ t('web.organizations.sso.unreadable_field') }}
          </p>
        </div>

        <!-- IdP signing certificate (one PEM block; fingerprints refused) -->
        <div>
          <label
            for="domain-sso-idp-cert"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300">
            {{ t('web.organizations.sso.idp_cert') }}
            <span class="text-red-500" aria-hidden="true">*</span>
          </label>
          <p
            id="domain-sso-idp-cert-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.sso.idp_cert_hint') }}
          </p>
          <textarea
            id="domain-sso-idp-cert"
            :value="formState.idp_cert"
            @input="updateField('idp_cert', ($event.target as HTMLTextAreaElement).value)"
            rows="6"
            required
            autocomplete="off"
            spellcheck="false"
            wrap="off"
            :placeholder="t('web.organizations.sso.idp_cert_placeholder')"
            :aria-invalid="isUnreadable('idp_cert') || undefined"
            :aria-describedby="
              isUnreadable('idp_cert')
                ? 'domain-sso-idp-cert-hint domain-sso-idp-cert-error'
                : 'domain-sso-idp-cert-hint'
            "
            class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 font-mono text-xs"></textarea>
          <p
            v-if="isUnreadable('idp_cert')"
            id="domain-sso-idp-cert-error"
            class="mt-1 text-sm text-red-600 dark:text-red-400">
            {{ t('web.organizations.sso.unreadable_field') }}
          </p>
        </div>
      </template>
      </section>

      <!-- Domain Allowlist (only for providers without IdP-side access control) -->
      <div v-if="showDomainFilter">
        <label
          for="domain-sso-domain-input"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.allowed_domains') }}
        </label>
        <p
          id="domain-allowed-domains-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.allowed_domains_hint') }}
        </p>

        <!-- Domain chips -->
        <div
          v-if="formState.allowed_domains && formState.allowed_domains.length > 0"
          class="mt-2 flex flex-wrap gap-2"
          role="list"
          :aria-label="t('web.organizations.sso.allowed_domains')">
          <span
            v-for="domain in formState.allowed_domains"
            :key="domain"
            role="listitem"
            class="inline-flex items-center gap-1 rounded-full bg-gray-100 px-3 py-1 text-sm text-gray-700 dark:bg-gray-600 dark:text-gray-200">
            {{ domain }}
            <button
              type="button"
              @click="removeDomain(domain)"
              class="ml-1 rounded-full p-0.5 text-gray-400 hover:bg-gray-200 hover:text-gray-600 dark:hover:bg-gray-500 dark:hover:text-gray-100"
              :aria-label="t('web.organizations.sso.remove_domain', { domain })">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-4"
                aria-hidden="true" />
            </button>
          </span>
        </div>

        <!-- Add domain input -->
        <div class="mt-2 flex gap-2">
          <div class="flex-1">
            <input
              id="domain-sso-domain-input"
              v-model="newDomain"
              type="text"
              :placeholder="t('web.organizations.sso.domain_placeholder')"
              aria-describedby="domain-allowed-domains-hint domain-domain-input-error"
              :aria-invalid="!!domainInputError"
              @keydown.enter.prevent="addDomain"
              class="block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
          </div>
          <button
            type="button"
            @click="addDomain"
            class="inline-flex items-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
            {{ t('web.COMMON.add') }}
          </button>
        </div>
        <p
          v-if="domainInputError"
          id="domain-domain-input-error"
          class="mt-1 text-sm text-red-600 dark:text-red-400"
          role="alert">
          {{ domainInputError }}
        </p>
      </div>

      <!-- The primary check panel: heading, hint, warnings and results. Its
           action (sso-diagnostics-run) is in the sticky footer. The run
           saves when needed, checks the saved configuration, and turns a
           record that is off on when the check passes. -->
      <section
        data-testid="sso-diagnostics"
        aria-labelledby="sso-diagnostics-title">
        <h4
          id="sso-diagnostics-title"
          class="border-b border-gray-200 pb-2 text-sm font-medium text-gray-900 dark:border-gray-700 dark:text-white">
          {{ t('web.organizations.sso.diagnostics_title') }}
        </h4>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{
            t(
              isSaml
                ? 'web.organizations.sso.diagnostics_hint_saml'
                : requiresTenantId
                  ? 'web.organizations.sso.diagnostics_hint_entra'
                  : 'web.organizations.sso.diagnostics_hint'
            )
          }}
        </p>
        <p
          v-if="!connectionOn"
          data-testid="sso-diagnostics-activation-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.diagnostics_activation_hint') }}
        </p>

        <!-- Changed credentials on a connection that is on (advisory, never
             a gate: saving stays possible). role="alert" so it is announced
             when it appears; amber is the fixed warning hue (#4132) and the
             text carries the meaning on its own (WCAG 1.4.1). -->
        <div
          v-if="showUncheckedCredentialsWarning"
          data-testid="sso-credentials-unchecked-warning"
          role="alert"
          class="mt-3 flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 dark:bg-amber-900/20">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle"
            class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400"
            aria-hidden="true" />
          <p class="text-sm text-amber-700 dark:text-amber-300">
            {{ t('web.organizations.sso.credentials_unchecked_warning') }}
          </p>
        </div>

        <!-- Diagnostics Result -->
        <div
          v-if="diagnosticsResult || diagnosticsError"
          class="mt-4">
          <div
            v-if="diagnosticsResult && diagnosticsOverallStyle"
            data-testid="sso-diagnostics-result"
            :data-overall="diagnosticsResult.overall"
            :role="diagnosticsOverallStyle.role"
            :aria-live="diagnosticsOverallStyle.live"
            :class="diagnosticsOverallStyle.box">
            <div class="flex">
              <OIcon
                collection="heroicons"
                :name="diagnosticsOverallStyle.icon"
                :class="diagnosticsOverallStyle.iconClass"
                aria-hidden="true" />
              <div class="ml-3 min-w-0 flex-1">
                <p
                  data-testid="sso-diagnostics-summary"
                  class="text-sm font-medium"
                  :class="diagnosticsOverallStyle.text">
                  {{ t(`web.organizations.sso.diagnostics_${diagnosticsResult.overall}`) }}
                </p>
                <!-- What the run did to the connection (activation). -->
                <p
                  v-if="activationNotice"
                  data-testid="sso-activation-notice"
                  :data-activation="activationNotice.activation"
                  :class="[
                    'mt-2 text-sm font-medium',
                    activationNotice.tone === 'ok'
                      ? 'text-green-800 dark:text-green-200'
                      : 'text-amber-800 dark:text-amber-200',
                  ]">
                  {{ activationNotice.text }}
                </p>
                <p
                  v-if="diagnosticsResult.overall === 'passed' && (hasUnsavedChanges || showDiagnosticsNext)"
                  data-testid="sso-diagnostics-next"
                  class="mt-2 text-sm text-gray-800 dark:text-gray-100">
                  {{
                    t(
                      hasUnsavedChanges
                        ? 'web.organizations.sso.diagnostics_saved_result'
                        : 'web.organizations.sso.diagnostics_next'
                    )
                  }}
                </p>
                <ul class="mt-3 space-y-3">
                  <li
                    v-for="check in diagnosticsResult.checks"
                    :key="check.check"
                    :data-testid="`sso-diagnostics-check-${check.check}`"
                    :data-status="check.status"
                    class="text-sm text-gray-800 dark:text-gray-100">
                    <div class="flex flex-wrap items-center gap-2">
                      <span
                        data-testid="sso-diagnostics-status"
                        class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
                        :class="DIAGNOSTIC_STATUS_CHIPS[check.status].classes">
                        {{ t(DIAGNOSTIC_STATUS_CHIPS[check.status].labelKey) }}
                      </span>
                      <span class="font-medium">{{ diagnosticCheckLabel(check) }}</span>
                    </div>
                    <p class="mt-1 text-gray-700 dark:text-gray-300">{{ check.message }}</p>
                    <p
                      v-if="check.details?.note"
                      data-testid="sso-diagnostics-note"
                      class="mt-1 text-gray-700 dark:text-gray-300">
                      {{ check.details.note }}
                    </p>
                    <details
                      v-if="hasDiagnosticTechnicalDetails(check)"
                      data-testid="sso-diagnostics-technical-details"
                      :open="
                        check.status !== 'passed' ||
                        check.details.token_endpoint_auth_method_supported === false
                      "
                      class="mt-2">
                      <summary class="cursor-pointer font-medium">
                        {{ t('web.organizations.sso.technical_details') }}
                      </summary>
                      <dl
                        data-testid="sso-diagnostics-details"
                        class="mt-1 space-y-1 text-gray-700 dark:text-gray-300">
                        <div
                          v-if="check.details.error_code"
                          class="flex gap-2">
                          <dt class="shrink-0 font-medium">{{ t('web.COMMON.error_code') }}:</dt>
                          <dd class="font-mono break-all">{{ check.details.error_code }}</dd>
                        </div>
                        <div
                          v-if="check.details.aadsts_code"
                          class="flex gap-2">
                          <dt class="shrink-0 font-medium">
                            {{ t('web.organizations.sso.diagnostics_aadsts_code') }}:
                          </dt>
                          <dd class="font-mono break-all">{{ check.details.aadsts_code }}</dd>
                        </div>
                        <div
                          v-if="check.details.http_status"
                          class="flex gap-2">
                          <dt class="shrink-0 font-medium">{{ t('web.COMMON.http_status') }}:</dt>
                          <dd>{{ check.details.http_status }}</dd>
                        </div>
                        <template v-if="check.details.error_code === 'issuer_mismatch'">
                          <div class="flex gap-2">
                            <dt class="shrink-0 font-medium">
                              {{ t('web.organizations.sso.configured_issuer') }}:
                            </dt>
                            <dd>
                              <code
                                class="font-mono break-all"
                                data-testid="sso-diagnostics-configured-issuer"
                                >{{ check.details.configured_issuer }}</code
                              >
                            </dd>
                          </div>
                          <div class="flex gap-2">
                            <dt class="shrink-0 font-medium">
                              {{ t('web.organizations.sso.discovery_issuer') }}:
                            </dt>
                            <dd>
                              <code
                                class="font-mono break-all"
                                data-testid="sso-diagnostics-discovery-issuer"
                                >{{ check.details.discovery_issuer ?? '—' }}</code
                              >
                            </dd>
                          </div>
                        </template>
                        <div
                          v-if="check.details.errors?.length"
                          class="flex gap-2">
                          <dt class="shrink-0 font-medium">
                            {{ t('web.organizations.sso.diagnostics_errors') }}:
                          </dt>
                          <dd class="break-words">{{ check.details.errors.join('; ') }}</dd>
                        </div>
                        <div
                          v-if="check.details.certificate_not_after"
                          class="flex gap-2">
                          <dt class="shrink-0 font-medium">
                            {{ t('web.organizations.sso.certificate_expires') }}:
                          </dt>
                          <dd>
                            {{ formatDiagnosticDate(check.details.certificate_not_after) }}
                            <span v-if="check.details.certificate_expires_in_days !== undefined">
                              ({{
                                t(
                                  'web.organizations.sso.certificate_expires_in_days',
                                  check.details.certificate_expires_in_days
                                )
                              }})
                            </span>
                          </dd>
                        </div>
                        <div
                          v-if="check.details.token_endpoint_auth_methods_supported?.length"
                          class="flex gap-2">
                          <dt class="shrink-0 font-medium">
                            {{ t('web.organizations.sso.token_endpoint_auth_methods_supported') }}:
                          </dt>
                          <dd class="font-mono break-all">
                            {{ check.details.token_endpoint_auth_methods_supported.join(', ') }}
                          </dd>
                        </div>
                      </dl>
                    </details>
                  </li>
                </ul>
                <details
                  data-testid="sso-diagnostics-run-details"
                  :open="diagnosticsResult.overall !== 'passed'"
                  class="mt-3 text-sm text-gray-700 dark:text-gray-300">
                  <summary class="cursor-pointer font-medium">
                    {{ t('web.organizations.sso.check_details') }}
                  </summary>
                  <p
                    data-testid="sso-diagnostics-checked-at"
                    class="mt-1">
                    {{ t('web.organizations.sso.diagnostics_checked_at') }}:
                    {{ diagnosticsCheckedAt }}
                  </p>
                </details>
              </div>
            </div>
          </div>

          <!-- No verdict was received; the server may still have activated
               the connection. Announced like the failed verdict (role="alert"). -->
          <div
            v-else-if="diagnosticsError"
            data-testid="sso-diagnostics-error"
            role="alert"
            aria-live="assertive"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
            <div class="flex">
              <OIcon
                collection="heroicons"
                name="exclamation-triangle-solid"
                class="size-5 text-red-400"
                aria-hidden="true" />
              <div class="ml-3">
                <p class="text-sm font-medium text-red-800 dark:text-red-200">
                  {{ diagnosticsError }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Provider discovery check (D7): an optional check of the CURRENT form
           values. It saves nothing and never verifies the secret, so it is
           neither the saved-configuration check above nor a sign-in. Collapsed
           by default; a result opens it so it is never hidden. -->
      <details
        data-testid="sso-provider-check"
        :open="providerCheckOpen"
        @toggle="providerCheckOpen = ($event.target as HTMLDetailsElement).open">
        <summary
          class="cursor-pointer text-sm font-medium text-gray-700 select-none hover:text-gray-900 dark:text-gray-300 dark:hover:text-white">
          {{ t('web.organizations.sso.test_connection') }}
        </summary>
        <div class="mt-2 flex flex-col items-start gap-3 sm:flex-row sm:justify-between">
          <p class="min-w-0 flex-1 text-sm text-gray-500 dark:text-gray-400">
            {{ isSaml ? t('web.organizations.sso.test_connection_hint_saml') : t('web.organizations.sso.test_connection_hint') }}
          </p>
          <button
            type="button"
            @click="handleTestConnection"
            :disabled="!canTestConnection || isTesting || isSaving"
            class="inline-flex shrink-0 items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-600 dark:text-gray-100 dark:ring-gray-500 dark:hover:bg-gray-500">
            <OIcon
              v-if="isTesting"
              collection="heroicons"
              name="arrow-path"
              size="4"
              class="animate-spin motion-reduce:animate-none"
              aria-hidden="true" />
            <OIcon
              v-else
              collection="heroicons"
              name="signal"
              size="4"
              aria-hidden="true" />
            {{ isTesting ? t('web.organizations.sso.testing') : t('web.organizations.sso.test_button') }}
          </button>
        </div>

        <!-- Test Result -->
        <div
          v-if="testResult || testError"
          class="mt-4">
          <!-- Success Result -->
          <div
            v-if="testResult?.success"
            role="status"
            aria-live="polite"
            class="rounded-md bg-green-50 p-4 dark:bg-green-900/20">
            <div class="flex">
              <OIcon
                collection="heroicons"
                name="check-circle-solid"
                class="size-5 text-green-400"
                aria-hidden="true" />
              <div class="ml-3">
                <h5 class="text-sm font-medium text-green-800 dark:text-green-200">
                  {{ testResult.message }}
                </h5>
                <!-- The API's note. With an unadvertised token endpoint auth
                     method (#4764) it explains a gap, so it reads as a warning;
                     otherwise it is part of the confirmation. -->
                <p
                  v-if="testResult.details?.note"
                  data-testid="sso-test-note"
                  :class="
                    tokenEndpointAuthMethodUnadvertised
                      ? 'mt-2 flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-700 dark:bg-amber-900/20 dark:text-amber-300'
                      : 'mt-1 text-sm text-green-700 dark:text-green-300'
                  ">
                  <OIcon
                    v-if="tokenEndpointAuthMethodUnadvertised"
                    collection="heroicons"
                    name="exclamation-triangle"
                    class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400"
                    aria-hidden="true" />
                  <span>{{ testResult.details.note }}</span>
                </p>
                <p
                  class="mt-2 text-sm text-green-800 dark:text-green-200"
                  data-testid="sso-provider-check-next">
                  {{ t('web.organizations.sso.provider_check_next') }}
                </p>
                <details
                  v-if="advertisedTokenEndpointAuthMethods?.length"
                  data-testid="sso-test-technical-details"
                  :open="tokenEndpointAuthMethodUnadvertised"
                  class="mt-2 text-sm text-green-700 dark:text-green-300">
                  <summary class="cursor-pointer font-medium">
                    {{ t('web.organizations.sso.technical_details') }}
                  </summary>
                  <dl
                    v-if="advertisedTokenEndpointAuthMethods?.length"
                    data-testid="sso-test-token-endpoint-auth-methods"
                    class="mt-2 space-y-1 text-sm text-green-700 dark:text-green-300">
                    <div class="flex gap-2">
                      <dt class="shrink-0 font-medium">
                        {{ t('web.organizations.sso.token_endpoint_auth_methods_supported') }}:
                      </dt>
                      <dd class="font-mono break-all">
                        {{ advertisedTokenEndpointAuthMethods.join(', ') }}
                      </dd>
                    </div>
                  </dl>
                </details>
                <!-- SAML (#4450): the test is local, so it reports what it
                     parsed — the certificate's subject and expiry. -->
                <dl
                  v-if="testResult.details?.certificate_subject || certificateExpiry"
                  data-testid="sso-test-saml-details"
                  class="mt-2 space-y-1 text-sm text-green-700 dark:text-green-300">
                  <div v-if="testResult.details.certificate_subject" class="flex gap-2">
                    <dt class="font-medium">{{ t('web.organizations.sso.certificate_subject') }}:</dt>
                    <dd class="break-all">{{ testResult.details.certificate_subject }}</dd>
                  </div>
                  <div v-if="certificateExpiry" class="flex gap-2">
                    <dt class="font-medium">{{ t('web.organizations.sso.certificate_expires') }}:</dt>
                    <dd>
                      {{ certificateExpiry.date }}
                      <span v-if="certificateExpiry.days !== undefined">
                        ({{ t('web.organizations.sso.certificate_expires_in_days', certificateExpiry.days) }})
                      </span>
                    </dd>
                  </div>
                </dl>
              </div>
            </div>
          </div>

          <!-- Failure Result -->
          <div
            v-else-if="testResult && !testResult.success"
            role="alert"
            aria-live="assertive"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
            <div class="flex">
              <OIcon
                collection="heroicons"
                name="x-circle-solid"
                class="size-5 text-red-400"
                aria-hidden="true" />
              <div class="ml-3">
                <h5 class="text-sm font-medium text-red-800 dark:text-red-200">
                  {{ testResult.message }}
                </h5>
                <div
                  v-if="testResult.details"
                  class="mt-2 text-sm text-red-700 dark:text-red-300">
                  <dl class="space-y-1">
                    <div v-if="testResult.details.error_code" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.COMMON.error_code') }}:</dt>
                      <dd>{{ testResult.details.error_code }}</dd>
                    </div>
                    <div v-if="testResult.details.http_status" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.COMMON.http_status') }}:</dt>
                      <dd>{{ testResult.details.http_status }}</dd>
                    </div>
                    <div v-if="testResult.details.field" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.COMMON.field') }}:</dt>
                      <dd>{{ t(UNREADABLE_FIELD_LABELS[testResult.details.field] ?? testResult.details.field) }}</dd>
                    </div>
                    <div v-if="testResult.details.description" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.COMMON.details') }}:</dt>
                      <dd>{{ testResult.details.description }}</dd>
                    </div>
                    <div v-if="certificateValidFrom" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.organizations.sso.certificate_valid_from') }}:</dt>
                      <dd>{{ certificateValidFrom }}</dd>
                    </div>
                    <div v-if="certificateExpiry" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.organizations.sso.certificate_expires') }}:</dt>
                      <dd>{{ certificateExpiry.date }}</dd>
                    </div>
                    <div v-if="testResult.details.missing_fields?.length" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.organizations.sso.missing_fields') }}:</dt>
                      <dd>{{ testResult.details.missing_fields.join(', ') }}</dd>
                    </div>
                    <template v-if="testResult.details.error_code === 'issuer_mismatch'">
                      <div class="flex gap-2">
                        <dt class="shrink-0 font-medium">
                          {{ t('web.organizations.sso.configured_issuer') }}:
                        </dt>
                        <dd>
                          <code
                            class="font-mono break-all"
                            data-testid="sso-configured-issuer">{{
                              testResult.details.configured_issuer
                            }}</code>
                        </dd>
                      </div>
                      <div class="flex gap-2">
                        <dt class="shrink-0 font-medium">
                          {{ t('web.organizations.sso.discovery_issuer') }}:
                        </dt>
                        <dd>
                          <code
                            class="font-mono break-all"
                            data-testid="sso-discovery-issuer">{{
                              testResult.details.discovery_issuer ?? '—'
                            }}</code>
                        </dd>
                      </div>
                    </template>
                  </dl>
                  <p
                    v-if="testResult.details.error_code === 'issuer_mismatch'"
                    class="mt-2"
                    data-testid="sso-issuer-mismatch-hint">
                    {{ t('web.organizations.sso.issuer_mismatch_hint') }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- Error (exception) -->
          <div
            v-else-if="testError"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
            <div class="flex">
              <OIcon
                collection="heroicons"
                name="exclamation-triangle-solid"
                class="size-5 text-red-400"
                aria-hidden="true" />
              <div class="ml-3">
                <p class="text-sm font-medium text-red-800 dark:text-red-200">
                  {{ testError }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </details>

      <section
        data-testid="sso-confirm-sign-in"
        aria-labelledby="sso-confirm-sign-in-title">
        <h4
          id="sso-confirm-sign-in-title"
          class="border-b border-gray-200 pb-2 text-sm font-medium text-gray-900 dark:border-gray-700 dark:text-white">
          {{ t('web.organizations.sso.confirm_sign_in') }}
        </h4>
        <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.confirm_sign_in_hint', { domain: domainHost }) }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.confirm_sign_in_limits') }}
        </p>
        <!-- The domain's sign-in settings withhold SSO (verdict
             sso_not_permitted), so this step cannot work yet. role="status";
             amber is the fixed warning hue (#4132) and the text carries the
             meaning on its own (WCAG 1.4.1). -->
        <div
          v-if="signInNotPermitted"
          data-testid="sso-confirm-sign-in-not-permitted"
          role="status"
          class="mt-3 flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 dark:bg-amber-900/20">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle"
            class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400"
            aria-hidden="true" />
          <p class="text-sm text-amber-700 dark:text-amber-300">
            {{ t('web.organizations.sso.confirm_sign_in_not_permitted') }}
          </p>
        </div>
        <div
          v-if="isConfigured"
          class="mt-2 flex flex-wrap items-start justify-between gap-2">
          <p
            data-testid="sso-last-sign-in"
            :data-result="lastSignIn?.result ?? 'none'"
            aria-live="polite"
            :class="[
              'min-w-0 flex-1 text-sm',
              lastSignIn?.result === 'failed'
                ? 'text-red-700 dark:text-red-300'
                : 'text-gray-700 dark:text-gray-300',
            ]">
            {{ lastSignInText }}
          </p>
          <button
            type="button"
            data-testid="sso-last-sign-in-refresh"
            :disabled="isRefreshingLastSignIn"
            :aria-busy="isRefreshingLastSignIn"
            @click="emit('refresh-last-sign-in')"
            class="inline-flex shrink-0 items-center gap-1.5 rounded-md bg-white px-2.5 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-gray-300 ring-inset hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            <OIcon
              collection="heroicons"
              name="arrow-path"
              size="4"
              :class="isRefreshingLastSignIn ? 'animate-spin motion-reduce:animate-none' : ''"
              aria-hidden="true" />
            {{ t('web.organizations.sso.last_sign_in_refresh') }}
          </button>
        </div>
      </section>

      <!-- Grant Org Scope Toggle (withheld pending testing unless already
           granted, so an existing grant stays revocable — see showGrantOrgScope) -->
      <div
        v-if="showGrantOrgScope"
        class="flex items-center justify-between gap-4">
        <div>
          <p class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.organizations.sso.grant_org_scope') }}
          </p>
          <p
            id="domain-grant-org-scope-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.sso.grant_org_scope_hint') }}
          </p>
        </div>
        <ToggleWithIcon
          data-testid="grant-org-scope-toggle"
          :enabled="formState.grant_org_scope"
          :disabled="isSaving"
          @update:enabled="updateField('grant_org_scope', $event)" />
      </div>

      <!-- Danger zone (D6): delete is the only way to remove a record and the
           one destructive action here, so it stands apart from the footer. -->
      <section
        v-if="isEditing"
        data-testid="sso-danger-zone"
        aria-labelledby="sso-danger-zone-title"
        class="rounded-lg border border-red-200 p-4 dark:border-red-900/50">
        <h4
          id="sso-danger-zone-title"
          class="text-sm font-medium text-red-700 dark:text-red-300">
          {{ t('web.COMMON.danger_zone') }}
        </h4>
        <div class="mt-2 flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p class="text-sm text-gray-600 dark:text-gray-300">
            {{ t('web.organizations.sso.delete_config_hint') }}
          </p>
          <button
            v-if="!showDeleteConfirm"
            type="button"
            @click="showDeleteConfirm = true"
            :disabled="isDeleting || isSaving"
            class="inline-flex shrink-0 items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-red-600 shadow-sm ring-1 ring-inset ring-red-300 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-red-400 dark:ring-red-700 dark:hover:bg-red-900/20">
            <OIcon
              collection="heroicons"
              name="trash"
              class="size-4"
              aria-hidden="true" />
            {{ t('web.organizations.sso.delete_config') }}
          </button>
          <div
            v-else
            class="flex flex-wrap items-center gap-2">
            <span class="text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.organizations.sso.delete_confirm') }}
            </span>
            <button
              type="button"
              @click="handleDelete"
              :disabled="isDeleting"
              class="inline-flex items-center rounded-md bg-red-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-500 dark:hover:bg-red-400">
              {{ isDeleting ? t('web.COMMON.processing') : t('web.COMMON.yes_delete') }}
            </button>
            <button
              type="button"
              @click="showDeleteConfirm = false"
              :disabled="isDeleting"
              class="inline-flex items-center rounded-md bg-white px-3 py-1.5 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
              {{ t('web.COMMON.word_cancel') }}
            </button>
          </div>
        </div>
      </section>

      <!-- Footer, sticky to the viewport bottom: the primary action first,
           then Discard whenever there is something to discard, and Save for a
           record that exists (a new record is saved by the check, so setup
           has one save path; saving never turns the connection on). One
           control per action. The negative margin spans the host card's
           horizontal padding so the top border meets the card edges. -->
      <div
        data-testid="sso-form-footer"
        class="sticky bottom-0 z-10 -mx-6 flex flex-wrap items-center justify-between gap-3 rounded-b-lg border-t border-gray-200 bg-white px-6 py-4 dark:border-gray-700 dark:bg-gray-800">
        <button
          type="button"
          data-testid="sso-diagnostics-run"
          :data-action="checkNeedsSave ? 'save-and-check' : connectionOn ? 'check' : 'check-and-activate'"
          @click="handleRunCheck"
          :disabled="!canRunCheck"
          class="inline-flex shrink-0 items-center gap-2 rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
          <OIcon
            v-if="isDiagnosing || isSaving"
            collection="heroicons"
            name="arrow-path"
            size="4"
            class="animate-spin motion-reduce:animate-none"
            aria-hidden="true" />
          <OIcon
            v-else
            collection="heroicons"
            name="clipboard-document-check"
            size="4"
            aria-hidden="true" />
          {{ checkButtonLabel }}
        </button>

        <div
          v-if="isEditing || hasUnsavedChanges"
          class="flex flex-wrap items-center gap-3">
          <button
            v-if="hasUnsavedChanges && !showDeleteConfirm"
            type="button"
            @click="emit('discard')"
            :disabled="isSaving"
            class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            {{ t('web.domains.email.discard_changes') }}
          </button>
          <button
            v-if="isEditing"
            type="submit"
            data-testid="sso-save"
            :disabled="!isFormValid || isSaving || isDeleting"
            class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            <OIcon
              v-if="isSaving"
              collection="heroicons"
              name="arrow-path"
              class="size-4 animate-spin motion-reduce:animate-none"
              aria-hidden="true" />
            <span v-if="isSaving">{{ t('web.COMMON.saving') }}</span>
            <span v-else>{{ t('web.COMMON.save_changes') }}</span>
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
