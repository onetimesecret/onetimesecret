// stores/metadataStore.ts
import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/endpoints';
import { createApiError } from '@/schemas/api/errors';
import { responseSchemas } from '@/schemas/api/responses';
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { MetadataState } from '@/schemas/models/metadata';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

interface StoreState {
  currentRecord: Metadata | null;
  currentDetails: MetadataDetails | null;
  listRecords: MetadataRecords[];
  listDetails: MetadataRecordsDetails | null;
  isLoadingDetail: boolean;
  isLoadingList: boolean;
}
export { StoreState as MetadataStoreState };

export const useMetadataStore = defineStore('metadata', {
  state: (): StoreState => ({
    currentRecord: null,
    currentDetails: null,
    listRecords: [],
    listDetails: null,
    isLoadingDetail: false,
    isLoadingList: false,
  }),

  getters: {
    canBurn: (state): boolean => {
      if (!state.currentRecord) return false;
      return (
        [MetadataState.NEW, MetadataState.SHARED, MetadataState.VIEWED].includes(
          state.currentRecord.state
        ) && !state.currentRecord.is_burned
      );
    },
  },

  actions: {
    async fetchOne(key: string) {
      this.isLoadingDetail = true;
      try {
        const response = await api.get(`/api/v2/private/${key}`);
        const validated = responseSchemas.metadata.parse(response.data);
        this.currentRecord = validated.record;
        this.currentDetails = validated.details;
      } catch (error) {
        if (error instanceof Error && 'status' in error && error.status === 404) {
          throw createApiError('NOT_FOUND', 'NOT_FOUND', 'Metadata not found');
        }
        throw createApiError(
          'SERVER',
          'SERVER_ERROR',
          error instanceof Error ? error.message : 'Failed to fetch metadata'
        );
      } finally {
        this.isLoadingDetail = false;
      }
    },

    async fetchList() {
      this.isLoadingList = true;
      try {
        const response = await api.get('/api/v2/private/recent');
        const validated = responseSchemas.metadataList.parse(response.data);
        this.listRecords = validated.records;
        this.listDetails = validated.details;
      } catch (error) {
        throw createApiError(
          'SERVER',
          'SERVER_ERROR',
          error instanceof Error ? error.message : 'Failed to fetch metadata list'
        );
      } finally {
        this.isLoadingList = false;
      }
    },

    async burn(key: string, passphrase?: string) {
      if (!this.canBurn) {
        throw createApiError('VALIDATION', 'VALIDATION_ERROR', 'Cannot burn this metadata');
      }

      try {
        const response = await api.post(`/api/v2/private/${key}/burn`, {
          passphrase,
          continue: true,
        });
        const validated = responseSchemas.metadata.parse(response.data);
        this.currentRecord = validated.record;
        this.currentDetails = validated.details;
      } catch (error) {
        throw createApiError(
          'SERVER',
          'SERVER_ERROR',
          error instanceof Error ? error.message : 'Failed to burn metadata'
        );
      }
    },
  },
});
