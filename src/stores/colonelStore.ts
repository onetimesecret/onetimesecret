// stores/colonelStore.ts

import { useStoreError } from '@/composables/useStoreError';
import { responseSchemas, type ColonelData } from '@/schemas/api';
import { ApiError } from '@/schemas/api/errors';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

interface StoreState {
  isLoading: boolean;
  error: ApiError | null;
  data: ColonelData | null;
}

export const useColonelStore = defineStore('colonel', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    data: null,
  }),

  actions: {
    handleError(error: unknown): ApiError {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      return this.error;
    },

    async fetchData(): Promise<ColonelData> {
      this.isLoading = true;
      this.error = null;

      try {
        const response = await api.get('/api/v2/colonel/dashboard');
        const validated = responseSchemas.colonel.parse(response.data);
        // The record contains the ColonelData
        this.data = validated.record ?? null;
        return this.data;
      } catch (error) {
        this.handleError(error); // Update to use new handleError
        throw error; // Re-throw to maintain current behavior
      } finally {
        this.isLoading = false;
      }

      // This line is needed to satisfy TypeScript's control flow analysis
      throw new Error('Unreachable - handleApiError always throws');
    },

    dispose() {
      this.data = null;
      this.error = null;
      this.isLoading = false;
    },
  },
});
