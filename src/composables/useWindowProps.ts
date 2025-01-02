// src/composables/useWindowProps.ts
import { useWindowStore } from '@/stores/windowStore';
import { OnetimeWindow } from '@/types/declarations/window';
import { computed } from 'vue';
import { z } from 'zod';

/**
 * Provides type-safe access to window properties through the window store.
 * Ensures store is initialized before access.
 *
 * @example
 *
 * const cust = useValidatedWindowProp('cust');
 *
 * // Access is type-safe
 * const customerId = computed(() => cust.value?.id);
 *
 *
 * @param {keyof OnetimeWindow} prop - Window property key
 * @returns {ComputedRef<OnetimeWindow[K] | undefined>} Typed window property
 */
export function useValidatedWindowProp<K extends keyof OnetimeWindow>(
  prop: K
) {
  const windowStore = useWindowStore();

  // Initialize store if needed
  if (!windowStore._initialized) {
    windowStore.init();
  }

  const typedProp = computed(() => windowStore[prop] as OnetimeWindow[K]);

  return typedProp;
}

export const useWindowProp = useValidatedWindowProp;

export function useWindowProps(...fields: Array<keyof OnetimeWindow>) {
  // Map each field to a validated prop
  const props = fields.map((field) => useValidatedWindowProp(field, z.any()));
  return props;
}
