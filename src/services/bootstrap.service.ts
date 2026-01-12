// src/services/bootstrap.service.ts

import type { OnetimeWindow } from '@/types/declarations/window';

/**
 * Bootstrap Service - Pre-Pinia State Access
 *
 * This service provides access to server-injected window state BEFORE Pinia
 * is installed. It is used by early-initialization code that runs before
 * the Vue app and Pinia are fully set up.
 *
 * Lifecycle:
 * 1. Server injects state into window.__BOOTSTRAP_STATE__
 * 2. consumeBootstrapData() reads and deletes it (prevents memory leaks)
 * 3. getBootstrapValue() provides key access during initialization
 * 4. bootstrapStore.init() hydrates from getBootstrapSnapshot()
 * 5. After init, all access goes through bootstrapStore
 *
 * Consumers (pre-Pinia):
 * - i18n.ts (lines 141-145): locale, supported_locales, fallback_locale
 * - appInitializer.ts (lines 43-46): diagnostics, d9s_enabled, display_domain
 */

const BOOTSTRAP_KEY = '__BOOTSTRAP_STATE__' as const;

// Internal storage after consumption
let bootstrapSnapshot: Partial<OnetimeWindow> | null = null;
let consumed = false;

/**
 * Reads window.__BOOTSTRAP_STATE__, stores it internally, and deletes
 * the window property to prevent memory leaks and signal consumption.
 *
 * This function should be called once during app initialization, before
 * Pinia is installed but after the DOM is ready.
 *
 * @returns The bootstrap data snapshot, or null if already consumed or unavailable
 */
export function consumeBootstrapData(): Partial<OnetimeWindow> | null {
  if (consumed) {
    console.debug('[BootstrapService] Data already consumed');
    return bootstrapSnapshot;
  }

  if (typeof window === 'undefined') {
    console.debug('[BootstrapService] Window not defined (SSR?)');
    consumed = true;
    return null;
  }

  const windowWithState = window as Window & { [BOOTSTRAP_KEY]?: OnetimeWindow };
  const state = windowWithState[BOOTSTRAP_KEY];

  if (!state) {
    console.debug('[BootstrapService] No bootstrap state found on window');
    consumed = true;
    return null;
  }

  // Store snapshot and replace with marker (true = consumed successfully)
  // This allows memory to be reclaimed while preserving a testable marker
  bootstrapSnapshot = { ...state };
  (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY] = true;
  consumed = true;

  console.debug('[BootstrapService] Consumed bootstrap data:', {
    authenticated: bootstrapSnapshot.authenticated,
    locale: bootstrapSnapshot.locale,
    keysCount: Object.keys(bootstrapSnapshot).length,
  });

  return bootstrapSnapshot;
}

/**
 * Gets a single value from bootstrap state.
 * Works both before and after consumption.
 *
 * Pre-consumption: reads from window.__BOOTSTRAP_STATE__
 * Post-consumption: reads from internal snapshot
 *
 * @param key - The OnetimeWindow property to retrieve
 * @returns The value or undefined if not found
 */
export function getBootstrapValue<K extends keyof OnetimeWindow>(
  key: K
): OnetimeWindow[K] | undefined {
  // If already consumed, use snapshot
  if (consumed && bootstrapSnapshot) {
    return bootstrapSnapshot[key] as OnetimeWindow[K] | undefined;
  }

  // Pre-consumption: read directly from window
  if (typeof window !== 'undefined') {
    const windowWithState = window as Window & { [BOOTSTRAP_KEY]?: OnetimeWindow };
    const state = windowWithState[BOOTSTRAP_KEY];
    if (state) {
      return state[key];
    }
  }

  return undefined;
}

/**
 * Gets the full bootstrap snapshot for Pinia store hydration.
 * Call this during bootstrapStore.init() to get all values at once.
 *
 * If data hasn't been consumed yet, this will consume it first.
 *
 * @returns The full bootstrap data snapshot, or null if unavailable
 */
export function getBootstrapSnapshot(): Partial<OnetimeWindow> | null {
  if (!consumed) {
    return consumeBootstrapData();
  }
  return bootstrapSnapshot;
}

/**
 * Checks if bootstrap data has been consumed.
 * Useful for debugging and conditional initialization logic.
 */
export function isBootstrapConsumed(): boolean {
  return consumed;
}

/**
 * Resets the bootstrap service state.
 * Only for use in tests to allow re-consumption.
 *
 * @internal
 */
export function _resetForTesting(): void {
  bootstrapSnapshot = null;
  consumed = false;
}

/**
 * Bootstrap Service object for organized access.
 * Provides the same functions as named exports in an object form.
 */
export const BootstrapService = {
  consume: consumeBootstrapData,
  get: getBootstrapValue,
  getSnapshot: getBootstrapSnapshot,
  isConsumed: isBootstrapConsumed,
  _resetForTesting,
};
