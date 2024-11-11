// src/stores/metadataStore.ts
import {
  metadataInputSchema,
  metadataListInputSchema,
  MetadataState,
  type Metadata,
  type MetadataDetails
} from '@/schemas/models/metadata';
import {
  apiRecordResponseSchema,
  apiRecordsResponseSchema,
  type ApiRecordResponse,
  type ApiRecordsResponse
} from '@/types/api/responses';
import { createApi } from '@/utils/api';
import { isTransformError, transformResponse } from '@/utils/transforms';
import { defineStore } from 'pinia';
import type { ZodIssue } from 'zod';

const api = createApi();

interface MetadataStoreState {
  cache: Map<string, Metadata>;
  records: Metadata[];
  currentRecord: Metadata | null;
  details: MetadataDetails | null;
  isLoading: boolean;
  error: string | null;
  abortController: AbortController | null,
}

export const useMetadataStore = defineStore('metadata', {
  state: (): MetadataStoreState => ({
    cache: new Map(),
    records: [],
    currentRecord: null,
    details: null,
    isLoading: false,
    error: null,
    abortController: null,
  }),

  getters: {
    getByKey: (state) => (key: string) => state.cache.get(key),
    isDestroyed: (state) => state.currentRecord?.state === MetadataState.RECEIVED ||
                           state.currentRecord?.state === MetadataState.BURNED,
    canBurn: (state) => {
      // Can burn if:
      // 1. Record exists
      // 2. State is NEW, VIEWED or SHARED
      // 3. Not already destroyed
      return state.currentRecord &&
             [MetadataState.NEW, MetadataState.SHARED, MetadataState.VIEWED].includes(state.currentRecord.state) &&
             !state.details?.is_destroyed;
    }
  },

  actions: {
    // Abort controller should be declared as instance property


    abortPendingRequests() {
      if (this.abortController) {
        this.abortController.abort();
        this.abortController = null;
        this.isLoading = false;
      }
    },

    async fetchList() {
      this.abortPendingRequests();
      this.abortController = new AbortController();
      this.isLoading = true;
      let response; // Declare outside try block to access in catch

      try {
        response = await api.get<ApiRecordsResponse<Metadata>>('/api/v2/private/recent', {
          signal: this.abortController.signal
        });

        const validated = transformResponse(
          apiRecordsResponseSchema(metadataListInputSchema),
          response.data
        );

        // Store records in both cache and records array
        this.records = validated.records;
        this.details = validated.details || null;

        validated.records.forEach(record => {
          this.cache.set(record.key, record);
        });

        return validated;


      } catch (error) {
        // Add validation error details
        if (error instanceof Error) {
          console.error('Validation error:', {
            name: error.name,
            message: error.message,
            data: response?.data
          });
        }
        this.handleError(error);
        //throw error;
      } finally {
        this.isLoading = false;
        this.abortController = null;
      }
    },

    async fetchOne(key: string, bypassCache = false) {
      if (!bypassCache && this.cache.has(key)) {
        return {
          record: this.cache.get(key)!,
          details: this.details
        };
      }

      if (bypassCache) {
        this.abortPendingRequests();
        this.abortController = new AbortController();
      }

      this.isLoading = true;

      try {
        const response = await api.get<ApiRecordResponse<Metadata>>(`/api/v2/private/${key}`, {
          signal: bypassCache ? this.abortController?.signal : undefined
        });

        const validated = transformResponse(
          apiRecordResponseSchema(metadataInputSchema),
          response.data
        );

        this.cache.set(key, validated.record);
        this.currentRecord = validated.record;
        this.details = validated.details;

        return validated;

      } catch (error) {
        if (error instanceof Error) {
          if ('status' in error && error.status === 404) {
            this.currentRecord = null;
            this.details = null;
            this.error = 'Record not found';
            return null;
          }
          if (error.name === 'AbortError') {
            console.debug('Metadata fetch aborted');
            return;
          }
        }
        this.handleError(error);
        throw error;

      } finally {
        if (bypassCache) {
          this.abortController = null;
        }
        this.isLoading = false;
      }
    },

    async burnMetadata(key: string, passphrase?: string) {
      if (!this.canBurn) {
        throw new Error(`Cannot burn metadata in current state (${this.currentRecord?.state})`);
      }

      this.isLoading = true;

      try {
        const response = await api.post<ApiRecordResponse<Metadata>>(
          `/api/v2/private/${key}/burn`,
          { passphrase, continue: true }
        );

        const validated = transformResponse(
          apiRecordResponseSchema(metadataInputSchema),
          response.data
        );

        this.clearRecord(key);
        this.currentRecord = validated.record;
        this.details = validated.details;
        this.records = this.records.map(r =>
          r.key === key ? validated.record : r
        );

        return validated;

      } catch (error) {
        this.handleError(error);
        throw error;
      } finally {
        this.isLoading = false;
      }
    },

    updateState(key: string, newState: 'new' | 'received' | 'burned' | 'viewed') {
      const record = this.cache.get(key) || this.currentRecord;
      if (record && record.state !== newState) {
        this.clearRecord(key);

        const updated = { ...record, state: newState };
        if (record === this.currentRecord) {
          this.currentRecord = updated;
        }

        this.records = this.records.map(r =>
          r.key === key ? updated : r
        );
      }
    },

    clearRecord(key: string) {
      this.cache.delete(key);
      if (this.currentRecord?.key === key) {
        this.currentRecord = null;
      }
    },

    clearCache(keysToKeep?: string[]) {
      if (!keysToKeep) {
        this.cache.clear();
      } else {
        for (const [key] of this.cache) {
          if (!keysToKeep.includes(key)) {
            this.cache.delete(key);
          }
        }
      }
    },

    dispose() {
      this.abortPendingRequests();
      this.clearCache();
      this.currentRecord = null;
      this.details = null;
      this.records = [];
      this.error = null;
    },

    handleError(error: unknown) {
      if (isTransformError(error)) {
        console.error('Metadata validation failed:', {
          error: 'TRANSFORM_ERROR',
          details: formatErrorDetails(error.details),
          rawData: error.data
        });
      }
      throw error;
    }
  }
});

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
