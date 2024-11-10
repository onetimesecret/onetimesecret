// src/stores/metadataStore.ts
import {
  type Metadata,
  type MetadataData,
  type MetadataDetails,
  metadataDataSchema
} from '@/schemas/models/metadata';
import {
  type ApiRecordResponse,
  type ApiRecordsResponse,
  apiRecordResponseSchema,
  apiRecordsResponseSchema
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
}

export const useMetadataStore = defineStore('metadata', {
  state: (): MetadataStoreState => ({
    cache: new Map(),
    records: [],
    currentRecord: null,
    details: null,
    isLoading: false,
    error: null
  }),

  getters: {
    getByKey: (state) => (key: string) => state.cache.get(key),
    isDestroyed: (state) => state.currentRecord?.state === 'received' ||
                           state.currentRecord?.state === 'burned',
    canBurn: (state) => state.currentRecord?.state === 'new'
  },

  actions: {
    abortController: null as AbortController | null,

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
      this.error = null;

      try {
        const response = await api.get<ApiRecordsResponse<MetadataData>>('/api/v2/private/recent', {
          signal: this.abortController.signal
        });

        const validated = transformResponse(
          apiRecordsResponseSchema(metadataDataSchema),
          response.data
        );

        const transformedRecords = validated.records.map(record => ({
          ...record,
          created: record.created,
          updated: record.updated,
          state: 'new',
          received: false,
          show_recipients: false,
          stamp: record.expiration_stamp,
          uri: record.metadata_path,
          is_received: false,
          is_burned: false,
          is_destroyed: false,
          custid: '',
          secret_ttl: 0,
          passphrase: '',
          viewed: false,
          shared: false,
          burned: false,
          truncate: false
        })) satisfies Metadata[];

        transformedRecords.forEach(record => {
          this.cache.set(record.key, record);
        });
        this.records = transformedRecords;

        return validated;

      } catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
          console.debug('Metadata list fetch aborted');
          return;
        }
        this.handleError(error);
        throw error;

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
      this.error = null;

      try {
        const response = await api.get<ApiRecordResponse<MetadataData>>(`/api/v2/private/${key}`, {
          signal: bypassCache ? this.abortController?.signal : undefined
        });

        const validated = transformResponse(
          apiRecordResponseSchema(metadataDataSchema),
          response.data
        );

        const transformedRecord = {
          ...validated.record,
          created: validated.record.created,
          updated: validated.record.updated,
          state: 'new',
          received: false,
          show_recipients: false,
          stamp: validated.record.expiration_stamp,
          uri: validated.record.metadata_path,
          is_received: false,
          is_burned: false,
          is_destroyed: false,
          custid: '',
          secret_ttl: 0,
          passphrase: '',
          viewed: false,
          shared: false,
          burned: false,
          truncate: false
        } satisfies Metadata;

        this.cache.set(key, transformedRecord);
        this.currentRecord = transformedRecord;
        this.details = validated.details as MetadataDetails;

        return {
          record: transformedRecord,
          details: this.details
        };

      } catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
          console.debug('Metadata fetch aborted');
          return;
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
        throw new Error('Cannot burn metadata in current state');
      }

      this.isLoading = true;
      this.error = null;

      try {
        const response = await api.post<ApiRecordResponse<MetadataData>>(
          `/api/v2/private/${key}/burn`,
          { passphrase, continue: true }
        );

        const validated = transformResponse(
          apiRecordResponseSchema(metadataDataSchema),
          response.data
        );

        const transformedRecord = {
          ...validated.record,
          created: validated.record.created,
          updated: validated.record.updated,
          state: 'burned',
          received: false,
          show_recipients: false,
          stamp: validated.record.expiration_stamp,
          uri: validated.record.metadata_path,
          is_received: false,
          is_burned: true,
          is_destroyed: true,
          custid: '',
          secret_ttl: 0,
          passphrase: '',
          viewed: true,
          shared: false,
          burned: true,
          truncate: false
        } satisfies Metadata;

        this.clearRecord(key);
        this.currentRecord = transformedRecord;
        this.details = validated.details as MetadataDetails;
        this.records = this.records.map(r =>
          r.key === key ? transformedRecord : r
        );

        return {
          record: transformedRecord,
          details: this.details
        };

      } catch (error) {
        this.handleError(error);
        throw error;
      } finally {
        this.isLoading = false;
      }
    },

    updateState(key: string, newState: 'new' | 'received' | 'burned') {
      const record = this.cache.get(key) || this.currentRecord;
      if (record && record.state !== newState) {
        this.clearRecord(key);

        const updated = {
          ...record,
          state: newState,
          is_received: newState === 'received',
          is_burned: newState === 'burned',
          is_destroyed: newState === 'burned',
          received: newState === 'received',
          burned: newState === 'burned'
        } satisfies Metadata;

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
        this.error = 'Invalid server response';
      } else {
        this.error = error instanceof Error ? error.message : 'An unexpected error occurred';
      }
    }
  }
});

function formatErrorDetails(details: string | ZodIssue[]): unknown {
  return Array.isArray(details)
    ? details.map(detail => ({
        path: detail.path,
        code: detail.code,
        message: detail.message
      }))
    : details;
}
