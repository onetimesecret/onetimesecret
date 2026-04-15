// src/types/ui/vue-internals.ts

/**
 * Minimal type for Vue component instance properties we access.
 * These are Vue internals, not public API - structure may vary by version.
 *
 * Used by getComponentName() in globalErrorBoundary.ts to extract
 * component names for Sentry context without using `any`.
 *
 * @see https://github.com/vuejs/core/blob/main/packages/runtime-core/src/component.ts
 */
export interface VueComponentLike {
  /** Options API: component name from defineComponent({ name: '...' }) */
  $options?: { name?: string };
  /** Vue 3 internal instance, exposed on public proxy */
  $?: {
    /** Component type definition */
    type?: {
      /** Explicit name property */
      name?: string;
      /** SFC compiled name (set by vue-loader/vite-plugin-vue) */
      __name?: string;
    };
  };
}
