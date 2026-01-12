// src/services/window.service.ts

/**
 * @deprecated This service is deprecated in favor of bootstrapStore (Pinia).
 *
 * Migration guide:
 * - For reactive state access: use `useBootstrapStore()` with `storeToRefs()`
 * - For pre-Pinia access: use `getBootstrapValue()` from `bootstrap.service.ts`
 * - For state updates: use `bootstrapStore.update(data)`
 * - For state refresh: use `bootstrapStore.refresh()`
 *
 * This file will be removed in a future release.
 * See: https://github.com/onetimesecret/onetimesecret/issues/2365
 */

import type { OnetimeWindow } from '@/types/declarations/window';
import { reactive } from 'vue';

const STATE_KEY = '__ONETIME_STATE__';

/**
 * @deprecated Use bootstrapStore instead.
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * WINDOW SERVICE - REACTIVE STATE BRIDGE (DEPRECATED)
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * Provides reactive access to server-injected window state. This service is the
 * bridge between server-rendered state and Vue's reactivity system.
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * DUAL STATE ARCHITECTURE (CRITICAL)
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * State exists in TWO locations that must stay synchronized:
 *
 * 1. window.__ONETIME_STATE__
 *    - Server-injected on page load
 *    - Used by legacy code and SSR hydration
 *    - NOT reactive - changes don't trigger Vue updates
 *
 * 2. WindowService.reactiveState (internal)
 *    - Vue reactive() proxy initialized from window state
 *    - Used by computed properties (authStore.awaitingMfa, etc.)
 *    - Changes trigger Vue reactivity system
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * CRITICAL: ALWAYS USE update() FOR STATE CHANGES
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * When refreshing state from /window endpoint:
 *   ✓ WindowService.update(response.data)  - Updates BOTH locations
 *   ✗ window.__ONETIME_STATE__ = data      - Breaks reactivity!
 *
 * Direct assignment to window.__ONETIME_STATE__ does NOT update reactiveState,
 * causing computed properties to return stale values. This breaks features like
 * MFA flow where awaitingMfa must update after OTP verification.
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * AUTHENTICATION FLOW USAGE
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * The authStore uses WindowService for reactive auth state:
 *
 *   const awaitingMfa = computed(() => WindowService.get('awaiting_mfa'))
 *
 * After MFA verification:
 * 1. Server sets awaiting_mfa=false in session
 * 2. authStore.checkWindowStatus() fetches /window
 * 3. WindowService.update() syncs state to reactiveState
 * 4. awaitingMfa computed updates to false
 * 5. Route guard allows navigation away from /mfa-verify
 *
 * If step 3 uses direct assignment instead of update(), step 4 never happens
 * and the user gets stuck on the MFA page.
 */

/**
 * Internal reactive state that mirrors window.__ONETIME_STATE__.
 * This enables Vue's reactivity system to track changes when state is updated.
 */
const reactiveState = reactive<Partial<OnetimeWindow>>({});

/**
 * Initialize reactive state from window object.
 * Called once when the module loads.
 */
function initializeReactiveState(): void {
  if (typeof window !== 'undefined' && window[STATE_KEY]) {
    const windowState = window[STATE_KEY] as OnetimeWindow;
    console.debug('[WindowService.initializeReactiveState] Initializing from window state:', {
      authenticated: windowState.authenticated,
      had_valid_session: windowState.had_valid_session,
      keysCount: Object.keys(windowState).length,
    });
    Object.assign(reactiveState, window[STATE_KEY]);
  } else {
    console.debug('[WindowService.initializeReactiveState] No window state available:', {
      windowDefined: typeof window !== 'undefined',
      stateKeyExists: typeof window !== 'undefined' && !!window[STATE_KEY],
    });
  }
}

/**
 * Reset reactive state for testing.
 * Clears the reactive state and reinitializes from current window object.
 * @internal - Only for use in tests
 */
function resetReactiveState(): void {
  // Clear all keys from reactive state
  for (const key of Object.keys(reactiveState)) {
    delete reactiveState[key as keyof typeof reactiveState];
  }
  // Reinitialize from current window state
  initializeReactiveState();
}

// Initialize on module load
initializeReactiveState();

/**
 * Service for accessing typed window properties defined in window.d.ts.
 * Provides type-safe access to server-injected window properties with
 * optional default values.
 *
 * Uses Vue's reactive() internally so that computed() values automatically
 * update when state changes via update() or refresh().
 *
 * Can safely be used prior to full store hydration.
 */
export const WindowService = {
  /**
   * Retrieves a single window property with type inference.
   * Reads from reactive state for automatic reactivity, with fallback to window.
   * @param key - Property name defined in OnetimeWindow interface
   * @returns The typed window property value
   */
  get<K extends keyof OnetimeWindow>(key: K): OnetimeWindow[K] {
    const isAuthKey = key === 'authenticated' || key === 'had_valid_session';

    // Check reactive state first (for reactivity after update()/refresh())
    const reactiveValue = reactiveState[key];
    if (reactiveValue !== undefined) {
      if (isAuthKey) console.debug(`[WindowService.get] ${key} from reactiveState:`, reactiveValue);
      return reactiveValue as OnetimeWindow[K];
    }

    // Fallback to window object (for initial load and tests that set up state after module load)
    if (typeof window !== 'undefined' && window[STATE_KEY]) {
      const windowValue = (window[STATE_KEY] as OnetimeWindow)[key];
      if (windowValue !== undefined) {
        if (isAuthKey) console.debug(`[WindowService.get] ${key} from window fallback:`, windowValue);
        return windowValue;
      }
    }

    if (isAuthKey) console.debug(`[WindowService.get] ${key} is undefined`);
    return undefined as OnetimeWindow[K];
  },

  /**
   * Gets the full state object.
   * Prefers reactive state, falls back to window for backwards compatibility.
   */
  getState(): OnetimeWindow {
    if (typeof window === 'undefined') {
      throw new Error('[WindowService] Window is not defined');
    }

    // Return reactive state if initialized, otherwise window state
    if (Object.keys(reactiveState).length > 0) {
      return reactiveState as OnetimeWindow;
    }

    if (!window[STATE_KEY]) {
      throw new Error('[WindowService] State is not set');
    }

    return window[STATE_KEY] as OnetimeWindow;
  },

  /**
   * Retrieves multiple window properties with flexible input patterns.
   * Supports both default value objects and property name arrays.
   *
   * @example
   * // With defaults
   * const props = WindowService.getMultiple({
   *   authenticated: false,
   *   ot_version: ''
   * });
   *
   * @example
   * // Without defaults
   * const { regions_enabled, regions } = WindowService.getMultiple([
   *   'regions_enabled',
   *   'regions'
   * ]);
   *
   * @param input - Either an array of property names or an object with default values
   * @returns Object containing requested window properties with proper typing
   */
  getMultiple<K extends keyof OnetimeWindow>(
    input: K[] | Partial<Record<K, OnetimeWindow[K]>>
  ): Pick<OnetimeWindow, K> {
    if (Array.isArray(input)) {
      return Object.fromEntries(input.map((key) => [key, this.get(key)])) as Pick<OnetimeWindow, K>;
    }

    return Object.fromEntries(
      Object.entries(input).map(([key, defaultValue]) => [key, this.get(key as K) ?? defaultValue])
    ) as Pick<OnetimeWindow, K>;
  },

  /**
   * Updates the reactive state with new values.
   * Also syncs changes back to window.__ONETIME_STATE__ for consistency.
   *
   * @param newState - Partial state object with values to update
   */
  update(newState: Partial<OnetimeWindow>): void {
    // Update reactive state (triggers Vue reactivity)
    Object.assign(reactiveState, newState);

    // Sync to window object for consistency
    if (typeof window !== 'undefined' && window[STATE_KEY]) {
      Object.assign(window[STATE_KEY], newState);
    }
  },

  /**
   * Fetches fresh state from the /window endpoint and updates reactive state.
   * Use this after API calls that modify server-side session state.
   *
   * @returns Promise that resolves when state is refreshed
   * @throws Error if fetch fails
   */
  async refresh(): Promise<void> {
    if (typeof window === 'undefined') {
      throw new Error('[WindowService] Cannot refresh: window is not defined');
    }

    const response = await fetch('/window', {
      method: 'GET',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`[WindowService] Failed to refresh state: ${response.status}`);
    }

    const newState = (await response.json()) as OnetimeWindow;
    this.update(newState);
  },

  /**
   * Resets the reactive state for testing purposes.
   * Clears cached reactive state and reinitializes from current window object.
   * @internal - Only for use in tests
   */
  _resetForTesting: resetReactiveState,
};
