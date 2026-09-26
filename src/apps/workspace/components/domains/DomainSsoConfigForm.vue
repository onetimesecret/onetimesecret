<!-- src/apps/workspace/components/domains/DomainSsoConfigForm.vue -->

<script setup lang="ts">
/**
 * Domain SSO Configuration Form
 *
 * Presentational component that receives SSO config state via props
 * and emits events for actions. Parent (DomainSso.vue) manages state
 * via useSsoConfig composable.
 */
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
import CopyToClipboardButton from '@/shared/components/ui/CopyToClipboardButton.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import { useClipboard } from '@/shared/composables/useClipboard';
import {
  SSO_PROVIDER_ROUTE_NAMES,
  ssoProviderUsesClientCredentials,
  type CustomDomainSsoConfig,
  type SsoProviderType,
} from '@/schemas/shapes/domains/sso-config';
import type { SsoConfigFormState } from '@/shared/composables/useSsoConfig';
import type { TestSsoConnectionResponse } from '@/services/sso.service';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

const props = defineProps<{
  domainExtId: string;
  domainHost: string;
  orgId: string;
  formState: SsoConfigFormState;
  ssoConfig: CustomDomainSsoConfig | null;
  isLoading: boolean;
  isSaving: boolean;
  isDeleting: boolean;
  isTesting: boolean;
  hasUnsavedChanges: boolean;
  isConfigured: boolean;
  clientSecretMasked: string | null;
  testResult: TestSsoConnectionResponse | null;
  testError: string;
}>();

// ---------------------------------------------------------------------------
// Emits
// ---------------------------------------------------------------------------

const emit = defineEmits<{
  (e: 'save'): void;
  (e: 'disable'): void;
  (e: 'delete'): void;
  (e: 'test'): void;
  (e: 'discard'): void;
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

// ---------------------------------------------------------------------------
// Local UI state
// ---------------------------------------------------------------------------

const showDeleteConfirm = ref(false);
const showDisableConfirm = ref(false);
const actionPending = computed(
  () => props.isLoading || props.isSaving || props.isDeleting || props.isTesting
);
watch(
  () => props.domainExtId,
  () => {
    showDisableConfirm.value = false;
  }
);
const showClientSecret = ref(false);
const newDomain = ref('');
const domainInputError = ref('');

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

// ---------------------------------------------------------------------------
// Computed: form validation and display logic
// ---------------------------------------------------------------------------

const isEditing = computed(() => props.isConfigured);

const isSaml = computed(() => props.formState.provider_type === 'saml');

const requiresTenantId = computed(() => props.formState.provider_type === 'entra_id');

const requiresIssuer = computed(() => props.formState.provider_type === 'oidc');

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
 */
const ssoRouteBase = computed(() => {
  if (!props.domainHost) return null;
  const route = SSO_PROVIDER_ROUTE_NAMES[props.formState.provider_type];
  return `https://${props.domainHost}/auth/sso/${route}`;
});

/**
 * For a saved saml record the API composes the SP identifiers itself
 * (sp_entity_id / acs_url); the provider type is locked while editing, so
 * the record's values are for the type shown. Before a record exists (or
 * when the API could not derive them) they are previewed from the host.
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
 * login with an opaque IdP-side error).
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
 * flips it off, so it doesn't vanish mid-edit. It is scoped per domain: this
 * instance is reused across domains (no :key in SsoCredentialsModal), so when
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
  if (!isFormValid.value || props.isSaving) return;
  emit('save');
};

const handleDisable = () => {
  // Saved state controls recovery; repair-form validity and drafts do not.
  if (!props.ssoConfig?.enabled || actionPending.value) return;
  emit('disable');
  showDisableConfirm.value = false;
};

const handleDelete = () => {
  if (props.isDeleting) return;
  emit('delete');
  showDeleteConfirm.value = false;
};

/**
 * Weak test-before-enable warning (#4111 part 4).
 *
 * Deliberately NOT a gate: the availability ladder still guards runtime, and
 * blocking the save would strand the #4107 cohort (configs saved with live
 * intent, flag-stuck since June) with no way to turn their connection back on.
 * Industry practice (Okta/Auth0/WorkOS) sequences activation after a test, so
 * we advise the same order and let the operator proceed.
 *
 * Scope is this editing session: the record carries no "has ever passed a
 * test" field, so the only honest claim is about the test run here. Warning on
 * every already-enabled config would be noise on every open, so it fires only
 * when the operator flips the toggle ON without a passing test in view; it
 * clears when they flip it back off, when a test passes, or when a different
 * domain's config is loaded into this reused instance.
 */
const connectionEnabledTouchedOn = ref(false);

const testPassedThisSession = computed(() => props.testResult?.success === true);

const showEnableUntestedWarning = computed(
  () => connectionEnabledTouchedOn.value && props.formState.enabled && !testPassedThisSession.value
);

const handleConnectionEnabledChange = (value: boolean) => {
  connectionEnabledTouchedOn.value = value;
  updateField('enabled', value);
};

watch(
  () => props.domainExtId,
  () => {
    connectionEnabledTouchedOn.value = false;
  }
);

const handleTestConnection = () => {
  if (!canTestConnection.value || props.isTesting) return;
  emit('test');
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
  <div class="space-y-6">
    <!-- Loading State -->
    <SettingsSkeleton
      v-if="isLoading"
      :heading="false" />

    <!-- Form -->
    <form v-else
@submit.prevent="handleSave"
class="space-y-6">
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

      <!-- Provider Selection (locked when editing, selectable when creating) -->
      <fieldset>
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.organizations.sso.provider_type') }}
        </legend>
        <p v-if="!isEditing" class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.provider_type_description') }}
        </p>

        <!-- Locked display when editing existing config -->
        <div v-if="isEditing && currentProviderOption" class="mt-4">
          <div class="relative flex rounded-lg border border-brand-500 bg-brand-50 p-4 dark:border-brand-400 dark:bg-brand-900/20">
            <span class="flex flex-1 flex-col">
              <span class="block text-sm font-medium text-brand-900 dark:text-brand-100">
                {{ currentProviderOption.label }}
              </span>
              <span class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ currentProviderOption.description }}
              </span>
              <span class="mt-2 text-xs text-gray-400 dark:text-gray-500">
                {{ t('web.organizations.sso.provider_type_locked_hint') }}
              </span>
            </span>
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </div>
        </div>

        <!-- Selectable radio group when creating new config -->
        <div
          v-else
          class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2"
          role="radiogroup"
          aria-labelledby="provider-type-legend">
          <label
            v-for="option in providerOptions"
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

      <!-- Test Connection -->
      <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <h4 class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.organizations.sso.test_connection') }}
            </h4>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ isSaml ? t('web.organizations.sso.test_connection_hint_saml') : t('web.organizations.sso.test_connection_hint') }}
            </p>
          </div>
          <button
            type="button"
            @click="handleTestConnection"
            :disabled="!canTestConnection || isTesting || isSaving"
            class="ml-4 inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-600 dark:text-gray-100 dark:ring-gray-500 dark:hover:bg-gray-500">
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
                <p
                  v-if="testResult.details?.note"
                  class="mt-1 text-sm text-green-700 dark:text-green-300">
                  {{ testResult.details.note }}
                </p>
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
                  </dl>
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
      </div>

      <!-- Callback URL (OAuth-family providers) -->
      <div
        v-if="callbackUrl && !isSaml"
        class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <label class="block text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.organizations.sso.callback_url') }}
        </label>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.callback_url_hint') }}
        </p>
        <div class="mt-2 flex items-center gap-2">
          <code
            class="block flex-1 overflow-x-auto rounded-md border border-gray-300 bg-gray-100 px-3 py-2 text-sm text-gray-800 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
            {{ callbackUrl }}
          </code>
          <CopyToClipboardButton
            :is-copied="isCallbackCopied"
            @click="copyToClipboard(callbackUrl ?? '')" />
        </div>
      </div>

      <!-- SAML service-provider identifiers (#4450), read-only: what the admin
           registers at the IdP. SP Entity ID doubles as the SP metadata URL.
           Host-derived values are labelled a preview (spDetailsArePreview)
           because the static default route may not be the deployed one (#3932). -->
      <div
        v-if="isSaml && (spEntityId || callbackUrl)"
        data-testid="sso-saml-sp-details"
        class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
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
          <div v-if="spEntityId">
            <dt
              id="domain-sso-sp-entity-id-label"
              class="text-xs font-medium uppercase tracking-wide text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.sso.sp_entity_id') }}
            </dt>
            <dd class="mt-1 flex items-center gap-2">
              <code
                data-testid="sso-saml-sp-entity-id"
                aria-labelledby="domain-sso-sp-entity-id-label"
                class="block flex-1 overflow-x-auto rounded-md border border-gray-300 bg-gray-100 px-3 py-2 text-sm text-gray-800 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
                {{ spEntityId }}
              </code>
              <CopyToClipboardButton
                :is-copied="isSpEntityIdCopied"
                @click="copySpEntityId(spEntityId ?? '')" />
            </dd>
          </div>
          <div v-if="callbackUrl">
            <dt
              id="domain-sso-acs-url-label"
              class="text-xs font-medium uppercase tracking-wide text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.sso.acs_url') }}
            </dt>
            <dd class="mt-1 flex items-center gap-2">
              <code
                data-testid="sso-saml-acs-url"
                aria-labelledby="domain-sso-acs-url-label"
                class="block flex-1 overflow-x-auto rounded-md border border-gray-300 bg-gray-100 px-3 py-2 text-sm text-gray-800 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
                {{ callbackUrl }}
              </code>
              <CopyToClipboardButton
                :is-copied="isCallbackCopied"
                @click="copyToClipboard(callbackUrl ?? '')" />
            </dd>
          </div>
        </dl>
      </div>

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

      <!-- Connection Enabled Toggle (#4107) — writes SsoConfig.enabled, the
           credential record's own operational flag. Deliberately independent of
           the SigninConfig sso_enabled policy toggle on Sign-in Settings: the
           availability ladder requires BOTH before the sign-in page offers SSO.
           This was the field's only UI writer; dropping it (7326689cdc) left
           every saved config stuck at enabled=false. -->
      <div
        class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.organizations.sso.connection_enabled') }}
            </p>
            <p
              id="domain-connection-enabled-hint"
              class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.sso.connection_enabled_hint') }}
            </p>
          </div>
          <ToggleWithIcon
            data-testid="sso-connection-enabled-toggle"
            :enabled="formState.enabled"
            :disabled="isSaving"
            @update:enabled="handleConnectionEnabledChange" />
        </div>

        <!-- Weak test-before-enable warning (#4111): advisory only, never a
             gate. role="alert" so it is announced when it appears; amber is
             the fixed warning hue (#4132) and the text carries the meaning on
             its own (WCAG 1.4.1). -->
        <div
          v-if="showEnableUntestedWarning"
          data-testid="sso-enable-untested-warning"
          role="alert"
          class="mt-3 flex items-start gap-2 rounded-md bg-amber-50 px-3 py-2 dark:bg-amber-900/20">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle"
            class="mt-0.5 size-4 flex-shrink-0 text-amber-600 dark:text-amber-400"
            aria-hidden="true" />
          <p class="text-sm text-amber-700 dark:text-amber-300">
            {{ t('web.organizations.sso.enable_untested_warning') }}
          </p>
        </div>
      </div>

      <!-- Grant Org Scope Toggle (withheld pending testing unless already
           granted, so an existing grant stays revocable — see showGrantOrgScope) -->
      <div
        v-if="showGrantOrgScope"
        class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
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

      <!-- Action Buttons -->
      <div
        v-if="ssoConfig?.enabled"
        class="space-y-3 border-t border-gray-200 pt-6 dark:border-gray-700">
        <button
          v-if="!showDisableConfirm"
          type="button"
          data-testid="disable-sso"
          :disabled="actionPending"
          class="rounded-md px-3 py-2 text-sm font-semibold text-red-600 ring-1 ring-red-300 disabled:opacity-50 dark:text-red-400"
          @click="showDisableConfirm = true">
          {{ t('web.organizations.sso.disable_action') }}
        </button>
        <div
          v-else
          class="space-y-3">
          <p
            class="text-sm text-gray-600 dark:text-gray-400"
            data-testid="disable-sso-confirmation">
            {{ t('web.organizations.sso.disable_confirm') }}
            <span v-if="ssoConfig.enforce_sso_only">{{
              t('web.organizations.sso.disable_enforcement_warning')
            }}</span>
          </p>
          <button
            type="button"
            data-testid="confirm-disable-sso"
            :disabled="actionPending"
            class="rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
            @click="handleDisable">
            {{ t('web.organizations.sso.disable_action') }}
          </button>
          <button
            type="button"
            :disabled="actionPending"
            class="px-3 py-2 text-sm text-gray-700 dark:text-gray-200"
            @click="showDisableConfirm = false">
            {{ t('web.COMMON.word_cancel') }}
          </button>
        </div>
      </div>

      <div class="flex items-center justify-between border-t border-gray-200 pt-6 dark:border-gray-700">
        <!-- Left: Delete + Discard -->
        <div class="flex items-center gap-3">
          <!-- Delete button (only when editing existing config) -->
          <template v-if="isEditing && !showDeleteConfirm">
            <button
              type="button"
              @click="showDeleteConfirm = true"
              :disabled="isDeleting || isSaving"
              class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-red-600 shadow-sm ring-1 ring-inset ring-red-300 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-red-400 dark:ring-red-700 dark:hover:bg-red-900/20">
              <OIcon
                collection="heroicons"
                name="trash"
                class="size-4"
                aria-hidden="true" />
              {{ t('web.organizations.sso.delete_config') }}
            </button>
          </template>

          <!-- Delete confirmation -->
          <div v-if="showDeleteConfirm" class="flex items-center gap-2">
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

          <!-- Discard changes button -->
          <button
            v-if="hasUnsavedChanges && !showDeleteConfirm"
            type="button"
            @click="emit('discard')"
            :disabled="isSaving"
            class="inline-flex items-center gap-2 rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
            {{ t('web.domains.email.discard_changes') }}
          </button>
        </div>

        <!-- Right: Save button -->
        <button
          type="submit"
          :disabled="!isFormValid || isSaving || isDeleting"
          class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
          <OIcon
            v-if="isSaving"
            collection="heroicons"
            name="arrow-path"
            class="size-4 animate-spin motion-reduce:animate-none"
            aria-hidden="true" />
          <span v-if="isSaving">{{ t('web.COMMON.saving') }}</span>
          <span v-else>{{ isEditing ? t('web.COMMON.save_changes') : t('web.organizations.sso.save_config') }}</span>
        </button>
      </div>
    </form>
  </div>
</template>
