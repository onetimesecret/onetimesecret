// src/shared/composables/useSigninConfig.ts

/**
 * Composable for managing per-domain sign-in configuration.
 *
 * Follows the useSignupConfig lifecycle pattern:
 * - initialize: fetch current config (record null = unconfigured, not error)
 * - saveConfig: PUT full replacement
 * - deleteConfig: removes config (falls back to global signin policy)
 * - discardChanges: resets form state to last-saved snapshot
 * - hasUnsavedChanges: computed diff between form and saved state
 *
 * Auth-override semantics (ADR-024, shared with useSignupConfig via
 * useAuthOverrideState):
 * - Unconfigured domains are SEEDED from the inherited global state
 *   (response `details` + bootstrap method availability), so what the form
 *   shows selected is what actually runs — there is no separate display path.
 * - Every save materializes an explicit override (`enabled: true` via
 *   asExplicitOverride). Touching any control pins the domain against future
 *   changes to the workspace defaults; deleteConfig unpins.
 *
 * @param domainExtId - Domain external ID for API calls
 */

import type { PutSigninConfigRequest } from '@/schemas/api/domains/requests/signin-config';
import type { SigninConfigDetails } from '@/schemas/api/domains/responses/signin-config';
import type { ApplicationError } from '@/schemas/errors';
import type {
  CustomDomainSigninConfig,
  SigninRestrictTo,
} from '@/schemas/shapes/domains/signin-config';
import { SigninConfigService } from '@/services/signin-config.service';
import { useNotificationsStore } from '@/shared/stores';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';
import { asExplicitOverride, createAuthOverrideState } from './useAuthOverrideState';

/**
 * Form state for signin configuration.
 */
export interface SigninConfigFormState {
  enabled: boolean;
  signin_enabled: boolean;
  restrict_to: SigninRestrictTo | null;
  email_auth_enabled: boolean;
  sso_enabled: boolean;
}

/**
 * Globally-available auth methods (install-level config), read from the
 * bootstrap. The workspace app runs on the dashboard domain, so bootstrap
 * features reflect the install/global auth config. undefined is treated as
 * available (codebase convention). SSO is a union (boolean | config object);
 * an object's `enabled` flag is authoritative.
 *
 * Single definition consumed by both the page (method gating) and this
 * composable (seeding unconfigured domains).
 */
export interface GlobalMethodAvailability {
  email_auth: boolean;
  webauthn: boolean;
  sso: boolean;
}

export function resolveGlobalMethodAvailability(): GlobalMethodAvailability {
  const features = useBootstrapStore().features;
  const sso = features?.sso;
  const ssoAvailable =
    typeof sso === 'object' && sso !== null ? sso.enabled : sso !== false;
  return {
    email_auth: features?.email_auth !== false,
    webauthn: features?.webauthn !== false,
    sso: ssoAvailable,
  };
}

/**
 * Seed form state for an unconfigured domain from the inherited global
 * state (ADR-024): the selected mode and availability toggles reflect what
 * actually runs, and the first explicit write materializes this snapshot
 * plus the user's change — never static defaults that could silently flip
 * unrelated behavior.
 */
function createSeededFormState(
  details: SigninConfigDetails | null,
  methods: GlobalMethodAvailability
): SigninConfigFormState {
  return {
    enabled: false,
    signin_enabled: details?.effective_enabled ?? true,
    restrict_to: details?.global_restrict_to ?? null,
    email_auth_enabled: methods.email_auth,
    sso_enabled: methods.sso,
  };
}

/**
 * Convert API response to form state.
 *
 * Nullable API fields are coerced to concrete booleans for the form:
 * null inherits the global default, which the form represents as the
 * field's default value.
 */
function configToFormState(config: CustomDomainSigninConfig): SigninConfigFormState {
  return {
    enabled: config.enabled,
    signin_enabled: config.signin_enabled ?? true,
    restrict_to: config.restrict_to ?? null,
    email_auth_enabled: config.email_auth_enabled ?? false,
    sso_enabled: config.sso_enabled ?? false,
  };
}

/* eslint max-lines-per-function: off */
export function useSigninConfig(domainExtId: string) {
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

  /**
   * The form field currently being auto-saved (toggle save-on-change), or
   * null. Drives per-toggle loading feedback so only the flipped toggle
   * spins while the others merely disable.
   */
  const savingField = ref<keyof SigninConfigFormState | null>(null);

  /** The full config object from the API. Null = unconfigured. */
  const signinConfig = ref<CustomDomainSigninConfig | null>(null);

  /**
   * Resolution details from the last API response (ADR-024): the global
   * capability and the resolver's effective output for this domain. The UI
   * displays these; it never re-derives them from the raw flags.
   */
  const details = ref<SigninConfigDetails | null>(null);

  /** Current form state (editable). */
  const formState = ref<SigninConfigFormState>(
    createSeededFormState(null, resolveGlobalMethodAvailability())
  );

  /** Snapshot of form state at last save/load. Used for unsaved-changes detection. */
  const savedFormState = ref<SigninConfigFormState | null>(null);

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

  /** Whether a signin config record exists for this domain. */
  const isConfigured = computed(() => signinConfig.value !== null);

  /**
   * Shared auth-override display state (ADR-024): effective/global
   * availability and the workspace-default flag that drives the badge.
   */
  const overrideState = createAuthOverrideState(signinConfig, details);

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
  // Actions
  // ---------------------------------------------------------------------------

  const seedFormState = () => {
    formState.value = createSeededFormState(details.value, resolveGlobalMethodAvailability());
  };

  /**
   * Load the current signin config for this domain.
   * A null record means "unconfigured" — the form is seeded from the
   * inherited global state carried in details, not from static defaults.
   */
  const initialize = () =>
    wrap(async () => {
      const response = await SigninConfigService.getConfigForDomain(domainExtId);
      signinConfig.value = response.record;
      details.value = response.details;

      if (response.record) {
        formState.value = configToFormState(response.record);
      } else {
        seedFormState();
      }
      savedFormState.value = { ...formState.value };
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
        const payload: PutSigninConfigRequest = asExplicitOverride({
          signin_enabled: formState.value.signin_enabled,
          restrict_to: formState.value.restrict_to,
          email_auth_enabled: formState.value.email_auth_enabled,
          sso_enabled: formState.value.sso_enabled,
        });

        return await SigninConfigService.putConfigForDomain(domainExtId, payload);
      });

      if (result?.record) {
        signinConfig.value = result.record;
        if (result.details) details.value = result.details;
        formState.value = configToFormState(result.record);
        savedFormState.value = { ...formState.value };
        notifications.show(t('web.domains.signin.update_success'), 'success', 'top');
      } else if (savedFormState.value) {
        // PUT failed (wrapAction notified the user and returned undefined).
        // Every change auto-saves optimistically, so revert formState to the
        // last-saved snapshot — otherwise a toggle/radio stays visually in the
        // new position while the server still holds the old value.
        formState.value = { ...savedFormState.value };
      }
    } finally {
      isSaving.value = false;
    }
  };

  /**
   * Merge a partial form patch and persist immediately (save-on-change).
   *
   * The signin form auto-saves every change — there is no Save button. The
   * PUT is a full replacement, so the merged formState is sent in full; the
   * partial only carries the fields that changed. Multi-field saves (e.g.
   * picking a restrict_to method also flips its availability flag) commit
   * atomically as one PUT, avoiding a two-request race.
   *
   * @param partial - fields to merge into formState before saving
   * @param savingFieldHint - field to attribute the spinner to; defaults to
   *   the partial's first key
   */
  const autoSaveFields = async (
    partial: Partial<SigninConfigFormState>,
    savingFieldHint?: keyof SigninConfigFormState
  ) => {
    if (isSaving.value) return;
    formState.value = { ...formState.value, ...partial };

    const firstKey = Object.keys(partial)[0] as keyof SigninConfigFormState | undefined;
    savingField.value = savingFieldHint ?? firstKey ?? null;

    try {
      await saveConfig();
    } finally {
      savingField.value = null;
    }
  };

  /**
   * Update a single field and persist immediately (save-on-change).
   *
   * Thin wrapper over autoSaveFields for single-field callers.
   */
  const autoSaveField = <K extends keyof SigninConfigFormState>(
    field: K,
    value: SigninConfigFormState[K]
  ) => autoSaveFields({ [field]: value } as Partial<SigninConfigFormState>, field);

  /**
   * Delete the signin config for this domain ("Reset to defaults"): unpins
   * the domain so it follows the workspace defaults again. The response
   * carries post-delete resolution details, so the reseeded form reflects
   * the now-inherited state without a refetch.
   */
  const deleteConfig = async () => {
    isDeleting.value = true;
    error.value = null;

    try {
      await wrapAction(async () => {
        const result = await SigninConfigService.deleteConfigForDomain(domainExtId);
        signinConfig.value = null;
        if (result.details) details.value = result.details;
        seedFormState();
        savedFormState.value = { ...formState.value };
        notifications.show(t('web.domains.signin.reset_success'), 'success', 'top');
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
    details,
    formState,
    savingField,

    // Computed
    isConfigured,
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
    autoSaveField,
    autoSaveFields,
    deleteConfig,
    discardChanges,
  };
}
