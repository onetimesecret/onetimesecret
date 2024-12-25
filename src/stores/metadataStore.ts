// stores/metadataStore.ts
import { useErrorHandler } from '@/composables/useErrorHandler';
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
  // Base properties required for all stores
  isLoading: boolean;
  error: ApiError | null;
  // Metadata-specific properties
  currentRecord: Metadata | null;
  currentDetails: MetadataDetails | null;
  records: MetadataRecords[];
  details: MetadataRecordsDetails | null;
  initialized: boolean;
}

export const useMetadataStore = defineStore('metadata', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    currentRecord: null as Metadata | null,
    currentDetails: null,
    records: [],
    details: null,
    initialized: false,
  }),

  getters: {
    recordCount: (state) => state.records.length,

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
      const { handleError } = useErrorHandler();
      this.error = handleError(error);
      return this.error;
    },

    setData(data: { record: Metadata | null; details: MetadataDetails | null }) {
      this.currentRecord = data.record;
      this.currentDetails = data.details;
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
      return await this.withLoading(async () => {
        const response = await api.get('/api/v2/private/recent');
        const validated = responseSchemas.metadataList.parse(response.data);
        this.records = validated.records;
        this.details = validated.details;
        return validated;
      });
    },

    async refreshRecords() {
      if (this.initialized) return; // prevent repeated calls when 0 domains
      return await this.withLoading(async () => {
        this.fetchList();
        this.initialized = true;
      });
    },

    async burn(key: string, passphrase?: string) {
      if (!this.canBurn) {
        this.handleError(new Error('Cannot burn this metadata'));
      }

      return await this.withLoading(async () => {
        const response = await api.post(`/api/v2/private/${key}/burn`, {
          passphrase,
          continue: true,
        });
        const validated = responseSchemas.metadata.parse(response.data);
        this.currentRecord = validated.record;
        this.currentDetails = validated.details;
        return validated;
      });
    },
  },

  hydrate(store) {
    store.refreshRecords();
  }
});
