import type { ColonelData } from '@/schemas/api/endpoints/colonel';
import { zodErrorToDomainError } from '@/schemas/api/errors';
import { responseSchemas, type ColonelResponse } from '@/schemas/api/responses';
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
    async fetchData(): Promise<ColonelData | null> {
      this.isLoading = true;
      this.error = null;

      try {
        const response = await api.get<ColonelResponse>('/api/v2/colonel/dashboard');
        const validated = responseSchemas.colonel.parse(response.data);
        this.data = validated.record;
        return this.data;
      } catch (error) {
        if (error instanceof z.ZodError) {
          const domainError = zodErrorToDomainError(error);
          this.error = domainError.message;
          throw error;
        }
        this.error = error instanceof Error ? error.message : 'Unknown error';
        throw error;
      } finally {
        this.isLoading = false;
      }
    },

    dispose() {
      this.data = null;
      this.error = null;
      this.isLoading = false;
    },
  },
});
