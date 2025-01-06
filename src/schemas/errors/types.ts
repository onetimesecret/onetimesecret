/**
 * Application error type definitions using interfaces rather than classes.
 * This approach aligns with Vue 3's composition API patterns and ecosystem by:
 * - Favoring plain objects and composable functions over classes
 * - Maintaining flexibility for API error responses
 * - Matching type patterns used by Vue tooling (Pinia, Router, etc)
 */
export type ErrorType = 'technical' | 'human' | 'security';
export type ErrorSeverity = 'error' | 'warning' | 'info';

/**
 * Intended to supplement Vue 3's built-in error handling with a structured errorl
 * object that can be passed between components and services.l
 *
 *   Vue 3's Built-in Error Handling:
 *   ```ts
 *   // Vue's error handling hierarchy
 *   app.config.errorHandler = (err, instance, info) => {
 *     // Global error handler
 *   }
 *
 *   // Component-level error handling
 *   onErrorCaptured((err, instance, info) => {
 *     // Handle error in component tree
 *     return false // prevent error propagation
 *   })
 *   ```
 *
 */

export interface ApplicationError extends Error {
  type: ErrorType;
  severity: ErrorSeverity;
  code?: string;
  details?: Record<string, unknown>;
}

export function createApplicationError(
  message: string,
  type: ErrorType = 'technical',
  severity: ErrorSeverity = 'error',
  code?: string,
  details?: Record<string, unknown>
): ApplicationError {
  const error = Object.assign(new Error(message), {
    name: 'ApplicationError',
    type,
    severity,
    code,
    details,
  });

  Error.captureStackTrace(error, createApplicationError);
  return error as ApplicationError;
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
