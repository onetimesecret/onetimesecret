import { responseSchemas, type ColonelData } from '@/schemas/api';
import { createApiError, zodErrorToApiError } from '@/schemas/api/errors';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';
import { z } from 'zod';

const api = createApi();

interface ColonelStoreState {
  data: ColonelData | null;
  isLoading: boolean;
  error: string | null;
}

export const useColonelStore = defineStore('colonel', {
  state: (): ColonelStoreState => ({
    data: null,
    isLoading: false,
    error: null,
  }),

  actions: {
    handleApiError(error: unknown): never {
      if (error instanceof z.ZodError) {
        throw zodErrorToApiError(error);
      }
      throw createApiError(
        'SERVER',
        'SERVER_ERROR',
        error instanceof Error ? error.message : 'Error fetching colonel data'
      );
    },

    async fetchData(): Promise<ColonelData> {
      this.isLoading = true;
      this.error = null;

      try {
        const response = await api.get('/api/v2/colonel/dashboard');
        const validated = responseSchemas.colonel.parse(response.data);
        // The record contains the ColonelData
        this.data = validated.record;
        return this.data;
      } catch (error) {
        this.handleApiError(error);
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
