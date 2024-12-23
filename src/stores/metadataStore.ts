// stores/metadataStore.ts
import { useStoreError } from '@/composables/useStoreError';
import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/endpoints';
import { ApiError } from '@/schemas/api/errors';
import { responseSchemas } from '@/schemas/api/responses';
import { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

// Define valid states as a value (not just a type)
export const METADATA_STATUS = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  ORPHANED: 'orphaned',
} as const;

interface StoreState {
  // Base properties still needed in interface
  isLoading: boolean;
  error: ApiError | null;
  // No longer needs to extend BaseStore as those fields are global
  currentRecord: Metadata | null;
  currentDetails: MetadataDetails | null;
  listRecords: MetadataRecords[];
  listDetails: MetadataRecordsDetails | null;
  isLoadingDetail: boolean;
  isLoadingList: boolean;
}

export const useMetadataStore = defineStore('metadata', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    currentRecord: null as Metadata | null,
    currentDetails: null,
    listRecords: [],
    listDetails: null,
    isLoadingDetail: false,
    isLoadingList: false,
  }),

  getters: {
    canBurn(state: StoreState): boolean {
      if (!state.currentRecord) return false;
      const validStates = [
        METADATA_STATUS.NEW,
        METADATA_STATUS.SHARED,
        METADATA_STATUS.VIEWED,
      ] as const;
      return (
        validStates.includes(state.currentRecord.state as (typeof validStates)[number]) &&
        !state.currentRecord.burned
      );
    },
  },

  actions: {
    handleError(error: unknown): ApiError {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      return this.error;
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
