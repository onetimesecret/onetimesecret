<!-- src/apps/workspace/components/domains/DomainSigninConfigForm.vue -->

<script setup lang="ts">
/**
 * Domain Sign-In Configuration Form
 *
 * Presentational component for per-domain signin overrides.
 * Controls: signin enabled, restrict_to (single auth method),
 * email_auth and SSO domain-level toggles.
 */
import { useI18n } from 'vue-i18n';
import { computed, ref } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import SettingsSkeleton from '@/shared/components/closet/SettingsSkeleton.vue';
import {
  SIGNIN_RESTRICT_TO_METADATA,
  type SigninRestrictTo,
} from '@/schemas/shapes/domains/signin-config';
import type { SigninConfigFormState } from '@/shared/composables/useSigninConfig';

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

const props = defineProps<{
  domainExtId: string;
  formState: SigninConfigFormState;
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
  (e: 'update:formState', value: SigninConfigFormState): void;
}>();

const { t } = useI18n();

// ---------------------------------------------------------------------------
// Restrict-to options
// ---------------------------------------------------------------------------

const restrictToOptions: { value: SigninRestrictTo; label: string; description: string }[] = [
  {
    value: 'password',
    label: t('web.domains.signin.method_password'),
    description: SIGNIN_RESTRICT_TO_METADATA.password.description,
  },
  {
    value: 'email_auth',
    label: t('web.domains.signin.method_email_auth'),
    description: SIGNIN_RESTRICT_TO_METADATA.email_auth.description,
  },
  {
    value: 'webauthn',
    label: t('web.domains.signin.method_webauthn'),
    description: SIGNIN_RESTRICT_TO_METADATA.webauthn.description,
  },
  {
    value: 'sso',
    label: t('web.domains.signin.method_sso'),
    description: SIGNIN_RESTRICT_TO_METADATA.sso.description,
  },
];

// ---------------------------------------------------------------------------
// Local UI state
// ---------------------------------------------------------------------------

const showDeleteConfirm = ref(false);

// ---------------------------------------------------------------------------
// Form state helpers (emit updates to parent)
// ---------------------------------------------------------------------------

function updateField<K extends keyof SigninConfigFormState>(
  field: K,
  value: SigninConfigFormState[K]
): void {
  emit('update:formState', {
    ...props.formState,
    [field]: value,
  });
}

// ---------------------------------------------------------------------------
// Computed
// ---------------------------------------------------------------------------

const isEditing = computed(() => props.isConfigured);

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

const handleSave = () => {
  if (props.isSaving) return;
  emit('save');
};

const handleDelete = () => {
  if (props.isDeleting) return;
  emit('delete');
  showDeleteConfirm.value = false;
};
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
      <!-- Signin Enabled (domain override) -->
      <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <div>
          <label
            for="signin-domain-enabled"
            class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.domains.signin.signin_enabled_label') }}
          </label>
          <p
            id="signin-domain-enabled-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.domains.signin.signin_enabled_hint') }}
          </p>
        </div>
        <select
          id="signin-domain-enabled"
          aria-describedby="signin-domain-enabled-hint"
          :value="formState.signin_enabled === null ? 'inherit' : String(formState.signin_enabled)"
          @change="updateField('signin_enabled', ($event.target as HTMLSelectElement).value === 'inherit' ? null : ($event.target as HTMLSelectElement).value === 'true')"
          class="rounded-md border-gray-300 text-sm shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
          <option value="inherit">{{ t('web.domains.signin.inherit_global') }}</option>
          <option value="true">{{ t('web.COMMON.enabled') }}</option>
          <option value="false">{{ t('web.COMMON.disabled') }}</option>
        </select>
      </div>

      <!-- Restrict to single auth method -->
      <fieldset>
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.signin.restrict_to_label') }}
        </legend>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.signin.restrict_to_hint') }}
        </p>

        <div
          class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2"
          role="radiogroup"
          aria-labelledby="signin-restrict-legend">
          <!-- "Show all" option -->
          <label
            :class="[
              'relative flex cursor-pointer rounded-lg border p-4 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2',
              formState.restrict_to === null
                ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                : 'border-gray-300 bg-white hover:border-gray-400 dark:border-gray-600 dark:bg-gray-700 dark:hover:border-gray-500',
            ]">
            <input
              type="radio"
              id="signin-restrict-none"
              name="restrict_to"
              :value="'none'"
              :checked="formState.restrict_to === null"
              @change="updateField('restrict_to', null)"
              class="sr-only" />
            <span class="flex flex-1 flex-col">
              <span
                :class="[
                  'block text-sm font-medium',
                  formState.restrict_to === null
                    ? 'text-brand-900 dark:text-brand-100'
                    : 'text-gray-900 dark:text-white',
                ]">
                {{ t('web.domains.signin.all_methods') }}
              </span>
              <span class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.domains.signin.all_methods_description') }}
              </span>
            </span>
            <OIcon
              v-if="formState.restrict_to === null"
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </label>

          <!-- Per-method options -->
          <label
            v-for="option in restrictToOptions"
            :key="option.value"
            :class="[
              'relative flex cursor-pointer rounded-lg border p-4 focus-within:ring-2 focus-within:ring-brand-500 focus-within:ring-offset-2',
              formState.restrict_to === option.value
                ? 'border-brand-500 bg-brand-50 dark:border-brand-400 dark:bg-brand-900/20'
                : 'border-gray-300 bg-white hover:border-gray-400 dark:border-gray-600 dark:bg-gray-700 dark:hover:border-gray-500',
            ]">
            <input
              type="radio"
              :id="`signin-restrict-${option.value}`"
              name="restrict_to"
              :value="option.value"
              :checked="formState.restrict_to === option.value"
              @change="updateField('restrict_to', option.value)"
              class="sr-only"
              :aria-describedby="`signin-restrict-${option.value}-description`" />
            <span class="flex flex-1 flex-col">
              <span
                :class="[
                  'block text-sm font-medium',
                  formState.restrict_to === option.value
                    ? 'text-brand-900 dark:text-brand-100'
                    : 'text-gray-900 dark:text-white',
                ]">
                {{ option.label }}
              </span>
              <span
                :id="`signin-restrict-${option.value}-description`"
                class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ option.description }}
              </span>
            </span>
            <OIcon
              v-if="formState.restrict_to === option.value"
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-brand-600 dark:text-brand-400"
              aria-hidden="true" />
          </label>
        </div>
      </fieldset>

      <!-- Auth method domain overrides -->
      <fieldset class="space-y-4">
        <legend class="text-sm font-medium text-gray-900 dark:text-white">
          {{ t('web.domains.signin.method_overrides_label') }}
        </legend>
        <p class="text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.domains.signin.method_overrides_hint') }}
        </p>

        <!-- Email Auth override -->
        <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
          <div>
            <label
              for="signin-email-auth"
              class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.domains.signin.email_auth_label') }}
            </label>
            <p
              id="signin-email-auth-hint"
              class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.domains.signin.email_auth_hint') }}
            </p>
          </div>
          <select
            id="signin-email-auth"
            aria-describedby="signin-email-auth-hint"
            :value="formState.email_auth_enabled === null ? 'inherit' : String(formState.email_auth_enabled)"
            @change="updateField('email_auth_enabled', ($event.target as HTMLSelectElement).value === 'inherit' ? null : ($event.target as HTMLSelectElement).value === 'true')"
            class="rounded-md border-gray-300 text-sm shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
            <option value="inherit">{{ t('web.domains.signin.inherit_global') }}</option>
            <option value="true">{{ t('web.COMMON.enabled') }}</option>
            <option value="false">{{ t('web.COMMON.disabled') }}</option>
          </select>
        </div>

        <!-- SSO override -->
        <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
          <div>
            <label
              for="signin-sso"
              class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.domains.signin.sso_enabled_label') }}
            </label>
            <p
              id="signin-sso-hint"
              class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.domains.signin.sso_enabled_hint') }}
            </p>
          </div>
          <select
            id="signin-sso"
            aria-describedby="signin-sso-hint"
            :value="formState.sso_enabled === null ? 'inherit' : String(formState.sso_enabled)"
            @change="updateField('sso_enabled', ($event.target as HTMLSelectElement).value === 'inherit' ? null : ($event.target as HTMLSelectElement).value === 'true')"
            class="rounded-md border-gray-300 text-sm shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white">
            <option value="inherit">{{ t('web.domains.signin.inherit_global') }}</option>
            <option value="true">{{ t('web.COMMON.enabled') }}</option>
            <option value="false">{{ t('web.COMMON.disabled') }}</option>
          </select>
        </div>
      </fieldset>

      <!-- Enabled Toggle (master switch for this per-domain config) -->
      <div class="flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-700/50">
        <div>
          <label
            for="signin-enabled"
            class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.domains.signin.enabled_label') }}
          </label>
          <p
            id="signin-enabled-hint"
            class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.domains.signin.enabled_hint') }}
          </p>
        </div>
        <button
          id="signin-enabled"
          type="button"
          role="switch"
          :aria-checked="formState.enabled"
          aria-describedby="signin-enabled-hint"
          @click="updateField('enabled', !formState.enabled)"
          :class="[
            'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800',
            formState.enabled ? 'bg-brand-600' : 'bg-gray-200 dark:bg-gray-600',
          ]">
          <span class="sr-only">{{ t('web.domains.signin.enabled_label') }}</span>
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
              {{ t('web.domains.signin.delete_config') }}
            </button>
          </template>

          <div v-if="showDeleteConfirm" class="flex items-center gap-2">
            <span class="text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.domains.signin.delete_confirm') }}
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
          :disabled="isSaving || isDeleting"
          class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 font-brand text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
          <OIcon
            v-if="isSaving"
            collection="heroicons"
            name="arrow-path"
            class="size-4 animate-spin motion-reduce:animate-none"
            aria-hidden="true" />
          <span v-if="isSaving">{{ t('web.COMMON.saving') }}</span>
          <span v-else>{{ isEditing ? t('web.COMMON.save_changes') : t('web.domains.signin.save_config') }}</span>
        </button>
      </div>
    </form>
  </div>
</template>
