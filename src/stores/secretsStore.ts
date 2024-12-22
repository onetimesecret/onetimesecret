import { responseSchemas, type SecretResponse } from '@/schemas/api';
import { createApiError, zodErrorToApiError } from '@/schemas/api/errors';
import { type Secret, type SecretDetails } from '@/schemas/models/secret';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';
import { z } from 'zod';

const api = createApi();

interface SecretState {
  record: Secret | null;
  details: SecretDetails | null;
  isLoading: boolean;
  error: string | null;
}

export const useSecretsStore = defineStore('secrets', {
  state: (): SecretState => ({
    record: null,
    details: null,
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
        error instanceof Error ? error.message : 'Unknown error occurred'
      );
    },

    async loadSecret(secretKey: string) {
      this.isLoading = true;
      try {
        const response = await api.get(`/api/v2/secret/${secretKey}`);
        const validated = responseSchemas.secret.parse(response.data);
        this.record = validated.record;
        this.details = validated.details;
        this.error = null;
        return validated;
      } catch (error) {
        this.handleApiError(error);
      } finally {
        this.isLoading = false;
      }
    },

    async revealSecret(secretKey: string, passphrase?: string) {
      this.isLoading = true;
      try {
        const response = await api.post<SecretResponse>(
          `/api/v2/secret/${secretKey}/reveal`,
          {
            passphrase,
            continue: true,
          }
        );
        const validated = responseSchemas.secret.parse(response.data);
        this.record = validated.record;
        this.details = validated.details;
        this.error = null;
        return validated;
      } catch (error) {
        this.handleApiError(error);
      } finally {
        this.isLoading = false;
      }
    },

    clearSecret() {
      this.record = null;
      this.details = null;
      this.error = null;
    },
  },
});
