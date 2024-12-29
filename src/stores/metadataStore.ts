// stores/metadataStore.ts
import { createError, useErrorHandler } from '@/composables/useErrorHandler';
import { ApplicationError, ErrorSeverity } from '@/schemas';
import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/endpoints';
import { responseSchemas } from '@/schemas/api/responses';
import { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { createApi } from '@/utils/api';
import { type AxiosInstance } from 'axios';
import { defineStore } from 'pinia';

export const METADATA_STATUS = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  ORPHANED: 'orphaned',
} as const;

interface StoreState {
  isLoading: boolean;
  currentRecord: Metadata | null;
  currentDetails: MetadataDetails | null;
  records: MetadataRecords[];
  details: MetadataRecordsDetails | {};
  initialized: boolean;
  count: number | null;
}

interface InitOptions {
  notify?: (message: string, severity: ErrorSeverity) => void;
  log?: (error: ApplicationError) => void;
}

export const useMetadataStore = defineStore('metadata', {
  state: (): StoreState => ({
    isLoading: false,
    currentRecord: null,
    currentDetails: null,
    records: [],
    details: {},
    initialized: false,
    count: null,
  }),

  getters: {
    recordCount: (state) => state.count,

    canBurn(state: StoreState): boolean {
      if (!state.currentRecord) {
        return false;
      }

      // Check state validity
      const validStates = [
        METADATA_STATUS.NEW,
        METADATA_STATUS.SHARED,
        METADATA_STATUS.VIEWED,
      ] as const;

      // If record is already burned or in invalid state, not burnable
      if (
        state.currentRecord.burned ||
        !validStates.includes(state.currentRecord.state as (typeof validStates)[number])
      ) {
        return false;
      }

      return true;
    },
  },

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    _ensureInitialized() {
      if (!this._errorHandler) this.init();
    },

    // Allow passing options during initialization
    init(api: AxiosInstance = createApi(), options: InitOptions = {}) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify, // Allow UI layer to handle notifications if provided
        log: options.log, // Allow custom logging if provided
      });
    },

    async fetchOne(key: string) {
      this._ensureInitialized();

      /**
       *  Wraps async operations with loading state management. A poor dude's plugin.
       *
       * Implementation Note: Originally attempted as a Pinia plugin but moved to a
       * store action due to testing challenges. The plugin approach required complex
       * setup with proper plugin initialization in tests, which introduced more
       * complexity than value. While plugins are better for cross-store
       * functionality, this simple loading pattern works fine as a store
       * action and is much easier to test.
       *
       * The original plugin implementation kept failing with "_withLoading does not
       * exist" errors in tests, likely due to plugin initialization timing issues.
       * This direct approach sidesteps those problems entirely.
       *
       */
      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.get(`/api/v2/private/${key}`);
        const validated = responseSchemas.metadata.parse(response.data);
        this.currentRecord = validated.record;
        this.currentDetails = validated.details;
        return validated;
      });
    },

    async fetchList() {
      this._ensureInitialized();

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

      this._ensureInitialized();

      return await this._errorHandler!.withErrorHandling(async () => {
        await this.fetchList();
        this.initialized = true;
      });
    },

    async burn(key: string, passphrase?: string) {
      this._ensureInitialized();

      if (!this.canBurn) {
        throw createError('Cannot burn this metadata', 'human', 'error');
      }

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.post(`/api/v2/private/${key}/burn`, {
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
});
