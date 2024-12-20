import { ref, readonly, Ref, unref, shallowRef } from 'vue';
import { z } from 'zod';

/**
 * With this caching mechanism:

1. The first time a property is requested, a new ref is created and stored in the `cache` object.
2. Subsequent calls for the same property will return the cached ref.
3. This ensures that only one ref is created per window property, regardless of how many components use it.

This approach is more efficient in terms of memory usage and ensures consistency across your application. All components using the same window property will share the same ref, so they'll all update together if the underlying window property changes.

To summarize:
- The original implementation recreates refs each time it's called.
- This improved, cached version creates refs only once and reuses them across all calls.

The cached version is generally the better choice for most applications, as it optimizes memory usage and ensures consistency across your app.
**/

const cache: Partial<Record<keyof Window, Ref<Window[keyof Window]>>> = {};

export const useWindowProps = <T extends keyof Window>(props: T[]): { [K in T]: Readonly<Ref<Window[K]>> } => {
  const result: Partial<Record<T, Readonly<Ref<Window[T]>>>> = {};

  props.forEach((prop) => {
    if (!cache[prop]) {
      cache[prop] = ref(window[prop]);
    }
    result[prop] = readonly(cache[prop] as Ref<Window[T]>);
  });

  return result as { [K in T]: Readonly<Ref<Window[K]>> };
};

// Helper function
export const useWindowProp = <T extends keyof Window>(prop: T): Readonly<Ref<Window[T]>> => {
  if (!cache[prop]) {
    cache[prop] = ref(window[prop]);
  }
  return readonly(cache[prop] as Ref<Window[T]>);
};

/**
 * Validates and transforms a window property using a Zod schema.
 *
 * @description
 * When the window property contains data that needs transformation (like the customer object),
 * there can be a race condition between:
 * 1. Initial component rendering
 * 2. Schema validation and transformation
 * 3. Cache population
 *
 * Timeline:
 * ```
 * T0: Component starts mounting
 * T1: Template rendering begins with raw window data
 * T2: useValidatedWindowProp called
 * T3: Schema validation/transformation occurs
 * T4: Transformed data cached
 * ```
 *
 * During this process (particularly between T1-T4), the data might be:
 * - Undefined (not yet validated)
 * - Raw (pre-transformation)
 * - Transformed (post-validation)
 *
 * Best practices:
 * - Always use optional chaining (?.) when accessing transformed properties
 * - Provide fallback values using nullish coalescing (??)
 * - Consider v-if/v-show for template sections that depend on transformed data
 *
 * @example
 * ```vue
 * const cust = useValidatedWindowProp('cust', customerInputSchema);
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
 * @template T - Window property key
 * @template Input - Schema input type
 * @template Output - Schema output type
 * @param {T} prop - Window property key
 * @param {z.ZodType<Output, z.ZodTypeDef, Input>} schema - Zod schema for validation/transformation
 * @returns {Ref<Output | null>} Validated and transformed data as a Vue ref
 */
export const useValidatedWindowProp = <
  T extends keyof Window,
  Input,
  Output
>(
  prop: T,
  schema: z.ZodType<Output, z.ZodTypeDef, Input>
): Ref<Output | null> => {
  if (!cache[prop]) {
    const value = window[prop] as unknown;
    try {
      const parsedValue = schema.parse(value);
      cache[prop] = shallowRef(parsedValue);
    } catch (error) {
      console.error('Failed to validate window property:', error);
      cache[prop] = shallowRef(null);
    }
  }
  return cache[prop] as Ref<Output | null>;
};
