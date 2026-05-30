<!-- src/apps/workspace/components/domains/DomainSignupConfigForm.vue -->

<script setup lang="ts">
/**
 * Domain Signup Validation Configuration Form
 *
 * Presentational component that receives signup config state via props
 * and emits events for actions. Parent (DomainSignup.vue) manages state
 * via useSignupConfig composable.
 */
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import {
  SIGNUP_STRATEGY_METADATA,
  type CustomDomainSignupConfig,
  type SignupValidationStrategy,
} from '@/schemas/shapes/domains/signup-config';
import type { SignupConfigFormState } from '@/shared/composables/useSignupConfig';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

const props = defineProps<{
  domainExtId: string;
  formState: SignupConfigFormState;
  signupConfig: CustomDomainSignupConfig | null;
  isLoading: boolean;
  isSaving: boolean;
  isDeleting: boolean;
  hasUnsavedChanges: boolean;
  isConfigured: boolean;
}>();

// ---------------------------------------------------------------------------
// Emits
// ---------------------------------------------------------------------------

const emit = defineEmits<{
  (e: 'save'): void;
  (e: 'delete'): void;
  (e: 'discard'): void;
  (e: 'update:formState', value: SignupConfigFormState): void;
}>();

const { t } = useI18n();

// ---------------------------------------------------------------------------
// Strategy options
// ---------------------------------------------------------------------------

const strategyOptions: { value: SignupValidationStrategy; label: string; description: string }[] = [
  {
    value: 'passthrough',
    label: 'Passthrough',
    description: SIGNUP_STRATEGY_METADATA.passthrough.description,
  },
  {
    value: 'domain_allowlist',
    label: 'Domain allowlist',
    description: SIGNUP_STRATEGY_METADATA.domain_allowlist.description,
  },
  {
    value: 'mx',
    label: 'MX lookup',
    description: SIGNUP_STRATEGY_METADATA.mx.description,
  },
  {
    value: 'smtp',
    label: 'SMTP probe',
    description: SIGNUP_STRATEGY_METADATA.smtp.description,
  },
];

// ---------------------------------------------------------------------------
// Local UI state
// ---------------------------------------------------------------------------

const showDeleteConfirm = ref(false);
const newDomain = ref('');
const domainInputError = ref('');

// ---------------------------------------------------------------------------
// Form state helpers (emit updates to parent)
// ---------------------------------------------------------------------------

function updateField<K extends keyof SignupConfigFormState>(
  field: K,
  value: SignupConfigFormState[K]
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

const requiresAllowlist = computed(
  () => SIGNUP_STRATEGY_METADATA[props.formState.validation_strategy]?.requiresAllowlist ?? false
);

const performsNetworkValidation = computed(
  () => SIGNUP_STRATEGY_METADATA[props.formState.validation_strategy]?.networkValidation ?? false
);

const isFormValid = computed(() => {
  if (requiresAllowlist.value && props.formState.allowed_signup_domains.length === 0) {
    return false;
  }
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

const addDomain = () => {
  const domain = newDomain.value.trim().toLowerCase();

  if (!domain) return;

  // Basic frontend validation for UX (backend does authoritative PublicSuffix check)
  if (!domain.includes('.') || /\s/.test(domain)) {
    domainInputError.value = t('web.domains.signup.invalid_domain');
    return;
  }

  if (props.formState.allowed_signup_domains?.includes(domain)) {
    domainInputError.value = t('web.domains.signup.domain_exists');
    return;
  }

  updateField('allowed_signup_domains', [
    ...(props.formState.allowed_signup_domains || []),
    domain,
  ]);
  newDomain.value = '';
  domainInputError.value = '';
};

const removeDomain = (domain: string) => {
  updateField(
    'allowed_signup_domains',
    props.formState.allowed_signup_domains?.filter((d) => d !== domain) ?? []
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
      <!-- Strategy Selection -->
      <fieldset>
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.signup.strategy_label') }}
        </legend>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.signup.strategy_description') }}
        </p>

        <div
          class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2"
          role="radiogroup"
          aria-labelledby="signup-strategy-legend">
          <label
            v-for="option in strategyOptions"
            :key="option.value"
            :class="[
              'relative flex cursor-pointer rounded-lg border p-4 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2',
              formState.validation_strategy === option.value
                ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                : 'border-gray-300 bg-white hover:border-gray-400 dark:border-gray-600 dark:bg-gray-700 dark:hover:border-gray-500',
            ]">
            <input
              type="radio"
              :id="`signup-strategy-${option.value}`"
              :name="'validation_strategy'"
              :value="option.value"
              :checked="formState.validation_strategy === option.value"
              @change="updateField('validation_strategy', option.value)"
              class="sr-only"
              :aria-describedby="`signup-strategy-${option.value}-description`" />
            <span class="flex flex-1 flex-col">
              <span
                :class="[
                  'block text-sm font-medium',
                  formState.validation_strategy === option.value
                    ? 'text-brand-900 dark:text-brand-100'
                    : 'text-gray-900 dark:text-white',
                ]">
                {{ option.label }}
              </span>
              <span
                :id="`signup-strategy-${option.value}-description`"
                class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ option.description }}
              </span>
            </span>
            <OIcon
              v-if="formState.validation_strategy === option.value"
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </label>
        </div>
      </fieldset>

      <!-- Network validation warning -->
      <div
        v-if="performsNetworkValidation"
        role="status"
        aria-live="polite"
        class="flex items-start gap-3 rounded-md bg-yellow-50 px-4 py-3 dark:bg-yellow-900/20">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-5 flex-shrink-0 text-yellow-500 dark:text-yellow-400"
          aria-hidden="true" />
        <p class="flex-1 text-sm text-yellow-700 dark:text-yellow-300">
          {{ t('web.domains.signup.network_validation_warning') }}
        </p>
      </div>

      <!-- Allowed Domains (only when strategy requires it) -->
      <div v-if="requiresAllowlist">
        <label
          for="signup-domain-input"
          class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.domains.signup.allowed_domains_label') }}
          <span class="text-red-500" aria-hidden="true">*</span>
        </label>
        <p
          id="signup-allowed-domains-hint"
          class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.signup.allowed_domains_hint') }}
        </p>

        <!-- Domain chips -->
        <div
          v-if="formState.allowed_signup_domains && formState.allowed_signup_domains.length > 0"
          class="mt-2 flex flex-wrap gap-2"
          role="list"
          :aria-label="t('web.domains.signup.allowed_domains_label')">
          <span
            v-for="domain in formState.allowed_signup_domains"
            :key="domain"
            role="listitem"
            class="inline-flex items-center gap-1 rounded-full bg-gray-100 px-3 py-1 text-sm text-gray-700 dark:bg-gray-600 dark:text-gray-200">
            {{ domain }}
            <button
              type="button"
              @click="removeDomain(domain)"
              class="ml-1 rounded-full p-0.5 text-gray-400 hover:bg-gray-200 hover:text-gray-600 dark:hover:bg-gray-500 dark:hover:text-gray-100"
              :aria-label="t('web.domains.signup.remove_domain', { domain })">
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
              id="signup-domain-input"
              v-model="newDomain"
              type="text"
              :placeholder="t('web.domains.signup.domain_placeholder')"
              aria-describedby="signup-allowed-domains-hint signup-domain-input-error"
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
          id="signup-domain-input-error"
          class="mt-1 text-sm text-red-600 dark:text-red-400"
          role="alert">
          {{ domainInputError }}
        </p>
      </div>

      <!-- Enabled Toggle -->
      <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <div>
          <label
            for="signup-enabled"
            class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.domains.signup.enabled_label') }}
          </label>
          <p
            id="signup-enabled-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.domains.signup.enabled_hint') }}
          </p>
        </div>
        <button
          id="signup-enabled"
          type="button"
          role="switch"
          :aria-checked="formState.enabled"
          aria-describedby="signup-enabled-hint"
          @click="updateField('enabled', !formState.enabled)"
          :class="[
            'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800',
            formState.enabled ? 'bg-brand-600' : 'bg-gray-200 dark:bg-gray-600',
          ]">
          <span class="sr-only">{{ t('web.domains.signup.enabled_label') }}</span>
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
              {{ t('web.domains.signup.delete_config') }}
            </button>
          </template>

          <div v-if="showDeleteConfirm" class="flex items-center gap-2">
            <span class="text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.domains.signup.delete_confirm') }}
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
          <span v-else>{{ isEditing ? t('web.COMMON.save_changes') : t('web.domains.signup.save_config') }}</span>
        </button>
      </div>
    </form>
  </div>
</template>
