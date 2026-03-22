// src/shared/stores/bootstrapStore.ts

import { getBootstrapSnapshot } from '@/services/bootstrap.service';
import {
  bootstrapSchema,
  type BootstrapPayload,
  type FooterLinksConfig,
  type HeaderConfig,
} from '@/schemas/contracts/bootstrap';
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
  // Explicitly include optional fields that Zod omits
  apitoken: undefined,
  customer_since: undefined,
  regions: undefined,
  stripe_customer: undefined,
  stripe_subscriptions: undefined,
  entitlement_test_planid: undefined,
  entitlement_test_plan_name: undefined,
  organization: undefined,
  development: undefined,
};

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
 * - update() called after /bootstrap/me API responses
 * - refresh() fetches fresh state from server (use after mutations)
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

  state: (): BootstrapState => ({
    ...DEFAULTS,
    _initialized: false,
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
     * Header configuration from UI settings.
     * Provides typed access to header config with fallback.
     */
    headerConfig: (state): HeaderConfig | undefined => state.ui.header,

    /**
     * Footer links configuration from UI settings.
     * Provides typed access to footer config with fallback.
     */
    footerLinksConfig: (state): FooterLinksConfig | undefined => state.ui.footer_links,
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

        if (!snapshot) {
          console.debug('[BootstrapStore.init] No bootstrap data available, using defaults');
          this._initialized = true;
          return { isInitialized: true };
        }

        // Hydrate all state from snapshot using functional $patch
        // (functional form avoids _DeepPartial type issues with complex Stripe types)
        // Filter out undefined values to match previous updateIfDefined behavior
        this.$patch((state) => {
          Object.assign(state, filterDefined(snapshot));
          state._initialized = true;
        });

        console.debug('[BootstrapStore.init] Initialized from snapshot:', {
          authenticated: this.authenticated,
          locale: this.locale,
          email: this.email,
        });
      } catch (error) {
        // Fallback to defaults if snapshot parsing or hydration fails
        console.error('[BootstrapStore.init] Failed to initialize from snapshot, using defaults:', error);
        this._initialized = true;
      }

      return { isInitialized: true };
    },

    /**
     * Updates the store with new data from /bootstrap/me API response.
     * Only updates fields that are present in the data object.
     *
     * @param data - Partial BootstrapPayload data to merge
     */
    update(data: Partial<BootstrapPayload>): void {
      // Use functional $patch to avoid _DeepPartial type issues with complex Stripe types
      // Filter out undefined values to match previous updateIfDefined behavior
      this.$patch((state) => {
        Object.assign(state, filterDefined(data));
      });

      console.debug('[BootstrapStore.update] Updated with:', {
        authenticated: data.authenticated,
        awaiting_mfa: data.awaiting_mfa,
        fieldsUpdated: Object.keys(data).length,
      });
    },

    /**
     * Refreshes state from the /bootstrap/me API endpoint.
     * Use this to sync state with the server after actions that change server state.
     *
     * @returns Promise that resolves when state is refreshed
     * @throws Error if fetch fails
     */
    async refresh(): Promise<void> {
      if (typeof window === 'undefined') {
        throw new Error('[BootstrapStore] Cannot refresh: window is not defined');
      }

      const response = await fetch('/bootstrap/me', {
        method: 'GET',
        credentials: 'same-origin',
        headers: {
          Accept: 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`[BootstrapStore] Failed to refresh state: ${response.status}`);
      }

      const newState = (await response.json()) as BootstrapPayload;
      this.update(newState);
    },

    /**
     * Resets user-specific state while preserving server configuration.
     *
     * Called on logout to clear all user-specific state while keeping
     * server configuration fields that don't change per-user.
     *
     * Note: We intentionally preserve server config fields (authentication,
     * ui, features, regions, secret_options, diagnostics) because:
     * 1. They're set by the server at startup and don't vary by user
     * 2. Resetting them would temporarily show permissive defaults
     * 3. They get re-hydrated on full page reload anyway
     */
    resetForLogout(): void {
      // Capture current server config values before reset
      const preservedConfig = {
        authentication: this.authentication,
        ui: this.ui,
        features: this.features,
        regions: this.regions,
        secret_options: this.secret_options,
        diagnostics: this.diagnostics,
      };

      // Use built-in $reset to restore all state to DEFAULTS
      this.$reset();

      // Restore server config fields and _initialized flag
      // Use functional $patch to avoid _DeepPartial type issues
      this.$patch((state) => {
        state.authentication = preservedConfig.authentication;
        state.ui = preservedConfig.ui;
        state.features = preservedConfig.features;
        state.regions = preservedConfig.regions;
        state.secret_options = preservedConfig.secret_options;
        state.diagnostics = preservedConfig.diagnostics;
        state._initialized = true;
      });

      console.debug('[BootstrapStore.resetForLogout] Reset to defaults (server config preserved)');
    },
  },
});
