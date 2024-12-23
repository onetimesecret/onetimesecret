// types/stores.ts
import type { ApiError } from '@/schemas/api/errors';
import { StateTree } from 'pinia';

/**
 * Base interface for stores with standardized error and loading state
 */
export interface BaseStore extends StateTree {
  isLoading: boolean;
  error: ApiError | null;
}
