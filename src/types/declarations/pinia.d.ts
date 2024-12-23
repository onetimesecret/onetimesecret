import type { ApiError } from '@/schemas/api/errors';

declare module 'pinia' {
  /**
   *  Required reactive state properties that stores must include in their `state()`.
   */
  export interface PiniaCustomProperties {
    $logout: () => void;
    handleError: (error: unknown) => ApiError;
  }

  /**
   * Required state properties for all stores.
   * Each store must implement:
   * - isLoading: to indicate async operation status
   * - error: to maintain error state
   *
   * @example
   * ```ts
   * interface StoreState {
   *   isLoading: boolean;
   *   error: ApiError | null;
   *   // Store-specific state...
   * }
   * ```
   */
  export interface PiniaCustomStateProperties {
    isLoading: boolean;
    error: ApiError | null;
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
 *            const { handleError } = useStoreError();
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
