// services/window.ts
import type { OnetimeWindow } from '@/types/declarations/window';

/**
 * Service for safely accessing window properties.
 *
 * Recommended for initial page load state retrieval before reactive
 * stores are fully initialized.
 *
 * @example
 * ```typescript
 *
 *    const initialLanguage = WindowService.get('userLanguage', 'en');
 *
 *    const appConfig = WindowService.getMultiple([
 *      'appName', 'environment', 'version',
 *    ]);
 *
 * }
 * ```
 */
export const WindowService = {
  /**
   * Safely retrieves a window property with optional type casting
   * @param key Property name to retrieve from window object
   * @param defaultValue Optional fallback value if property is undefined
   * @returns Property value or default
   */
  get<K extends keyof OnetimeWindow>(
    key: K,
    defaultValue: OnetimeWindow[K]
  ): OnetimeWindow[K] {
    try {
      return window[key as keyof Window] ?? defaultValue;
    } catch {
      return defaultValue;
    }
  },

  /**
   * Checks if a window property exists
   * @param key Property name to check
   * @returns Boolean indicating property existence
   */
  has(key: keyof OnetimeWindow): boolean {
    try {
      return key in window;
    } catch {
      return false;
    }
  },

  /**
   * Retrieves multiple window properties safely
   * @param keys Array of property names to retrieve
   * @returns Object with retrieved properties
   */
  getMultiple(defaults: Partial<OnetimeWindow>): Partial<OnetimeWindow> {
    return Object.entries(defaults).reduce((acc, [key, defaultValue]) => {
      acc[key as keyof typeof defaults] = this.get(
        key as keyof OnetimeWindow,
        defaultValue
      );
      return acc;
    }, {} as Partial<OnetimeWindow>);
  },
};
