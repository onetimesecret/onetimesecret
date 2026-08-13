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
import { createError, type ApplicationError } from '@/schemas/errors';
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
 * available (codebase convention).
 *
 * SSO is deliberately absent. Bootstrap `features.sso` is PLATFORM SSO
 * (AUTH_SSO_ENABLED + platform provider env), resolved by ConfigSerializer
 * against the *current request's* display_domain — on the workspace host that
 * is the canonical site. Per-domain SSO is TENANT SSO: whether it RUNS is
 * decided by the domain's SsoConfig credentials + sso_permitted_for? (the
 * stored sso_enabled) — the runtime ladder never consults ORGS_SSO_ENABLED or
 * manage_sso, which only gate who may CONFIGURE it (write endpoints + UI).
 * Never AND runtime state with those management gates. Reading the platform
 * flag here made the domain sign-in page the sole surface gating tenant SSO
 * on the wrong axis, and — worse — seeded `sso_enabled` from it, so the first
 * autosave on an install with platform SSO off persisted `sso_enabled: false`
 * and killed the domain's working tenant SSO.
 *
 * Single definition consumed by both the page (method gating) and this
 * composable (seeding unconfigured domains).
 */
export interface GlobalMethodAvailability {
  email_auth: boolean;
  webauthn: boolean;
}

export function resolveGlobalMethodAvailability(): GlobalMethodAvailability {
  const features = useBootstrapStore().features;
  return {
    email_auth: features?.email_auth !== false,
    webauthn: features?.webauthn !== false,
  };
}

/**
 * Seed form state for an unconfigured domain from the inherited global
 * state (ADR-024): the selected mode and availability toggles reflect what
 * actually runs, and the first explicit write materializes this snapshot
 * plus the user's change — never static defaults that could silently flip
 * unrelated behavior.
 *
 * The null-details fallback seeds signin OFF (custom domains are default-off
 * opt-in, #3814) and only backs the placeholder state before initialize
 * resolves — initialize itself errors on a details-less response instead of
 * seeding, so a guessed seed can never be materialized by an autosave.
 *
 * restrict_to is seeded from `details.effective_restrict_to` — the server's
 * resolution — NOT from `global_restrict_to` (ADR-024 A4). The client used to
 * read the raw global value and re-derive what would actually run; there is
 * now exactly one place that decides, and it is the server. The named method
 * is taken whatever the state, including `unavailable`: the restriction still
 * stands, and dropping the name here would seed (and, on the next autosave,
 * persist) an unrestricted domain.
 */
function createSeededFormState(
  details: SigninConfigDetails | null,
  methods: GlobalMethodAvailability
): SigninConfigFormState {
  return {
    enabled: false,
    signin_enabled: details?.effective_enabled ?? false,
    restrict_to: details?.effective_restrict_to?.restrict_to ?? null,
    email_auth_enabled: methods.email_auth,
    // Both seed call sites run with no record (initialize's null branch,
    // deleteConfig after clearing it), and for an unconfigured domain the
    // backend authority — SigninConfig.sso_permitted_for? — returns true
    // unconditionally ("master switch off => defer to SsoConfig credentials").
    // So the inherited state is literally true; materializing this seed leaves
    // tenant SSO exactly as it was running.
    sso_enabled: true,
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
    signin_enabled: config.signin_enabled ?? false,
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

  /**
   * The server's restriction resolution for this domain (ADR-024 A4),
   * verbatim. Null only until details have loaded. Consumers read `.state`
   * — all three states, `unavailable` included — and never recompute it from
   * `global_restrict_to` and the raw flags.
   */
  const effectiveRestrictTo = computed(() => details.value?.effective_restrict_to ?? null);

  /**
   * The resolved restriction cannot run on this domain: sign-in offers
   * nothing until the owner changes it (fail-closed, ADR-024 A3). Distinct
   * from "unrestricted" — this is a surfaced dead end, not an open door.
   */
  const isRestrictionUnavailable = computed(
    () => effectiveRestrictTo.value?.state === 'unavailable'
  );

  /** Tenant-SSO availability verdict from the runtime ladder (#4111). */
  const tenantSso = computed(() => details.value?.tenant_sso ?? null);

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
   *
   * A response with neither record nor details (older backend 404 or a
   * payload that failed schema validation) fails loudly instead of seeding:
   * the seed is a guess about the inherited state, and any autosave would
   * materialize that guess as an explicit override — on an SSO-only domain
   * that would persist signin_enabled: false and disable sign-in (PR #3817).
   */
  const initialize = () =>
    wrap(async () => {
      const response = await SigninConfigService.getConfigForDomain(domainExtId);

      if (!response.record && !response.details) {
        throw createError(t('web.COMMON.unexpected_error'), 'technical', 'error');
      }

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
   * Patch queued while a PUT is in flight. Concurrent auto-saves coalesce
   * here (later keys win) and drain as follow-up saves once the in-flight
   * request settles. Dropping them instead would silently lose a user
   * action — today every control disables while isSaving, but the composable
   * must not stake correctness on every future caller remembering to.
   *
   * The queued patch is deliberately NOT merged into formState until its own
   * save runs: saveConfig's success path replaces formState from the server
   * record (and its failure path reverts to the saved snapshot), either of
   * which would clobber an early optimistic merge.
   */
  let queuedPatch: {
    partial: Partial<SigninConfigFormState>;
    hint?: keyof SigninConfigFormState;
  } | null = null;

  /** Merge one patch into formState, attribute the spinner, run one PUT. */
  const applyAndSave = async (
    partial: Partial<SigninConfigFormState>,
    savingFieldHint?: keyof SigninConfigFormState
  ) => {
    formState.value = { ...formState.value, ...partial };
    const firstKey = Object.keys(partial)[0] as keyof SigninConfigFormState | undefined;
    savingField.value = savingFieldHint ?? firstKey ?? null;
    await saveConfig();
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
   * A call arriving while a save is in flight queues (see queuedPatch) and
   * resolves immediately; the call that owns the in-flight save drains the
   * queue before returning.
   *
   * @param partial - fields to merge into formState before saving
   * @param savingFieldHint - field to attribute the spinner to; defaults to
   *   the partial's first key
   */
  const autoSaveFields = async (
    partial: Partial<SigninConfigFormState>,
    savingFieldHint?: keyof SigninConfigFormState
  ) => {
    if (isSaving.value) {
      queuedPatch = {
        partial: { ...queuedPatch?.partial, ...partial },
        hint: savingFieldHint ?? queuedPatch?.hint,
      };
      return;
    }

    try {
      await applyAndSave(partial, savingFieldHint);
      while (queuedPatch) {
        const next = queuedPatch;
        queuedPatch = null;
        await applyAndSave(next.partial, next.hint);
      }
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

    // Server-resolved restriction + tenant SSO verdict (ADR-024 A4, #4111)
    effectiveRestrictTo,
    isRestrictionUnavailable,
    tenantSso,

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
