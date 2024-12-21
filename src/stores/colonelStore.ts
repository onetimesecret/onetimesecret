import { colonelDataSchema, colonelDataResponseSchema, type ColonelData } from '@/schemas/models/colonel';
import type { ApiRecordResponse } from '@/types/api/responses';
import { createApi } from '@/utils/api';
import { isTransformError, transformResponse } from '@/utils/transforms';
import axios from 'axios';
import { defineStore } from 'pinia';
import type { ZodIssue } from 'zod';

const api = createApi();

interface ColonelStoreState {
  data: ColonelData | null;
  isLoading: boolean;
  error: string | null;
}

/**
 * Store for colonel (admin) dashboard data
 * - Uses shared ColonelData type with components
 * - Handles API transformation at edges only
 * - Centralizes error handling
 */
export const useColonelStore = defineStore('colonel', {
  state: (): ColonelStoreState => ({
    data: null,
    isLoading: false,
    error: null
  }),

  actions: {
    /**
     * Centralized error handler for API errors
     */
    handleApiError(error: unknown): never {
      if (axios.isAxiosError(error)) {
        const serverMessage = error.response?.data?.message || error.message;
        console.error('API Error:', serverMessage);
        this.error = serverMessage;
        throw new Error(serverMessage);
      } else if (isTransformError(error)) {
        console.error('Data Validation Error:', formatErrorDetails(error.details));
        this.error = 'Data validation failed';
        throw new Error('Data validation failed');
      } else if (error instanceof Error) {
        console.error('Unexpected Error:', error.message);
        this.error = error.message;
        throw new Error(error.message);
      } else {
        console.error('Unexpected Error:', error);
        this.error = 'An unexpected error occurred';
        throw new Error('An unexpected error occurred');
      }
    },

    /**
     * Fetches colonel dashboard data
     */
    async fetchData() {
      this.isLoading = true;
      this.error = null;

      try {
        const response = await api.get<ApiRecordResponse<ColonelData>>('/api/v2/colonel/dashboard');

        const validated = transformResponse(
          colonelDataResponseSchema,
          response.data
        );

        this.data = colonelDataSchema.parse(validated.record);
        return this.data;

      } catch (error) {
        this.handleApiError(error);
      } finally {
        this.isLoading = false;
      }
    },

    /**
     * Clears store state
     */
    dispose() {
      this.data = null;
      this.error = null;
      this.isLoading = false;
    }
  }
});

// Helper function to safely format error details
function formatErrorDetails(details: ZodIssue[] | string): string | Record<string, string> {
  if (typeof details === 'string') {
    return details;
  }

  return details.reduce((acc, issue) => {
    const path = issue.path.join('.');
    acc[path] = issue.message;
    return acc;
  }, {} as Record<string, string>);
}
