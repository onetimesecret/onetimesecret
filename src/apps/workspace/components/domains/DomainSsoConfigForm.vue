<!-- src/apps/workspace/components/domains/DomainSsoConfigForm.vue -->

<script setup lang="ts">
/**
 * Domain SSO Configuration Form
 *
 * This component mirrors SsoConfigForm but uses domain-scoped service methods.
 * It provides SSO configuration for individual custom domains.
 */
import { useI18n } from 'vue-i18n';
import { computed, onMounted, ref, watch } from 'vue';
import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { classifyError } from '@/schemas/errors';
import { SsoService, type TestSsoConnectionResponse } from '@/services/sso.service';
import {
  SSO_PROVIDER_METADATA,
  type OrgSsoConfig,
  type SsoProviderType,
} from '@/schemas/shapes/sso-config';
import type { PatchSsoConfigRequest } from '@/schemas/api/organizations/requests/sso-config';

/**
 * Internal form state type.
 * Required fields are non-optional for form validation; client_secret is optional
 * (omit to preserve existing when editing).
 */
interface SsoConfigFormData {
  provider_type: SsoProviderType;
  display_name: string;
  client_id: string;
  client_secret?: string;
  tenant_id?: string;
  issuer?: string;
  allowed_domains: string[];
  enabled: boolean;
}

const props = defineProps<{
  domainExtId: string;
}>();

const emit = defineEmits<{
  (e: 'saved'): void;
  (e: 'deleted'): void;
}>();

const { t } = useI18n();

// Provider options with display info
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

// Form state
const isLoading = ref(true);
const isSaving = ref(false);
const isDeleting = ref(false);
const isTesting = ref(false);
const showDeleteConfirm = ref(false);
const error = ref('');
const success = ref('');
const fieldErrors = ref<Record<string, string>>({});

// Connection test state
const testResult = ref<TestSsoConnectionResponse | null>(null);
const testError = ref('');

// Existing config (null if no config exists)
const existingConfig = ref<OrgSsoConfig | null>(null);

// Form data - internal state with required fields; saveConfig auto-selects PUT/PATCH
const formData = ref<SsoConfigFormData>({
  provider_type: 'entra_id',
  display_name: '',
  client_id: '',
  client_secret: undefined,
  tenant_id: undefined,
  issuer: undefined,
  allowed_domains: [],
  enabled: false,
});

// Show/hide password
const showClientSecret = ref(false);

// Domain input for adding new domains
const newDomain = ref('');
const domainInputError = ref('');

// Computed: whether we're editing existing config
const isEditing = computed(() => existingConfig.value !== null);

// Computed: whether provider requires tenant_id
const requiresTenantId = computed(() => formData.value.provider_type === 'entra_id');

// Computed: whether provider requires issuer
const requiresIssuer = computed(() => formData.value.provider_type === 'oidc');

// Computed: whether to show domain filter field
// Only shown for providers without IdP-side user assignment (e.g., GitHub)
const showDomainFilter = computed(() => {
  const metadata = SSO_PROVIDER_METADATA[formData.value.provider_type];
  return metadata?.requiresDomainFilter ?? false;
});

// Computed: form is valid
const isFormValid = computed(() => {
  if (!formData.value.display_name.trim()) return false;
  if (!formData.value.client_id.trim()) return false;

  // client_secret required for new configs
  if (!isEditing.value && !formData.value.client_secret?.trim()) return false;

  // Provider-specific requirements
  if (requiresTenantId.value && !formData.value.tenant_id?.trim()) return false;
  if (requiresIssuer.value && !formData.value.issuer?.trim()) return false;

  return true;
});

// Computed: client secret placeholder text
const clientSecretPlaceholder = computed(() => {
  if (isEditing.value && existingConfig.value?.client_secret_masked) {
    return existingConfig.value.client_secret_masked;
  }
  return t('web.organizations.sso.client_secret_placeholder');
});

// Computed: can test connection (has required fields for testing)
const canTestConnection = computed(() => {
  if (!formData.value.client_id.trim()) return false;

  // Provider-specific requirements for testing
  if (requiresTenantId.value && !formData.value.tenant_id?.trim()) return false;
  if (requiresIssuer.value && !formData.value.issuer?.trim()) return false;

  return true;
});

// Test connection
const handleTestConnection = async () => {
  if (!canTestConnection.value || isTesting.value) return;

  isTesting.value = true;
  testResult.value = null;
  testError.value = '';
  error.value = '';
  success.value = '';

  try {
    const payload = {
      provider_type: formData.value.provider_type,
      client_id: formData.value.client_id.trim(),
      tenant_id: requiresTenantId.value ? formData.value.tenant_id?.trim() : undefined,
      issuer: requiresIssuer.value ? formData.value.issuer?.trim() : undefined,
    };

    testResult.value = await SsoService.testConnectionForDomain(props.domainExtId, payload);

    if (testResult.value.success) {
      success.value = testResult.value.message;
    } else {
      testError.value = testResult.value.message;
    }
  } catch (err) {
    const classified = classifyError(err);
    testError.value = classified.message || t('web.organizations.sso.test_error');
    console.error('[DomainSsoConfigForm] Error testing connection:', err);
  } finally {
    isTesting.value = false;
  }
};

// Clear test result when form data changes
watch(
  () => [formData.value.provider_type, formData.value.client_id, formData.value.tenant_id, formData.value.issuer],
  () => {
    testResult.value = null;
    testError.value = '';
  }
);

// Load existing config
const loadConfig = async () => {
  isLoading.value = true;
  error.value = '';

  try {
    const response = await SsoService.getConfigForDomain(props.domainExtId);
    existingConfig.value = response.record;

    if (response.record) {
      // Populate form with existing data
      formData.value = {
        provider_type: response.record.provider_type,
        display_name: response.record.display_name,
        client_id: response.record.client_id,
        client_secret: undefined, // Never populate secret from response
        tenant_id: response.record.tenant_id ?? undefined,
        issuer: response.record.issuer ?? undefined,
        allowed_domains: response.record.allowed_domains ?? [],
        enabled: response.record.enabled,
      };
    }
  } catch (err) {
    // 404 is handled by SsoService.getConfigForDomain (returns { record: null })
    // Any error reaching here is a real failure
    const classified = classifyError(err);
    error.value = classified.message || t('web.organizations.sso.load_error');
    console.error('[DomainSsoConfigForm] Error loading config:', err);
  } finally {
    isLoading.value = false;
  }
};

// Save config
const handleSave = async () => {
  if (!isFormValid.value || isSaving.value) return;

  isSaving.value = true;
  error.value = '';
  success.value = '';
  fieldErrors.value = {};

  try {
    // Prepare payload - only include client_secret if provided
    // saveConfigForDomain auto-selects PUT (with secret) or PATCH (without secret)
    const payload: PatchSsoConfigRequest = {
      provider_type: formData.value.provider_type,
      display_name: formData.value.display_name.trim(),
      client_id: formData.value.client_id.trim(),
      allowed_domains: formData.value.allowed_domains,
      enabled: formData.value.enabled,
    };

    // Only include client_secret if user entered a new one
    if (formData.value.client_secret?.trim()) {
      payload.client_secret = formData.value.client_secret.trim();
    }

    // Provider-specific fields
    if (requiresTenantId.value && formData.value.tenant_id) {
      payload.tenant_id = formData.value.tenant_id.trim();
    }
    if (requiresIssuer.value && formData.value.issuer) {
      payload.issuer = formData.value.issuer.trim();
    }

    const response = await SsoService.saveConfigForDomain(props.domainExtId, payload);
    existingConfig.value = response.record;

    // Clear secret field after successful save
    formData.value.client_secret = undefined;

    success.value = isEditing.value
      ? t('web.organizations.sso.update_success')
      : t('web.organizations.sso.create_success');

    emit('saved');
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.organizations.sso.save_error');
    console.error('[DomainSsoConfigForm] Error saving config:', err);
  } finally {
    isSaving.value = false;
  }
};

// Delete config
const handleDelete = async () => {
  if (isDeleting.value) return;

  isDeleting.value = true;
  error.value = '';
  success.value = '';

  try {
    await SsoService.deleteConfigForDomain(props.domainExtId);
    existingConfig.value = null;

    // Reset form to defaults
    formData.value = {
      provider_type: 'entra_id',
      display_name: '',
      client_id: '',
      client_secret: undefined,
      tenant_id: undefined,
      issuer: undefined,
      allowed_domains: [],
      enabled: false,
    };

    showDeleteConfirm.value = false;
    success.value = t('web.organizations.sso.delete_success');
    emit('deleted');
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.message || t('web.organizations.sso.delete_error');
    console.error('[DomainSsoConfigForm] Error deleting config:', err);
  } finally {
    isDeleting.value = false;
  }
};

// Add domain to allowlist
const addDomain = () => {
  const domain = newDomain.value.trim().toLowerCase();

  if (!domain) return;

  // Basic domain validation
  const domainRegex = /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}$/;
  if (!domainRegex.test(domain)) {
    domainInputError.value = t('web.organizations.sso.invalid_domain');
    return;
  }

  // Check for duplicates
  if (formData.value.allowed_domains?.includes(domain)) {
    domainInputError.value = t('web.organizations.sso.domain_exists');
    return;
  }

  formData.value.allowed_domains = [...(formData.value.allowed_domains || []), domain];
  newDomain.value = '';
  domainInputError.value = '';
};

// Remove domain from allowlist
const removeDomain = (domain: string) => {
  formData.value.allowed_domains = formData.value.allowed_domains?.filter((d) => d !== domain) ?? [];
};

// Clear domain input error when typing
watch(newDomain, () => {
  if (domainInputError.value) {
    domainInputError.value = '';
  }
});

// Handle provider change - clear provider-specific fields
watch(() => formData.value.provider_type, (newType, oldType) => {
  if (newType !== oldType) {
    // Clear tenant_id when switching away from entra_id
    if (oldType === 'entra_id') {
      formData.value.tenant_id = undefined;
    }
    // Clear issuer when switching away from oidc
    if (oldType === 'oidc') {
      formData.value.issuer = undefined;
    }
  }
});

onMounted(loadConfig);
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
      <!-- Alerts -->
      <BasicFormAlerts
        v-if="error"
        :error="error" />
      <BasicFormAlerts
        v-if="success"
        :success="success" />

      <!-- Provider Selection -->
      <fieldset>
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.organizations.sso.provider_type') }}
        </legend>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.sso.provider_type_description') }}
        </p>
        <div
          class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2"
          role="radiogroup"
          aria-labelledby="provider-type-legend">
          <label
            v-for="option in providerOptions"
            :key="option.value"
            :class="[
              'relative flex cursor-pointer rounded-lg border p-4 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2',
              formData.provider_type === option.value
                ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                : 'border-gray-300 bg-white hover:border-gray-400 dark:border-gray-600 dark:bg-gray-700 dark:hover:border-gray-500',
            ]">
            <input
              type="radio"
              :id="`domain-provider-${option.value}`"
              :name="'provider_type'"
              :value="option.value"
              v-model="formData.provider_type"
              class="sr-only"
              :aria-describedby="`domain-provider-${option.value}-description`" />
            <span class="flex flex-1 flex-col">
              <span
                :class="[
                  'block text-sm font-medium',
                  formData.provider_type === option.value
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
              v-if="formData.provider_type === option.value"
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
          v-model="formData.display_name"
          type="text"
          required
          maxlength="100"
          :placeholder="t('web.organizations.sso.display_name_placeholder')"
          aria-describedby="domain-display-name-hint"
          :aria-invalid="!!fieldErrors.display_name"
          class="mt-2 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 sm:text-sm" />
        <p
          v-if="fieldErrors.display_name"
          :id="`domain-display-name-error`"
          class="mt-1 text-sm text-red-600 dark:text-red-400"
          role="alert">
          {{ fieldErrors.display_name }}
        </p>
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
          v-model="formData.client_id"
          type="text"
          required
          autocomplete="off"
          :placeholder="t('web.organizations.sso.client_id_placeholder')"
          :aria-invalid="!!fieldErrors.client_id"
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
            v-model="formData.client_secret"
            :type="showClientSecret ? 'text' : 'password'"
            :required="!isEditing"
            autocomplete="new-password"
            :placeholder="clientSecretPlaceholder"
            :aria-describedby="isEditing ? 'domain-client-secret-hint' : undefined"
            :aria-invalid="!!fieldErrors.client_secret"
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
          v-model="formData.tenant_id"
          type="text"
          required
          autocomplete="off"
          :placeholder="t('web.organizations.sso.tenant_id_placeholder')"
          aria-describedby="domain-tenant-id-hint"
          :aria-invalid="!!fieldErrors.tenant_id"
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
          v-model="formData.issuer"
          type="url"
          required
          autocomplete="off"
          :placeholder="t('web.organizations.sso.issuer_placeholder')"
          aria-describedby="domain-issuer-hint"
          :aria-invalid="!!fieldErrors.issuer"
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
                <div
                  v-if="testResult.details"
                  class="mt-2 text-sm text-green-700 dark:text-green-300">
                  <dl class="space-y-1">
                    <div v-if="testResult.details.issuer" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.organizations.sso.issuer') }}:</dt>
                      <dd class="truncate">{{ testResult.details.issuer }}</dd>
                    </div>
                    <div v-if="testResult.details.authorization_endpoint" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.organizations.sso.auth_endpoint') }}:</dt>
                      <dd class="truncate">{{ testResult.details.authorization_endpoint }}</dd>
                    </div>
                    <div v-if="testResult.details.note" class="flex gap-2">
                      <dt class="font-medium">{{ t('web.COMMON.note') }}:</dt>
                      <dd>{{ testResult.details.note }}</dd>
                    </div>
                  </dl>
                </div>
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
          v-if="formData.allowed_domains && formData.allowed_domains.length > 0"
          class="mt-2 flex flex-wrap gap-2"
          role="list"
          :aria-label="t('web.organizations.sso.allowed_domains')">
          <span
            v-for="domain in formData.allowed_domains"
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
          :aria-checked="formData.enabled"
          aria-describedby="domain-enabled-hint"
          @click="formData.enabled = !formData.enabled"
          :class="[
            'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800',
            formData.enabled ? 'bg-brand-600' : 'bg-gray-200 dark:bg-gray-600',
          ]">
          <span class="sr-only">{{ t('web.organizations.sso.enabled') }}</span>
          <span
            :class="[
              'pointer-events-none relative inline-block size-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out',
              formData.enabled ? 'translate-x-5' : 'translate-x-0',
            ]">
            <span
              :class="[
                'absolute inset-0 flex h-full w-full items-center justify-center transition-opacity',
                formData.enabled ? 'opacity-0 duration-100 ease-out' : 'opacity-100 duration-200 ease-in',
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
                formData.enabled ? 'opacity-100 duration-200 ease-in' : 'opacity-0 duration-100 ease-out',
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
        <!-- Delete button (only if editing) -->
        <div>
          <button
            v-if="isEditing && !showDeleteConfirm"
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
        </div>

        <!-- Save button -->
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

    <!-- Live region for status announcements -->
    <div
      aria-live="polite"
      aria-atomic="true"
      class="sr-only">
      <span v-if="success">{{ success }}</span>
      <span v-if="error">{{ error }}</span>
    </div>
  </div>
</template>
