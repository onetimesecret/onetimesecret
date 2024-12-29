// stores/metadataListStore.ts
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/endpoints';
import { responseSchemas } from '@/schemas/api/responses';
import { createApi } from '@/utils/api';
import { type AxiosInstance } from 'axios';
import { defineStore } from 'pinia';

interface StoreState {
  isLoading: boolean;
  records: MetadataRecords[] | null;
  details: MetadataRecordsDetails | null;
  initialized: boolean;
  count: number | null;
}

export const useMetadataListStore = defineStore('metadataList', {
  state: (): StoreState => ({
    isLoading: false,
    records: null,
    details: null,
    initialized: false,
    count: null,
  }),

  getters: {
    recordCount: (state) => state.count,
  },

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    _ensureErrorHandler() {
      if (!this._errorHandler) this.setupErrorHandler();
    },

    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify,
        log: options.log,
      });
    },

    async fetchList() {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.get('/api/v2/private/recent');
        const validated = responseSchemas.metadataList.parse(response.data);

        this.records = validated.records ?? [];
        this.details = validated.details ?? {};
        this.count = validated.count ?? 0;

        return validated;
      });
    },

    async refreshRecords() {
      if (this.initialized) return;

      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        await this.fetchList();
        this.initialized = true;
      });
    },
  },
});
