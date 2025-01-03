// services/window.ts

interface WindowProperties {
  [key: string]: any;
}

/**
 * Service for safely accessing window properties.
 *
 * Recommended for initial page load state retrieval before reactive
 * stores are fully initialized.
 *
 * @example
 * ```typescript
 *
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
  get<T = any>(key: string, defaultValue?: T): T | undefined {
    try {
      return typeof window !== 'undefined'
        ? ((window as any)[key] ?? defaultValue)
        : defaultValue;
    } catch {
      return defaultValue;
    }
  },

  /**
   * Checks if a window property exists
   * @param key Property name to check
   * @returns Boolean indicating property existence
   */
  has(key: string): boolean {
    try {
      return typeof window !== 'undefined' && key in window;
    } catch {
      return false;
    }
  },

  /**
   * Retrieves multiple window properties safely
   * @param keys Array of property names to retrieve
   * @returns Object with retrieved properties
   */
  getMultiple(keys: string[]): WindowProperties {
    return keys.reduce((acc, key) => {
      acc[key] = this.get(key);
      return acc;
    }, {} as WindowProperties);
  },
};
