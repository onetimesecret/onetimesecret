// src/services/window.service.ts
import type { OnetimeWindow } from '@/types/declarations/window';

/**
 * Service for accessing window properties prior to store initialization.
 *
 * Use this service to retrieve properties from the global window object
 * with type safety and default values. Recommended for initial page load
 * state retrieval before reactive stores are fully available.
 */
export const WindowService = {
  /**
   * Retrieves a window property with an optional default value.
   * @param key - The property name to retrieve from the window object.
   * @param defaultValue - A fallback value if the property is undefined.
   * @returns The property value or the default.
   */
  get<K extends keyof OnetimeWindow>(
    key: K,
    defaultValue: OnetimeWindow[K]
  ): OnetimeWindow[K] {
    return (window as OnetimeWindow)[key] ?? defaultValue;
  },

  /**
   * Retrieves multiple window properties safely.
   * @param defaults - An object with keys as property names and values as default values.
   * @returns An object containing the retrieved properties.
   */
  getMultiple<T extends Partial<OnetimeWindow>>(defaults: T): T {
    const result = {} as T;
    for (const key in defaults) {
      result[key] = this.get(key as keyof OnetimeWindow, defaults[key]);
    }
    return result;
  },
};
