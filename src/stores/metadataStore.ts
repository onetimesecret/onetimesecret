// stores/metadataStore.ts
import {
  createError,
  ErrorHandlerOptions,
  useErrorHandler,
} from '@/composables/useErrorHandler';
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
  record: Metadata | null;
  details: MetadataDetails | null;
}

export const useMetadataStore = defineStore('metadata', {
  state: (): StoreState => ({
    isLoading: false,
    record: null,
    details: null,
  }),

  getters: {
    canBurn(state: StoreState): boolean {
      if (!state.record) {
        throw createError('No state metadata record', 'technical', 'error');
      }

      // Check state validity
      const validStates = [
        METADATA_STATUS.NEW,
        METADATA_STATUS.SHARED,
        METADATA_STATUS.VIEWED,
      ] as const;

      // If record is already burned or in invalid state, not burnable
      if (
        state.record.burned ||
        !validStates.includes(state.record.state as (typeof validStates)[number])
      ) {
        return false;
      }

      return true;
    },
  },

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    _ensureErrorHandler() {
      if (!this._errorHandler) this.setupErrorHandler();
    },

    // Allow passing options during initialization
    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify, // Allow UI layer to handle notifications if provided
        log: options.log, // Allow custom logging if provided
      });
    },

    async fetch(key: string) {
      this._ensureErrorHandler();

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
        this.record = validated.record;
        this.details = validated.details;
        return validated;
      });
    },

    async burn(key: string, passphrase?: string) {
      this._ensureErrorHandler();

      if (!this.canBurn) {
        throw createError('Cannot burn this metadata', 'human', 'error');
      }

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await this._api!.post(`/api/v2/private/${key}/burn`, {
          passphrase,
          continue: true,
        });
        const validated = responseSchemas.metadata.parse(response.data);
        this.record = validated.record;
        this.details = validated.details;
        return validated;
      });
    },
  },
});
