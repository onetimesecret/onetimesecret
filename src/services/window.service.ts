// src/services/window.service.ts

import type { OnetimeWindow } from '@/types/declarations/window';
import { reactive } from 'vue';

const STATE_KEY = '__ONETIME_STATE__';

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
    Object.assign(reactiveState, window[STATE_KEY]);
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
    // Check reactive state first (for reactivity after update()/refresh())
    const reactiveValue = reactiveState[key];
    if (reactiveValue !== undefined) {
      return reactiveValue as OnetimeWindow[K];
    }

    // Fallback to window object (for initial load and tests that set up state after module load)
    if (typeof window !== 'undefined' && window[STATE_KEY]) {
      const windowValue = (window[STATE_KEY] as OnetimeWindow)[key];
      if (windowValue !== undefined) {
        return windowValue;
      }
    }

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
