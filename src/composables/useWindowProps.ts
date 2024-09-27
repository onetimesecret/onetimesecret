import { ref, readonly, Ref, unref } from 'vue';

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

// Helper function for type safety
export const useWindowProp = <T extends keyof Window>(prop: T): Readonly<Ref<Window[T]>> => {
  if (!cache[prop]) {
    cache[prop] = ref(window[prop]);
  }
  return readonly(cache[prop] as Ref<Window[T]>);
};

// New helper function to return unref'd window props
export const useUnrefWindowProp = <T extends keyof Window>(prop: T): Window[T] => {
  const windowPropRef = useWindowProp(prop);
  return unref(windowPropRef);
};
