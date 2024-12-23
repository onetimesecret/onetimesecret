import { useStoreError } from '@/composables/useStoreError';
import { ApiError } from '@/schemas';
import { responseSchemas, type SecretResponse } from '@/schemas/api';
import { type Secret, type SecretDetails } from '@/schemas/models/secret';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

interface StoreState {
  isLoading: boolean;
  error: ApiError | null;
  record: Secret | null;
  details: SecretDetails | null;
}

export const useSecretsStore = defineStore('secrets', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    record: null,
    details: null,
  }),

  actions: {
    handleError(error: unknown): ApiError {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      return this.error;
    },

    async loadSecret(secretKey: string) {
      return await this.withLoading(async () => {
        const response = await api.get(`/api/v2/secret/${secretKey}`);
        const validated = responseSchemas.secret.parse(response.data);
        this.record = validated.record;
        this.details = validated.details;
        this.error = null;
        return validated;
      });
    },

    async revealSecret(secretKey: string, passphrase?: string) {
      return await this.withLoading(async () => {
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
      });
    },

    clearSecret() {
      this.record = null;
      this.details = null;
      this.error = null;
    },
  },
});
