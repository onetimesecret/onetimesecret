// src/shared/composables/useAuthOverrideState.ts

/**
 * Shared behavior for the per-domain auth override settings (sign-in and
 * sign-up). Defined once here, implemented twice — by useSigninConfig and
 * useSignupConfig (ADR-024).
 *
 * The model (see ADR-024 for the full contract):
 *
 * - Storage keeps two flags per feature: `enabled` (the customer has
 *   explicitly configured this domain — the "pin") and `{feature}_enabled`
 *   (the override value, ANDed with the global capability). The UI exposes
 *   ONE control: the effective availability.
 * - Display state comes from the backend resolver via response `details`
 *   (global_enabled / effective_enabled). The client never re-derives
 *   availability from the raw flag pair.
 * - Every write materializes an explicit override (`enabled: true`). Touching
 *   any control is an explicit configuration action; "Reset to defaults"
 *   (DELETE) is the way back to inheriting workspace defaults.
 */

import type { AuthOverrideDetails } from '@/schemas/api/domains/responses/auth-override';
import { computed, type ComputedRef, type Ref } from 'vue';

export type { AuthOverrideDetails };

export interface AuthOverrideState {
  /** Install-level capability, null until details have loaded. */
  globalEnabled: ComputedRef<boolean | null>;
  /** Resolver output for this domain (what actually runs), null until loaded. */
  effectiveEnabled: ComputedRef<boolean | null>;
  /** The customer has explicitly configured this domain (record with enabled=true). */
  isExplicitlyConfigured: ComputedRef<boolean>;
  /**
   * The domain follows workspace defaults: no record, or a legacy record
   * with enabled=false (which the resolver treats identically). Drives the
   * "Workspace default" badge.
   */
  isWorkspaceDefault: ComputedRef<boolean>;
  /**
   * The install-level capability is off: the feature is unavailable on this
   * domain regardless of per-domain settings (kill switch). Controls stay
   * active — explicit config still matters for future default changes — but
   * the UI shows a dormant warning.
   */
  isGloballyDisabled: ComputedRef<boolean>;
}

/**
 * Derive the shared display state from a config record + response details.
 *
 * Generic over the record/details types (Ref is invariant): any record with
 * an `enabled` flag and any details extending the shared contract qualify.
 *
 * @param record - the raw config record (null when unconfigured)
 * @param details - resolution details from the last API response (null until loaded)
 */
export function createAuthOverrideState<
  TRecord extends { enabled: boolean },
  TDetails extends AuthOverrideDetails,
>(record: Ref<TRecord | null>, details: Ref<TDetails | null>): AuthOverrideState {
  const globalEnabled = computed(() => details.value?.global_enabled ?? null);
  const effectiveEnabled = computed(() => details.value?.effective_enabled ?? null);
  const isExplicitlyConfigured = computed(() => record.value?.enabled === true);
  const isWorkspaceDefault = computed(() => !isExplicitlyConfigured.value);
  const isGloballyDisabled = computed(() => globalEnabled.value === false);

  return {
    globalEnabled,
    effectiveEnabled,
    isExplicitlyConfigured,
    isWorkspaceDefault,
    isGloballyDisabled,
  };
}

/**
 * The writes-materialize rule (ADR-024): every save from the settings UI is
 * an explicit configuration action and must set `enabled: true` — never per
 * call site, always through this single chokepoint. This is also what fixed
 * the latent bug where mode picks created `enabled: false` records the
 * resolver ignores.
 */
export function asExplicitOverride<T extends object>(payload: T): T & { enabled: true } {
  return { ...payload, enabled: true };
}
