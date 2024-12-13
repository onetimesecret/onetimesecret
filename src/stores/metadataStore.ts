// src/stores/metadataStore.ts
import {
  MetadataState,
  metadataListInputSchema,
  type Metadata,
  type MetadataDetails,
  type MetadataList
} from '@/schemas/models/metadata';
import {
  metadataRecordResponseSchema,
  apiRecordsResponseSchema,
  type ApiRecordsResponse,
  type MetadataRecordApiResponse
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
  abortController: AbortController | null;
}

// Helper to ensure type safety when checking states
const allowedBurnStates = [
  MetadataState.NEW,
  MetadataState.SHARED,
  MetadataState.VIEWED
] as const;

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
    isDestroyed: (state) => {
      if (!state.currentRecord) return false;
      return state.currentRecord.state === MetadataState.RECEIVED ||
             state.currentRecord.state === MetadataState.BURNED;
    },
    canBurn: (state) => {
      // Can burn if:
      // 1. Record exists
      // 2. State is NEW, VIEWED or SHARED
      // 3. Not already destroyed
      return state.currentRecord &&
             allowedBurnStates.includes(state.currentRecord.state as typeof allowedBurnStates[number]) &&
             !state.details?.is_destroyed;
    }
  },

  actions: {
    setData(response: MetadataRecordApiResponse) {
      this.currentRecord = response.record;
      this.details = response.details ?? null;
    },

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
        response = await api.get<ApiRecordsResponse<MetadataList>>('/api/v2/private/recent', {
          signal: this.abortController.signal
        });

        let validated;
        try {
          validated = transformResponse(
            apiRecordsResponseSchema(metadataListInputSchema),
            response.data
          );
        } catch (e) {
          // On validation error, try to extract what we can
          console.error('Validation error in fetchList:', e);
          validated = {
            records: response.data?.records || [],
            details: null
          };
        }

        // Convert list records to full metadata records
        const fullRecords = validated.records.map(record => ({
          ...record,
          created_date_utc: new Date().toISOString(), // Default value
          expiration_stamp: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(), // 24h from now
          share_path: `/share/${record.shortkey}`,
          burn_path: `/burn/${record.shortkey}`,
          metadata_path: `/metadata/${record.shortkey}`,
          share_url: `${window.location.origin}/share/${record.shortkey}`,
          metadata_url: `${window.location.origin}/metadata/${record.shortkey}`,
          burn_url: `${window.location.origin}/burn/${record.shortkey}`,
        })) as Metadata[];

        // Store records in both cache and records array
        this.records = fullRecords;
        this.details = null; // List view doesn't have details

        fullRecords.forEach(record => {
          this.cache.set(record.key, record);
        });

        return validated;

      } catch (error) {
        this.handleError(error);
        return null;
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
        const response = await api.get<MetadataRecordApiResponse>(`/api/v2/private/${key}`, {
          signal: bypassCache ? this.abortController?.signal : undefined
        });

        let validated;
        try {
          validated = transformResponse(
            metadataRecordResponseSchema,
            response.data
          );
        } catch (e) {
          // On validation error, try to extract what we can
          console.error('Validation error in fetchOne:', e);
          validated = {
            record: response.data?.record,
            details: null
          };
        }

        if (validated.record) {
          this.cache.set(key, validated.record);
          this.currentRecord = validated.record;
        }
        this.details = validated.details ?? null;

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
        return null;

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
        const response = await api.post<MetadataRecordApiResponse>(
          `/api/v2/private/${key}/burn`,
          { passphrase, continue: true }
        );

        let validated;
        try {
          validated = transformResponse(
            metadataRecordResponseSchema,
            response.data
          );
        } catch (e) {
          console.error('Validation error in burnMetadata:', e);
          validated = {
            record: response.data?.record,
            details: null
          };
        }

        if (validated.record) {
          this.clearRecord(key);
          this.currentRecord = validated.record;
          this.details = validated.details ?? null;
          this.records = this.records.map(r =>
            r.key === key ? validated.record : r
          );
        }

        return validated;

      } catch (error) {
        this.handleError(error);
        return null;
      } finally {
        this.isLoading = false;
      }
    },

    updateState(key: string, newState: Metadata['state']) {
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
      this.error = error instanceof Error ? error.message : 'Unknown error';
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
