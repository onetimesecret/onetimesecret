// stores/metadataStore.ts

import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/endpoints';
import { handleError } from '@/schemas/api/errors'; // Remove createApiError import
import { responseSchemas } from '@/schemas/api/responses';
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { MetadataState } from '@/schemas/models/metadata';
import { createApi } from '@/utils/api';

import { createBaseStore } from './baseStore';

const api = createApi();

interface StoreState {
  currentRecord: Metadata | null;
  currentDetails: MetadataDetails | null;
  listRecords: MetadataRecords[];
  listDetails: MetadataRecordsDetails | null;
  isLoadingDetail: boolean;
  isLoadingList: boolean;
  isLoading: boolean;
  error: Error | null;
}

export const useMetadataStore = createBaseStore({
  id: 'metadata',
  state: (): StoreState => ({
    currentRecord: null as Metadata | null,
    currentDetails: null,
    listRecords: [],
    listDetails: null,
    isLoadingDetail: false,
    isLoadingList: false,
    isLoading: false,
    error: null,
  }),

  getters: {
    canBurn(state: StoreState): boolean {
      if (!state.currentRecord) return false;
      const validStates = [
        MetadataState.NEW,
        MetadataState.SHARED,
        MetadataState.VIEWED,
      ] as const;
      return (
        validStates.includes(state.currentRecord.state as (typeof validStates)[number]) &&
        !state.currentRecord.burned // this date field is only set after burning
      );
    },
  },

  actions: {
    handleError(error: unknown): never {
      const apiError = handleError(error);
      this.error = apiError;
      throw apiError;
    },

    async fetchOne(key: string) {
      return await this.withLoading(async () => {
        const response = await api.get(`/api/v2/private/${key}`);
        const validated = responseSchemas.metadata.parse(response.data);
        this.currentRecord = validated.record;
        this.currentDetails = validated.details;
        return validated;
      });
    },

    async fetchList() {
      this.isLoadingList = true;
      try {
        const response = await api.get('/api/v2/private/recent');
        const validated = responseSchemas.metadataList.parse(response.data);
        this.listRecords = validated.records;
        this.listDetails = validated.details;
        return validated;
      } catch (error) {
        this.handleError(error);
      } finally {
        this.isLoadingList = false;
      }
    },

    async burn(key: string, passphrase?: string) {
      if (!this.canBurn) {
        this.handleError(new Error('Cannot burn this metadata'));
      }

      this.isLoadingDetail = true;
      try {
        const response = await api.post(`/api/v2/private/${key}/burn`, {
          passphrase,
          continue: true,
        });
        const validated = responseSchemas.metadata.parse(response.data);
        this.currentRecord = validated.record;
        this.currentDetails = validated.details;
        return validated;
      } catch (error) {
        this.handleError(error);
      } finally {
        this.isLoadingDetail = false;
      }
    },
  },
});
