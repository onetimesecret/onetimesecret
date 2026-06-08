// src/shared/composables/useSigninConfig.ts

/**
 * Composable for managing per-domain sign-in configuration.
 *
 * Follows the useSignupConfig lifecycle pattern:
 * - initialize: fetch current config (404 = unconfigured, not error)
 * - saveConfig: PUT full replacement
 * - deleteConfig: removes config (falls back to global signin policy)
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * NOTE: Backend persistence (Ruby model + API endpoints) is not yet
 * implemented. This composable is wired to a SigninConfigService that
 * will need corresponding backend routes.
 *
 * @param domainExtId - Domain external ID for API calls
 */

import type { ApplicationError } from '@/schemas/errors';
import type {
  CustomDomainSigninConfig,
  SigninRestrictTo,
} from '@/schemas/shapes/domains/signin-config';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Form state for signin configuration.
 */
export interface SigninConfigFormState {
  enabled: boolean;
  signin_enabled: boolean | null;
  restrict_to: SigninRestrictTo | null;
  email_auth_enabled: boolean | null;
  sso_enabled: boolean | null;
}

function createDefaultFormState(): SigninConfigFormState {
  return {
    enabled: false,
    signin_enabled: null,
    restrict_to: null,
    email_auth_enabled: null,
    sso_enabled: null,
  };
}

function _configToFormState(config: CustomDomainSigninConfig): SigninConfigFormState {
  return {
    enabled: config.enabled,
    signin_enabled: config.signin_enabled ?? null,
    restrict_to: config.restrict_to ?? null,
    email_auth_enabled: config.email_auth_enabled ?? null,
    sso_enabled: config.sso_enabled ?? null,
  };
}

/* eslint max-lines-per-function: off */
export function useSigninConfig(_domainExtId: string) {
  const { t: _t } = useI18n();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  const isLoading = ref(false);
  const isInitialized = ref(false);
  const isSaving = ref(false);
  const isDeleting = ref(false);
  const error = ref<ApplicationError | null>(null);

  /** The full config object from the API. Null = unconfigured (404). */
  const signinConfig = ref<CustomDomainSigninConfig | null>(null);

  /** Current form state (editable). */
  const formState = ref<SigninConfigFormState>(createDefaultFormState());

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<SigninConfigFormState | null>(null);

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /** Whether a signin config exists for this domain. */
  const isConfigured = computed(() => signinConfig.value !== null);

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    const current = formState.value;
    const saved = savedFormState.value;
    return (
      current.enabled !== saved.enabled ||
      current.signin_enabled !== saved.signin_enabled ||
      current.restrict_to !== saved.restrict_to ||
      current.email_auth_enabled !== saved.email_auth_enabled ||
      current.sso_enabled !== saved.sso_enabled
    );
  });

  // ---------------------------------------------------------------------------
  // Actions (stubbed — backend API not yet implemented)
  // ---------------------------------------------------------------------------

  const initialize = async () => {
    isLoading.value = true;
    try {
      // TODO: Replace with SigninConfigService.getConfigForDomain(domainExtId)
      // For now, start unconfigured (equivalent to a 404 response)
      signinConfig.value = null;
      formState.value = createDefaultFormState();
      savedFormState.value = { ...formState.value };
      isInitialized.value = true;
    } finally {
      isLoading.value = false;
    }
  };

  const saveConfig = async () => {
    isSaving.value = true;
    error.value = null;

    try {
      // TODO: Replace with SigninConfigService.putConfigForDomain(domainExtId, payload)
      // For now, treat formState as the saved state
      savedFormState.value = { ...formState.value };
    } finally {
      isSaving.value = false;
    }
  };

  const deleteConfig = async () => {
    isDeleting.value = true;
    error.value = null;

    try {
      // TODO: Replace with SigninConfigService.deleteConfigForDomain(domainExtId)
      signinConfig.value = null;
      formState.value = createDefaultFormState();
      savedFormState.value = { ...formState.value };
    } finally {
      isDeleting.value = false;
    }
  };

  const discardChanges = () => {
    if (savedFormState.value) {
      formState.value = { ...savedFormState.value };
    }
  };

  return {
    // State
    isLoading,
    isInitialized,
    isSaving,
    isDeleting,
    error,
    signinConfig,
    formState,

    // Computed
    isConfigured,
    hasUnsavedChanges,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    discardChanges,
  };
}
