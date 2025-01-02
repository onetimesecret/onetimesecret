import type { ErrorHandler } from '@/composables/useErrorHandler';
import type { AxiosInstance } from 'axios';
import 'pinia';

/**
 * Store Architecture & Error Handling
 *
 * Our stores directly handle both state management and API calls because:
 * 1. Single Source of Truth - stores ARE our service layer
 * 2. Schema Integration - Zod handles validation and typing
 * 3. Practical Benefits - no artificial abstraction layers
 *
 * Error Handling Pattern:
 * 1. Stores - focus on data operations, let errors propagate up
 * 2. Composables - handle errors, notifications, and user feedback
 * 3. Components - use composables for error handling
 *
 * This architecture provides:
 * - Clear boundaries between API and store state
 * - Natural type safety flow from schema to UI
 * - Focused, testable code with clear responsibilities
 */

declare module 'pinia' {
  /**
   *  Required reactive state properties that stores must include in their `state()`.
   */
  export interface PiniaCustomProperties {
    $api: AxiosInstance;
    $errorHandler: ErrorHandler;
    $logout: () => void;
    $reset: () => void;
  }

  /**
   * Required state properties for all stores.
   * Each store must implement:
   * - isLoading: to indicate async operation status
   *
   * @example
   * ```ts
   * interface StoreState {
   *   isLoading: boolean;
   *   // Store-specific state...
   * }
   * ```
   */
  export interface PiniaCustomStateProperties {
    isLoading: boolean;
  }
}

/**
 * Example store implementation:
 *
 *      export const useExampleStore = defineStore('example', {
 *        state: () => ({
 *          isLoading: false,
 *          error: null as ApiError | null,
 *          // other state...
 *        }),
 *
 *        actions: {
 *          handleError(error: unknown): ApiError {
 *            const { handleError } = useErrorHandler();
 *            this.error = handleError(error);
 *            return this.error;
 *          },
 *
 *          async someAction() {
 *            this.isLoading = true;
 *            try {
 *              // do something
 *            } catch (error) {
 *              this.handleError(error);
 *            } finally {
 *              this.isLoading = false;
 *            }
 *          }
 *        }
 *      });
 *
 */
