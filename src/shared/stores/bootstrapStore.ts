// src/shared/stores/bootstrapStore.ts

import {
  bootstrapSchema,
  effectiveAuthStatus,
  type ApiGuestRoutes,
  type ApiInterface,
  type BootstrapPayload,
  type ClientAuthStatus,
  type FooterLinksConfig,
  type HeaderConfig,
  type LegalLinks,
  type UiCapabilities,
} from '@/schemas/contracts/bootstrap';
import {
  getBootstrapSnapshot,
  replaceBootstrapSnapshot,
  updateBootstrapSnapshot,
} from '@/services/bootstrap.service';
import { setDiagnosticsActorContext } from '@/services/diagnostics.service';
import { parseCompleteSnapshot } from '@/utils/snapshotOrdering';
import { defineStore } from 'pinia';

/**
 * Default values for logged-out / initial state.
 *
 * Derived from bootstrapSchema.parse({}) - the schema is the single source
 * of truth for default values. This ensures consistency between:
 * - Server-side Rhales validation
 * - Client-side TypeScript types
 * - Store defaults
 *
 * When the user logs out, the store resets to these values.
 */
/**
 * Parse schema with empty input to get base defaults.
 * Note: Zod's .optional() fields are not included in the output if undefined.
 */
const SCHEMA_DEFAULTS = bootstrapSchema.parse({});

/**
 * Complete DEFAULTS with all optional fields explicitly set to undefined.
 * This ensures Pinia's reactive state tracks all properties from the start,
 * allowing later updates to trigger reactivity correctly.
 */
const DEFAULTS: BootstrapPayload = {
  ...SCHEMA_DEFAULTS,
  // Explicitly include optional fields that Zod omits (fields marked .optional()
  // in the schema, not fields with .default() which are included in SCHEMA_DEFAULTS)
  apitoken: undefined,
  // The server's status statement and the ADR-046 ordering fields are
  // `.optional()` (absent from a pre-contract backend, and the ordering pair
  // from every unordered payload). Listed so Pinia creates their accessors.
  auth_status: undefined,
  snapshot_epoch: undefined,
  snapshot_version: undefined,
  snapshot_generated_at: undefined,
  customer_since: undefined,
  regions: undefined,
  stripe_customer: undefined,
  stripe_subscriptions: undefined,
  entitlement_preview_planid: undefined,
  entitlement_preview_plan_name: undefined,
  organization: undefined,
  // Pseudonymous reference for the diagnostics boundary — the opaque `user.id`
  // Sentry groups a person's errors by. It is not an analytics identifier:
  // nothing counts it, and it exists so a defect report can be attributed to
  // one session without an email, customer id or IP.
  //
  // `.optional()` in the schema because the server OMITS it for anonymous
  // sessions, so Zod's parse({}) leaves it out of SCHEMA_DEFAULTS and Pinia
  // would not track it. Listed here so that later update()/resetForLogout()
  // writes are reactive AND so that $reset() has a defined target to restore
  // it to.
  //
  // Deliberately TOP-LEVEL, not nested under the `diagnostics` config block:
  // resetForLogout() preserves `diagnostics` across logout by design, so a
  // reference parked there would survive sign-out. At top level, $reset()
  // clears it.
  diagnostics_ref: undefined,
  // Brand fields (per-installation defaults from OT.conf['brand'])
  brand_primary_color: undefined,
  brand_product_name: undefined,
  brand_product_domain: undefined,
  brand_support_email: undefined,
  brand_corner_style: undefined,
  brand_font_family: undefined,
  brand_button_text_light: undefined,
  brand_logo_url: undefined,
  brand_logo_dark_url: undefined,
  brand_logo_alt: undefined,
  brand_favicon_url: undefined,
};

/**
 * Payload keys that describe ONE ACCOUNT rather than the installation (#4458).
 *
 * They are withheld whenever the client status is not `authenticated`, and a
 * complete snapshot that omits one clears it. Everything not listed here is
 * installation or domain configuration, which is safe to keep across a loss
 * of authority (and which resetForLogout() preserves for the same reason).
 *
 * A new account-scoped payload field MUST be added here; the account
 * transition spec fails when a field carrying identity survives a transition.
 */
export const ACCOUNT_SCOPED_KEYS = [
  'apitoken',
  'cust',
  'custid',
  'email',
  'customer_since',
  'has_password',
  'impersonation',
  'organization',
  'custom_domains',
  'domain_context',
  'stripe_customer',
  'stripe_subscriptions',
  'entitlement_preview_planid',
  'entitlement_preview_plan_name',
  'diagnostics_ref',
] as const satisfies ReadonlyArray<keyof BootstrapPayload>;

/**
 * Keys that state the authentication status. Only a complete snapshot
 * (init/applySnapshot) or a reset may write them; update() drops them, so a
 * local patch can never grant or revoke authority (#4458).
 */
const AUTH_AUTHORITY_KEYS = [
  'auth_status',
  'authenticated',
  'awaiting_mfa',
  'snapshot_epoch',
  'snapshot_version',
  'snapshot_generated_at',
] as const satisfies ReadonlyArray<keyof BootstrapPayload>;

/** State keys that are not part of the server payload. */
const CLIENT_ONLY_KEYS: ReadonlySet<string> = new Set([
  '_initialized',
  'authStatus',
  'retiredEpochs',
]);

/**
 * The accepted ordering pair (ADR-046). `version` stays a decimal string:
 * compare with BigInt, never as a number.
 */
export interface SnapshotWatermark {
  epoch: string;
  version: string;
}

/**
 * Filters out undefined values from an object.
 * Used to ensure updates only overwrite fields with defined values,
 * matching the previous updateIfDefined() behavior.
 */
function filterDefined<T extends Record<string, unknown>>(obj: T): Partial<T> {
  const result: Partial<T> = {};
  for (const key of Object.keys(obj) as Array<keyof T>) {
    if (obj[key] !== undefined) {
      result[key] = obj[key];
    }
  }
  return result;
}

/**
 * Store state type extending BootstrapPayload with internal tracking.
 */
interface BootstrapState extends BootstrapPayload {
  _initialized: boolean;
  /**
   * THE client authentication status (#4458). Every route and component
   * accessor derives from this one field. `checking` is client-only: no
   * verified statement from the server is held yet. It is written only by
   * init(), applySnapshot(), withholdAuthority() and the two resets.
   */
  authStatus: ClientAuthStatus;
  /**
   * Every snapshot epoch this page has replaced (ADR-046, #4464). A snapshot
   * from one of them is an anomaly for the lifetime of the page, so this
   * survives both resets; only a page load forgets it.
   */
  retiredEpochs: string[];
}

/** Restores every account-scoped key of `target` to its logged-out default. */
function withholdAccountScope(target: Record<string, unknown>): void {
  const defaults = structuredClone(DEFAULTS) as Record<string, unknown>;
  for (const key of ACCOUNT_SCOPED_KEYS) {
    target[key] = defaults[key];
  }
}

/**
 * Bootstrap Store - Centralized Server State
 *
 * This store replaces the WindowService dual-state pattern with a single
 * Pinia store that holds all server-injected configuration and user state.
 *
 * Design decisions:
 * 1. Options API with $patch() for efficient bulk updates
 *    - Hydration uses $patch() instead of individual ref updates
 *    - Reset preserves server config fields automatically
 *
 *    Note on $reset(): The built-in $reset() method only works automatically
 *    with Options Stores. For Setup Stores, you must implement $reset manually
 *    (typically via a plugin or custom action) because Pinia cannot infer the
 *    initial state from a function's returned refs. This is a genuine advantage
 *    of Options Stores for teams prioritizing state reset functionality.
 *
 * 2. Schema-derived defaults for logged-out state
 *    - Store is always in a valid state
 *    - $reset() restores initial DEFAULTS (does NOT preserve server config)
 *    - resetForLogout() resets user state while preserving server config
 *
 * 3. Single source of truth
 *    - No more window.__BOOTSTRAP_ME__ vs reactiveState synchronization
 *    - All access goes through this store after initialization
 *
 * Lifecycle:
 * - init() called once during app bootstrap (after Pinia is installed)
 * - applySnapshot() is the only way a complete snapshot (and with it the
 *   authentication status) enters the store: hydration, or a /bootstrap/me
 *   response accepted by the refresh coordinator in authStore
 * - update() merges a local patch; it cannot set authentication state
 * - resetForLogout() called on logout to restore defaults (preserving server config)
 *
 * Access Patterns:
 * Options API stores auto-unwrap refs, so access patterns differ by context:
 *
 * 1. Direct store access (routes, composables, non-reactive JS):
 *    ```ts
 *    const store = useBootstrapStore();
 *    if (store.billing_enabled) { ... }  // No .value needed
 *    ```
 *
 * 2. Reactive destructuring (Vue components needing reactivity):
 *    ```ts
 *    const { billing_enabled } = storeToRefs(store);
 *    if (billing_enabled.value) { ... }  // .value required
 *    ```
 *
 * 3. Template usage (either pattern works without .value):
 *    ```vue
 *    <div v-if="store.billing_enabled">  // Direct access
 *    <div v-if="billing_enabled">        // After storeToRefs destructure
 *    ```
 */
export const useBootstrapStore = defineStore('bootstrap', {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE - Single object spreading schema defaults
  // ═══════════════════════════════════════════════════════════════════════════

  // structuredClone, not a shallow spread: DEFAULTS contains nested objects
  // (e.g. ui.header) and a shallow copy would share those references across
  // every store instance, letting one instance's $patch bleed into the next
  // (notably across createTestingPinia instances in tests).
  state: (): BootstrapState => ({
    ...structuredClone(DEFAULTS),
    _initialized: false,
    authStatus: 'checking',
    retiredEpochs: [],
  }),

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS - Computed properties for derived state
  // ═══════════════════════════════════════════════════════════════════════════

  getters: {
    /**
     * Whether the store has been initialized from bootstrap data.
     */
    isInitialized: (state): boolean => state._initialized,

    /**
     * The ordering watermark (ADR-046, #4464): the epoch and version of the
     * last APPLIED complete snapshot, or null when the tab is unordered.
     *
     * Derived, not stored separately, so it cannot drift from the state it
     * describes. applySnapshot() replaces both fields with the snapshot's own
     * (clearing them when the snapshot carries none), and update() drops them
     * with the other authority keys, so a local patch can never advance it.
     */
    watermark: (state): SnapshotWatermark | null =>
      state.snapshot_epoch !== undefined && state.snapshot_version !== undefined
        ? { epoch: state.snapshot_epoch, version: state.snapshot_version }
        : null,

    /**
     * Whether the last ACCEPTED snapshot reported a session. Unlike
     * `authStatus` this does not change when authority is withheld after
     * failed refreshes: it answers "did the server last say there was a
     * session", which is what decides whether a later "no session" is an end.
     */
    lastSnapshotReportedSession: (state): boolean => state.authenticated || state.awaiting_mfa,

    /**
     * Header configuration from UI settings.
     * Provides typed access to header config with fallback.
     */
    headerConfig: (state): HeaderConfig | undefined => state.ui.header,

    /**
     * Footer links configuration from UI settings.
     * Provides typed access to footer config with fallback.
     */
    footerLinksConfig: (state): FooterLinksConfig | undefined => state.ui.footer_links,

    /**
     * Legal & policy URLs from site.legal (#4278). Sibling to
     * footerLinksConfig. Each field is null when not configured; consumers
     * hide the corresponding link entirely rather than render a dead anchor.
     */
    legalUrls: (state): LegalLinks => state.legal,

    /**
     * UI capability flags controlling optional form-field visibility.
     * Each flag is undefined when unset; consumers treat undefined as enabled.
     */
    uiCapabilities: (state): UiCapabilities | undefined => state.ui.capabilities,

    /**
     * True while this session is a colonel presenting as another customer.
     *
     * `impersonation` is a `.nullable().default(null)` schema field, so it is
     * present in SCHEMA_DEFAULTS and needs no entry in the DEFAULTS block below
     * the way `.optional()` fields (entitlement_preview_planid et al) do —
     * Pinia tracks it from the first state() call and $reset()/resetForLogout()
     * restore it to null.
     */
    isImpersonating: (state): boolean => state.impersonation !== null,

    /**
     * API configuration from bootstrap payload.
     * Contains enabled flag and guest route permissions.
     */
    apiConfig: (state): ApiInterface => state.api,

    /**
     * Guest route permissions for API access.
     * Controls which API routes are available to unauthenticated users.
     */
    guestRoutes: (state): ApiGuestRoutes => state.api.guest_routes,
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  actions: {
    /**
     * Initializes the store from bootstrap snapshot.
     * Called once during app initialization after Pinia is installed.
     *
     * @returns Object with initialization status
     */
    init(): { isInitialized: boolean } {
      if (this._initialized) {
        console.debug('[BootstrapStore.init] Already initialized, skipping');
        return { isInitialized: true };
      }

      try {
        const snapshot = getBootstrapSnapshot();

        // No hydration at all. NOT anonymous: nothing has been verified, so the
        // status stays `checking` and the refresh coordinator asks the server
        // once (#4456).
        if (!snapshot) {
          console.debug('[BootstrapStore.init] No bootstrap data available, status: checking');
          this._initialized = true;
          return { isInitialized: true };
        }

        // Hydration establishes the initial watermark (ADR-046, #4464): a full
        // page load has no preceding watermark and accepts its validated pair
        // as the start of the stream. Without a valid pair the tab starts
        // unordered; a malformed pair does not make the rest unreadable.
        const parsed = parseCompleteSnapshot(snapshot);

        if (parsed.ok) {
          this.applySnapshot(parsed.payload);
        } else {
          // Invalid hydration. The configuration half is still applied as it
          // always was, so the page renders in the right locale and with the
          // operator's auth feature flags rather than permissive schema
          // defaults. The ACCOUNT half is withheld and the status stays
          // `checking`: a payload that fails the shared contract makes no
          // statement about who is signed in.
          console.error(
            '[BootstrapStore.init] Hydration failed the bootstrap contract, status: checking',
            parsed.invalidPaths
          );
          const config: Record<string, unknown> = { ...filterDefined(snapshot) };
          for (const key of AUTH_AUTHORITY_KEYS) delete config[key];
          withholdAccountScope(config);
          this.$patch((state) => {
            Object.assign(state, config);
            state.authStatus = 'checking';
            state._initialized = true;
          });
          replaceBootstrapSnapshot(config as Partial<BootstrapPayload>);
        }

        console.debug('[BootstrapStore.init] Initialized from snapshot:', {
          authStatus: this.authStatus,
          locale: this.locale,
        });
      } catch (error) {
        // Hydration threw. Same rule: defaults, and `checking`, never anonymous.
        console.error(
          '[BootstrapStore.init] Failed to initialize from snapshot, status: checking:',
          error
        );
        this._initialized = true;
      }

      return { isInitialized: true };
    },

    /**
     * Applies a COMPLETE, contract-valid snapshot (#4458).
     *
     * This is the only way authentication state enters the client: hydration
     * (init) and an accepted /bootstrap/me response (the refresh coordinator in
     * authStore) both end here. It REPLACES rather than merges — the next
     * state is built from `{ ...DEFAULTS, ...snapshot }`, and any payload key
     * the snapshot omits is cleared — so a field of the previous account
     * cannot survive an account change by being left out of the new payload.
     *
     * The status comes from effectiveAuthStatus(), which can only withhold.
     * Unless it is `authenticated`, every account-scoped field is restored to
     * its logged-out default, whatever the payload carried. The store, the
     * pre-Pinia mirror and the diagnostics actor context change together.
     *
     * Ordering (ADR-046, #4464): the snapshot's own epoch/version pair becomes
     * the watermark in the same patch, and `retire` names an epoch the caller
     * decided this snapshot replaces. This method does not decide acceptance;
     * the refresh coordinator does, before calling it.
     *
     * @param snapshot - Output of bootstrapSchema.parse/safeParse, never raw JSON
     * @param options.retire - Epoch to remember as replaced, if any
     */
    applySnapshot(snapshot: BootstrapPayload, options: { retire?: string | null } = {}): void {
      const status = effectiveAuthStatus(snapshot);
      const next: Record<string, unknown> = { ...structuredClone(DEFAULTS), ...snapshot };

      // has_password: null means the server could not determine it (transient
      // auth-DB failure during serialization). For the SAME account, keep the
      // last known value so a blipped refresh never clobbers a good one. For
      // any other account there is no prior value that applies.
      const sameAccount = this.custid !== '' && this.custid === snapshot.custid;
      if (snapshot.has_password === null && sameAccount) {
        next.has_password = this.has_password;
      }

      if (status !== 'authenticated') {
        withholdAccountScope(next);
      }

      // The two projections are restated from the status so that the three
      // cannot disagree in client state even when they did on the wire.
      next.auth_status = status;
      next.authenticated = status === 'authenticated';
      next.awaiting_mfa = status === 'mfa_pending';

      this.$patch((state) => {
        const target = state as unknown as Record<string, unknown>;
        for (const key of Object.keys(target)) {
          if (!CLIENT_ONLY_KEYS.has(key) && !(key in next)) target[key] = undefined;
        }
        Object.assign(target, next);
        state.authStatus = status;
        state._initialized = true;
        if (options.retire && !state.retiredEpochs.includes(options.retire)) {
          state.retiredEpochs.push(options.retire);
        }
      });

      replaceBootstrapSnapshot(next as Partial<BootstrapPayload>);

      // setDiagnosticsActorContext validates the block and clears the context
      // on null. It no-ops when diagnostics are disabled.
      setDiagnosticsActorContext(this.diagnostics_ref ?? null);

      console.debug('[BootstrapStore.applySnapshot] Applied:', { authStatus: status });
    },

    /**
     * Withholds authority WITHOUT a server statement (#4458).
     *
     * Only the two client-side withholding states can be entered this way, so
     * this can never grant access: `checking` (nothing verified yet) and
     * `unavailable` (verification keeps failing). The last accepted snapshot
     * is left in place — a failed verification is not a sign-out, and the
     * accessors in authStore already read not-authenticated from the status.
     */
    withholdAuthority(status: 'checking' | 'unavailable'): void {
      this.authStatus = status;
    },

    /**
     * Merges a LOCAL patch into the store.
     *
     * A local patch is incomplete by definition and may not state who is
     * signed in: the authority keys are dropped (#4458). Authentication state
     * changes only through applySnapshot(), i.e. only on the server's word.
     *
     * @param data - Partial BootstrapPayload data to merge
     */
    update(data: Partial<BootstrapPayload>): void {
      const patch: Record<string, unknown> = { ...data };
      for (const key of AUTH_AUTHORITY_KEYS) {
        if (key in patch) {
          console.warn(`[BootstrapStore.update] Ignored "${key}": local patches cannot set auth state`);
          delete patch[key];
        }
      }

      // has_password: null is "no information"; never clobber a known value.
      if (patch.has_password === null) delete patch.has_password;

      const defined = filterDefined(patch) as Partial<BootstrapPayload>;

      // Functional $patch avoids _DeepPartial type issues with Stripe types.
      this.$patch((state) => {
        Object.assign(state, defined);
      });

      // Keep the bootstrap.service snapshot in sync so non-Pinia readers
      // (features.ts hasPassword/isSsoOnlyMode used by route guards and the
      // settings sidebar) see fresh values.
      updateBootstrapSnapshot(defined);

      if (defined.diagnostics_ref !== undefined) {
        setDiagnosticsActorContext(defined.diagnostics_ref);
      }
    },

    /**
     * Resets user-specific state while preserving server configuration.
     *
     * Called on logout to clear all user-specific state while keeping
     * server configuration fields that don't change per-user.
     *
     * Note: We intentionally preserve server config fields (authentication,
     * ui, legal, features, regions, secret_options, diagnostics) because:
     * 1. They're set by the server at startup and don't vary by user
     * 2. Resetting them would temporarily show permissive defaults
     * 3. They get re-hydrated on full page reload anyway
     *
     * The domain identity fields (canonical_domain, site_host, link_domains,
     * custom_domains, display_domain) are deliberately NOT preserved. They are
     * restored to schema defaults by $reset() — '' for the string fields, []
     * for link_domains (#4063) — which keeps link_domains symmetric with
     * canonical_domain. That symmetry is load-bearing: useDomainContext treats
     * an empty link pool as "stale payload" and falls back to
     * [canonical_domain], so preserving one without the other would produce a
     * picker offering operator domains with no canonical fallback behind them.
     * link_domains is a declared schema key precisely so this reset is
     * explicit rather than a silent strip of an untyped field.
     */
    resetForLogout(): void {
      // Capture current server config values before reset
      const preservedConfig = {
        api: this.api,
        authentication: this.authentication,
        ui: this.ui,
        legal: this.legal,
        features: this.features,
        regions: this.regions,
        secret_options: this.secret_options,
        diagnostics: this.diagnostics,
        disabled_homepage: this.disabled_homepage,
      };

      // A local sign-out ends this tab's stream: retire its epoch so a
      // snapshot from the signed-out session is never accepted again, and
      // keep the epochs already retired (ADR-046: remembered for the
      // lifetime of the page). $reset() clears the pair, so the tab
      // continues unordered.
      const retiredEpochs = [...this.retiredEpochs];
      const endedEpoch = this.snapshot_epoch;
      if (endedEpoch !== undefined && !retiredEpochs.includes(endedEpoch)) {
        retiredEpochs.push(endedEpoch);
      }

      // Use built-in $reset to restore all state to DEFAULTS
      this.$reset();

      // Restore server config fields and _initialized flag
      // Use functional $patch to avoid _DeepPartial type issues
      this.$patch((state) => {
        state.api = preservedConfig.api;
        state.authentication = preservedConfig.authentication;
        state.ui = preservedConfig.ui;
        state.legal = preservedConfig.legal;
        state.features = preservedConfig.features;
        state.regions = preservedConfig.regions;
        state.secret_options = preservedConfig.secret_options;
        state.diagnostics = preservedConfig.diagnostics;
        state.disabled_homepage = preservedConfig.disabled_homepage;
        // An explicit local sign-out. $reset() alone leaves `checking`.
        state.authStatus = 'anonymous';
        state.auth_status = 'anonymous';
        state._initialized = true;
        state.retiredEpochs = retiredEpochs;
      });

      // Replace the PRE-PINIA mirror as well. bootstrap.service holds a second
      // copy of the payload that `getBootstrapValue()` reads (features.ts
      // hasPassword, resolveDiagnosticsRef). Left alone, the previous
      // account's cust / has_password / diagnostics_ref would stay readable
      // there after a soft (SPA) logout. Replacing it from the post-reset
      // state covers every account-scoped key at once, in the store that owns
      // the mirror, for every caller of resetForLogout.
      const mirror: Record<string, unknown> = { ...this.$state };
      for (const key of CLIENT_ONLY_KEYS) delete mirror[key];
      replaceBootstrapSnapshot(mirror as Partial<BootstrapPayload>);

      console.debug('[BootstrapStore.resetForLogout] Reset to defaults (server config preserved)');
    },
  },
});
