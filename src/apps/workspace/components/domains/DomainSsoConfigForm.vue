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
import {
  SSO_PROVIDER_METADATA,
  type CustomDomainSsoConfig,
  type SsoProviderType,
} from '@/schemas/shapes/sso-config';
import type { SsoConfigFormState } from '@/shared/composables/useSsoConfig';
import type { TestSsoConnectionResponse } from '@/services/sso.service';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

const props = defineProps<{
  domainExtId: string;
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
  (e: 'delete'): void;
  (e: 'test'): void;
  (e: 'discard'): void;
  (e: 'update:formState', value: SsoConfigFormState): void;
}>();

const { t } = useI18n();

// ---------------------------------------------------------------------------
// Provider options
// ---------------------------------------------------------------------------

const providerOptions: { value: SsoProviderType; label: string; description: string }[] = [
  {
    value: 'entra_id',
    label: 'Microsoft Entra ID',
    description: 'Azure Active Directory / Microsoft 365',
  },
  {
    value: 'google',
    label: 'Google Workspace',
    description: 'Google OAuth for Workspace domains',
  },
  {
    value: 'github',
    label: 'GitHub',
    description: 'GitHub OAuth for organizations',
  },
  {
    value: 'oidc',
    label: 'Generic OIDC',
    description: 'Any OpenID Connect provider',
  },
];

// ---------------------------------------------------------------------------
// Local UI state
// ---------------------------------------------------------------------------

const showDeleteConfirm = ref(false);
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

const requiresTenantId = computed(() => props.formState.provider_type === 'entra_id');

const requiresIssuer = computed(() => props.formState.provider_type === 'oidc');

const showDomainFilter = computed(() => {
  const metadata = SSO_PROVIDER_METADATA[props.formState.provider_type];
  return metadata?.requiresDomainFilter ?? false;
});

const currentProviderOption = computed(() =>
  providerOptions.find((o) => o.value === props.formState.provider_type)
);

const isFormValid = computed(() => {
  if (!props.formState.display_name.trim()) return false;
  if (!props.formState.client_id.trim()) return false;

  // client_secret required for new configs
  if (!isEditing.value && !props.formState.client_secret?.trim()) return false;

  // Provider-specific requirements
  if (requiresTenantId.value && !props.formState.tenant_id?.trim()) return false;
  if (requiresIssuer.value && !props.formState.issuer?.trim()) return false;

  return true;
});

const clientSecretPlaceholder = computed(() => {
  if (isEditing.value && props.clientSecretMasked) {
    return props.clientSecretMasked;
  }
  return t('web.organizations.sso.client_secret_placeholder');
});

const canTestConnection = computed(() => {
  if (!props.formState.client_id.trim()) return false;

  // Provider-specific requirements for testing
  if (requiresTenantId.value && !props.formState.tenant_id?.trim()) return false;
  if (requiresIssuer.value && !props.formState.issuer?.trim()) return false;

  return true;
});

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

const handleSave = () => {
  if (!isFormValid.value || props.isSaving) return;
  emit('save');
};

const handleDelete = () => {
  if (props.isDeleting) return;
  emit('delete');
  showDeleteConfirm.value = false;
};

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
    <div v-if="isLoading" class="flex items-center justify-center py-12">
      <OIcon
        collection="heroicons"
        name="arrow-path"
        class="size-8 animate-spin text-gray-400"
        aria-hidden="true" />
      <span class="sr-only">{{ t('web.COMMON.loading') }}</span>
    </div>

    <!-- Form -->
    <form v-else
@submit.prevent="handleSave"
class="space-y-6">
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

      <!-- Client ID -->
      <div>
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
          class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
      </div>

      <!-- Client Secret -->
      <div>
        <label
          for="domain-sso-client-secret"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.organizations.sso.client_secret') }}
          <span v-if="!isEditing"
class="text-red-500"
aria-hidden="true">*</span>
        </label>
        <p
          v-if="isEditing"
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
            :required="!isEditing"
            autocomplete="new-password"
            :placeholder="clientSecretPlaceholder"
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
      </div>

      <!-- Test Connection -->
      <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <h4 class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.organizations.sso.test_connection') }}
            </h4>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.sso.test_connection_hint') }}
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
              class="animate-spin"
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
                    <div v-if="testResult.details.description" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.COMMON.details') }}:</dt>
                      <dd>{{ testResult.details.description }}</dd>
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

      <!-- Enabled Toggle -->
      <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <div>
          <label
            for="domain-sso-enabled"
            class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.organizations.sso.enabled') }}
          </label>
          <p
            id="domain-enabled-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.organizations.sso.enabled_hint') }}
          </p>
        </div>
        <button
          type="button"
          role="switch"
          :aria-checked="formState.enabled"
          aria-describedby="domain-enabled-hint"
          @click="updateField('enabled', !formState.enabled)"
          :class="[
            'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800',
            formState.enabled ? 'bg-brand-600' : 'bg-gray-200 dark:bg-gray-600',
          ]">
          <span class="sr-only">{{ t('web.organizations.sso.enabled') }}</span>
          <span
            :class="[
              'pointer-events-none relative inline-block size-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out',
              formState.enabled ? 'translate-x-5' : 'translate-x-0',
            ]">
            <span
              :class="[
                'absolute inset-0 flex h-full w-full items-center justify-center transition-opacity',
                formState.enabled ? 'opacity-0 duration-100 ease-out' : 'opacity-100 duration-200 ease-in',
              ]"
              aria-hidden="true">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-3 text-gray-400" />
            </span>
            <span
              :class="[
                'absolute inset-0 flex h-full w-full items-center justify-center transition-opacity',
                formState.enabled ? 'opacity-100 duration-200 ease-in' : 'opacity-0 duration-100 ease-out',
              ]"
              aria-hidden="true">
              <OIcon
                collection="heroicons"
                name="check"
                class="size-3 text-brand-600" />
            </span>
          </span>
        </button>
      </div>

      <!-- Action Buttons -->
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
            class="size-4 animate-spin"
            aria-hidden="true" />
          <span v-if="isSaving">{{ t('web.COMMON.saving') }}</span>
          <span v-else>{{ isEditing ? t('web.COMMON.save_changes') : t('web.organizations.sso.save_config') }}</span>
        </button>
      </div>
    </form>
  </div>
</template>
