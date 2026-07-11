// src/shared/composables/useSignupConfig.ts

/**
 * Composable for managing per-domain signup validation configuration.
 *
 * Follows the useSsoConfig lifecycle pattern (minus credential handling):
 * - initialize: fetch current config (record null = unconfigured, not error)
 * - saveConfig: PUT full replacement
 * - deleteConfig: removes config (falls back to global signup policy)
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * Auth-override semantics (ADR-024, shared with useSigninConfig via
 * useAuthOverrideState):
 * - Unconfigured domains are SEEDED from the inherited global state
 *   (response `details`), so the signup-enabled control shows what actually
 *   runs — there is no separate display path.
 * - Every save materializes an explicit override (`enabled: true` via
 *   asExplicitOverride). Saving pins the domain against future changes to
 *   the workspace defaults; deleteConfig unpins.
 *
 * @param domainExtId - Domain external ID for API calls
 */

import type { PutSignupConfigRequest } from '@/schemas/api/domains/requests/signup-config';
import type { SignupConfigDetails } from '@/schemas/api/domains/responses/signup-config';
import type { ApplicationError } from '@/schemas/errors';
import type {
  CustomDomainSignupConfig,
  SignupValidationStrategy,
} from '@/schemas/shapes/domains/signup-config';
import { SignupConfigService } from '@/services/signup-config.service';
import { useNotificationsStore } from '@/shared/stores';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import { type AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';
import { asExplicitOverride, createAuthOverrideState } from './useAuthOverrideState';

/**
 * Form state for signup configuration.
 */
export interface SignupConfigFormState {
  validation_strategy: SignupValidationStrategy;
  allowed_signup_domains: string[];
  enabled: boolean;
  signup_enabled: boolean;
  autoverify: boolean;
}

/**
 * Seed form state for an unconfigured domain from the inherited global
 * state (ADR-024): the signup-enabled control shows what actually runs, and
 * the first explicit save materializes this snapshot plus the user's edits.
 */
function createSeededFormState(details: SignupConfigDetails | null): SignupConfigFormState {
  return {
    validation_strategy: 'passthrough',
    allowed_signup_domains: [],
    enabled: false,
    signup_enabled: details?.effective_enabled ?? false,
    autoverify: false,
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
 */
function configToFormState(config: CustomDomainSignupConfig): SignupConfigFormState {
  return {
    validation_strategy: config.validation_strategy,
    allowed_signup_domains: config.allowed_signup_domains ?? [],
    enabled: config.enabled,
    signup_enabled: config.signup_enabled ?? false,
    autoverify: config.autoverify ?? false,
  };
}

/* eslint max-lines-per-function: off */
export function useSignupConfig(domainExtId: string) {
  const notifications = useNotificationsStore();
  const { t } = useI18n();
  const router = useRouter();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  const isLoading = ref(true);
  const isInitialized = ref(false);
  const isSaving = ref(false);
  const isDeleting = ref(false);
  const error = ref<ApplicationError | null>(null);

  /** The full config object from the API. Null = unconfigured. */
  const signupConfig = ref<CustomDomainSignupConfig | null>(null);

  /**
   * Resolution details from the last API response (ADR-024): the global
   * capability and the resolver's effective output for this domain. The UI
   * displays these; it never re-derives them from the raw flags.
   */
  const details = ref<SignupConfigDetails | null>(null);

  /** Current form state (editable). */
  const formState = ref<SignupConfigFormState>(createSeededFormState(null));

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<SignupConfigFormState | null>(null);

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

  // A second handler for save/delete actions that should NOT toggle isLoading.
  const { wrap: wrapAction } = useAsyncHandler({
    ...defaultAsyncHandlerOptions,
    setLoading: undefined,
  });

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /** Whether a signup config record exists for this domain. */
  const isConfigured = computed(() => signupConfig.value !== null);

  /** Whether per-domain signup validation is configured AND enabled. */
  const isEnabled = computed(() => signupConfig.value?.enabled ?? false);

  /**
   * Shared auth-override display state (ADR-024): effective/global
   * availability and the workspace-default flag that drives the badge.
   */
  const overrideState = createAuthOverrideState(signupConfig, details);

  /** Whether the form has been modified since last save/load. */
  const hasUnsavedChanges = computed(() => {
    if (!savedFormState.value) return false;
    const current = formState.value;
    const saved = savedFormState.value;
    return (
      current.validation_strategy !== saved.validation_strategy ||
      current.enabled !== saved.enabled ||
      current.signup_enabled !== saved.signup_enabled ||
      current.autoverify !== saved.autoverify ||
      !arraysEqual(current.allowed_signup_domains, saved.allowed_signup_domains)
    );
  });

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  const seedFormState = () => {
    formState.value = createSeededFormState(details.value);
  };

  const snapshotFormState = () => {
    savedFormState.value = {
      ...formState.value,
      allowed_signup_domains: [...formState.value.allowed_signup_domains],
    };
  };

  /**
   * Load the current signup config for this domain.
   * A null record means "unconfigured" — the form is seeded from the
   * inherited global state carried in details, not from static defaults.
   */
  const initialize = () =>
    wrap(async () => {
      const response = await SignupConfigService.getConfigForDomain(domainExtId);
      signupConfig.value = response.record;
      details.value = response.details;

      if (response.record) {
        formState.value = configToFormState(response.record);
      } else {
        seedFormState();
      }
      snapshotFormState();
      isInitialized.value = true;
    });

  /**
   * Save the current form state (PUT — full replacement).
   *
   * Always materializes an explicit override: `enabled: true` is forced here
   * (asExplicitOverride), never at individual call sites (ADR-024).
   */
  const saveConfig = async () => {
    isSaving.value = true;
    error.value = null;

    try {
      const result = await wrapAction(async () => {
        const payload: PutSignupConfigRequest = asExplicitOverride({
          validation_strategy: formState.value.validation_strategy,
          signup_enabled: formState.value.signup_enabled,
          autoverify: formState.value.autoverify,
        });

        // Only include allowed_signup_domains when the strategy actually
        // uses it. Backend treats the omitted field as an empty list under
        // PUT semantics, so switching away from domain_allowlist clears it.
        if (formState.value.validation_strategy === 'domain_allowlist') {
          payload.allowed_signup_domains = formState.value.allowed_signup_domains;
        }

        return await SignupConfigService.putConfigForDomain(domainExtId, payload);
      });

      if (result?.record) {
        signupConfig.value = result.record;
        if (result.details) details.value = result.details;
        formState.value = configToFormState(result.record);
        snapshotFormState();
        notifications.show(t('web.domains.signup.update_success'), 'success', 'top');
      }
    } finally {
      isSaving.value = false;
    }
  };

  /**
   * Delete the signup config for this domain ("Reset to defaults"): unpins
   * the domain so it follows the workspace defaults again. The response
   * carries post-delete resolution details, so the reseeded form reflects
   * the now-inherited state without a refetch.
   */
  const deleteConfig = async () => {
    isDeleting.value = true;
    error.value = null;

    try {
      await wrapAction(async () => {
        const result = await SignupConfigService.deleteConfigForDomain(domainExtId);
        signupConfig.value = null;
        if (result.details) details.value = result.details;
        seedFormState();
        snapshotFormState();
        notifications.show(t('web.domains.signup.delete_success'), 'success', 'top');
      });
    } finally {
      isDeleting.value = false;
    }
  };

  /**
   * Reset form to last-saved state.
   */
  const discardChanges = () => {
    if (savedFormState.value) {
      formState.value = {
        ...savedFormState.value,
        allowed_signup_domains: [...savedFormState.value.allowed_signup_domains],
      };
    }
  };

  return {
    // State
    isLoading,
    isInitialized,
    isSaving,
    isDeleting,
    error,
    signupConfig,
    details,
    formState,

    // Computed
    isConfigured,
    isEnabled,
    hasUnsavedChanges,

    // Auth-override display state (ADR-024)
    globalEnabled: overrideState.globalEnabled,
    effectiveEnabled: overrideState.effectiveEnabled,
    isExplicitlyConfigured: overrideState.isExplicitlyConfigured,
    isWorkspaceDefault: overrideState.isWorkspaceDefault,
    isGloballyDisabled: overrideState.isGloballyDisabled,

    // Actions
    initialize,
    saveConfig,
    deleteConfig,
    discardChanges,
  };
}
