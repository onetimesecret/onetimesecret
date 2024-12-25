// src/plugins/pinia/withLoadingPlugin.ts
import type { PiniaPluginContext } from 'pinia';

/**
 * Pinia plugin that adds standardized loading state management.
 *
 * This plugin implements the loading state pattern required by PiniaCustomStateProperties,
 * providing a consistent way to handle async operations across all stores.
 *
 * Key features:
 * - Automatic loading state management
 * - Type-safe operation wrapper
 *
 */
export function withLoadingPlugin({ store }: PiniaPluginContext) {
  /**
   * Wraps an async operation with loading state management.
   *
   * @param operation - The async operation to perform
   * @returns The operation result or undefined if an error occurred
   *
   * @template T - The type of the operation result
   *
   * Design decisions:
   * 1. Sets isLoading before operation starts
   * 2. Guarantees isLoading is reset in finally block
   * 3. Allows errors to propogate up
   */
  store.withLoading = async function <T>(operation: () => Promise<T>) {
    this.isLoading = true;
    try {
      return await operation();
    } finally {
      this.isLoading = false;
    }
  };
}
