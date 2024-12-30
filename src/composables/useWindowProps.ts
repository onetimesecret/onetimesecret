// src/composables/useWindowProps.ts
import { useWindowStore } from '@/stores/windowStore';
import { OnetimeWindow } from '@/types/declarations/window';
import { computed } from 'vue';
import { z, ZodType } from 'zod';

/**
 * Validates and transforms a window property using a Zod schema.
 *
 * @description
 * This composable accesses the window property through the window store and applies
 * validation and transformation using the provided Zod schema.
 *
 * @example
 * ```vue
 * const cust = useValidatedWindowProp('cust', customerSchema);
 *
 * // In template
 * <div v-if="cust?.feature_flags?.homepage_toggle">
 *   {{ cust.feature_flags.homepage_toggle }}
 * </div>
 *
 * // In script
 * const showFeature = computed(() => cust.value?.feature_flags?.homepage_toggle ?? false);
 * ```
 *
 * @template T - The type inferred from the schema
 * @param {keyof OnetimeWindow} prop - Window property key
 * @param {z.ZodType<T>} schema - Zod schema for validation/transformation
 * @returns {ComputedRef<T | null>} Validated and transformed data as a computed ref
 */
export function useValidatedWindowProp<T>(prop: keyof OnetimeWindow, schema: ZodType<T>) {
  const windowStore = useWindowStore();

  const validatedProp = computed(() => {
    const value = windowStore[prop] as unknown;
    const result = schema.safeParse(value);

    if (result.success) {
      return result.data;
    } else {
      console.error(`Failed to validate window property '${prop}':`, result.error);
      return null;
    }
  });

  return validatedProp;
}
