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
import ToggleWithIcon from '@/shared/components/common/ToggleWithIcon.vue';
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
  ssoConfigured: boolean;
  canManageSso: boolean;
  /** Field currently auto-saving, for per-toggle loading feedback. */
  savingField: keyof SigninConfigFormState | null;
}>();

// ---------------------------------------------------------------------------
// Emits
// ---------------------------------------------------------------------------

const emit = defineEmits<{
  (e: 'save'): void;
  (e: 'delete'): void;
  (e: 'discard'): void;
  (e: 'configure-sso'): void;
  (e: 'update:formState', value: SigninConfigFormState): void;
  (
    e: 'auto-save',
    field: keyof SigninConfigFormState,
    value: SigninConfigFormState[keyof SigninConfigFormState]
  ): void;
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

        <!-- Email Auth -->
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
          <ToggleWithIcon
            :enabled="Boolean(formState.email_auth_enabled)"
            :disabled="isSaving"
            :loading="savingField === 'email_auth_enabled'"
            :on-label="t('web.COMMON.enabled')"
            :off-label="t('web.COMMON.disabled')"
            @update:enabled="emit('auto-save', 'email_auth_enabled', $event)" />
        </div>

        <!-- SSO -->
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
          <div class="flex items-center gap-3">
            <button
              v-if="canManageSso"
              type="button"
              @click="emit('configure-sso')"
              class="inline-flex items-center gap-1.5 rounded-md bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-200 dark:ring-gray-600 dark:hover:bg-gray-600">
              <OIcon
                collection="heroicons"
                name="cog-6-tooth"
                class="size-4"
                aria-hidden="true" />
              {{ ssoConfigured ? t('web.domains.sso.edit_credentials') : t('web.domains.sso.configure_button') }}
            </button>
            <span
              v-else
              class="inline-flex items-center gap-1.5 text-sm text-gray-400 dark:text-gray-500">
              <OIcon
                collection="heroicons"
                name="lock-closed"
                class="size-4"
                aria-hidden="true" />
              {{ t('web.domains.sso.upgrade_required') }}
            </span>
            <ToggleWithIcon
              :enabled="Boolean(formState.sso_enabled)"
              :disabled="isSaving"
              :loading="savingField === 'sso_enabled'"
              @update:enabled="emit('auto-save', 'sso_enabled', $event)" />
          </div>
        </div>
      </fieldset>

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
          :disabled="isSaving || isDeleting || !hasUnsavedChanges"
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
