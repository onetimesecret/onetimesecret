/**
 * Application error type definitions using interfaces rather than classes.
 * This approach aligns with Vue 3's composition API patterns and ecosystem by:
 * - Favoring plain objects and composable functions over classes
 * - Maintaining flexibility for API error responses
 * - Matching type patterns used by Vue tooling (Pinia, Router, etc)
 */
export type ErrorType = 'technical' | 'business' | 'security';
export type ErrorSeverity = 'error' | 'warning' | 'info';

export interface ApplicationError extends Error {
  type: ErrorType;
  severity: ErrorSeverity;
  code?: string;
  details?: Record<string, unknown>;
}

// interface-based approach is better for Vue 3 apps. If type checking is needed, we can use type predicates:
export function isApplicationError(error: unknown): error is ApplicationError {
  return error instanceof Error && 'type' in error && 'severity' in error;
}

/**
 * Type predicates are TypeScript's way of doing custom type checks. Here's a
 * practical example:
 *
 * ```typescript
 * // Type predicate has this specific syntax:
 * // parameterName is Type
 * function isApplicationError(error: unknown): error is ApplicationError {
 *   return error instanceof Error &&
 *          'type' in error &&
 *          'severity' in error;
 * }
 *
 * // Usage:
 * function handleError(error: unknown) {
 *   if (isApplicationError(error)) {
 *     // TypeScript now KNOWS error is ApplicationError
 *     console.log(error.severity)  // ✅ TypeScript allows this
 *     console.log(error.type)      // ✅ TypeScript allows this
 *   } else {
 *     // TypeScript knows error is just unknown here
 *     console.log(error.severity)  // ❌ TypeScript error
 *   }
 * }
 * ```
 *
 * The predicate tells TypeScript "if this function returns true, you can treat
 * the parameter as this type". It's safer than type casting and provides better
 * type inference in the rest of your code.
 *
 * This is particularly useful in Vue 3 apps where errors might come from various
 * sources (API calls, user interactions, etc.) and need type-safe handling.
 */
