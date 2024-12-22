import {
  apiRecordsResponseSchema,
  metadataRecordResponseSchema,
  type ApiRecordsResponse,
  type MetadataRecordApiResponse,
} from '@/schemas/api/responses';
import {
  MetadataState,
  isMetadataDetails,
  isMetadataRecordsDetails,
  metadataDetailsSchema,
  metadataRecordsSchema,
  metadataSchema,
  type Metadata,
  type MetadataDetailsUnion,
  type MetadataRecords,
} from '@/schemas/models/metadata';
import { createApi } from '@/utils/api';
import { isTransformError, transformResponse } from '@/utils/transforms';
import { defineStore } from 'pinia';
import type { ZodIssue } from 'zod';

const api = createApi();

interface MetadataStoreState {
  cache: Map<string, MetadataRecords | Metadata>;
  records: MetadataRecords[];
  currentRecord: Metadata | null;
  details: MetadataDetailsUnion | null;
  isLoading: boolean;
  error: string | null;
  abortController: AbortController | null;
}

// Helper to ensure type safety when checking states
const allowedBurnStates = [MetadataState.NEW, MetadataState.SHARED, MetadataState.VIEWED] as const;

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
    isDestroyed: (state): boolean => {
      if (!state.currentRecord) return false;
      if (
        state.currentRecord.state === MetadataState.RECEIVED ||
        state.currentRecord.state === MetadataState.BURNED
      ) {
        return true;
      }
      if (state.details) {
        if (isMetadataDetails(state.details)) {
          return state.details.is_destroyed;
        }
        if (isMetadataRecordsDetails(state.details)) {
          return state.details.received.some((r) => r.key === state.currentRecord?.key);
        }
      }
      return false;
    },
    canBurn: (state) => {
      return (
        state.currentRecord &&
        allowedBurnStates.includes(
          state.currentRecord.state as (typeof allowedBurnStates)[number]
        ) &&
        !state.isDestroyed
      );
    },
  },

  actions: {
    setData(response: MetadataRecordApiResponse) {
      const validated = transformResponse(metadataRecordResponseSchema, response);
      this.currentRecord = metadataSchema.parse(validated.record);
      if (validated.details) {
        this.details = metadataDetailsSchema.parse(validated.details);
      } else {
        this.details = null;
      }
    },

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

      try {
        const response = await api.get<ApiRecordsResponse<MetadataRecords>>(
          '/api/v2/private/recent',
          {
            signal: this.abortController.signal,
          }
        );

        const validated = transformResponse(
          apiRecordsResponseSchema(metadataRecordsSchema),
          response.data
        );

        this.records = validated.records.map((record) => metadataRecordsSchema.parse(record));
        if (validated.details) {
          this.details = metadataDetailsSchema.parse(validated.details);
        } else {
          this.details = null;
        }

        // Cache management - store list items
        validated.records.forEach((record) => {
          const parsed = metadataRecordsSchema.parse(record);
          this.cache.set(parsed.key, parsed);
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
      const cached = this.cache.get(key);
      if (!bypassCache && cached) {
        // If we have a cached record, use it but still fetch in background
        this.currentRecord = cached as Metadata;
        if (!bypassCache) {
          this.fetchOne(key, true).catch(console.error);
        }
        return {
          record: cached,
          details: this.details,
        };
      }

      if (bypassCache) {
        this.abortPendingRequests();
        this.abortController = new AbortController();
      }

      this.isLoading = true;

      try {
        const response = await api.get<MetadataRecordApiResponse>(`/api/v2/private/${key}`, {
          signal: bypassCache ? this.abortController?.signal : undefined,
        });

        const validated = transformResponse(metadataRecordResponseSchema, response.data);

        if (validated.record) {
          const parsed = metadataSchema.parse(validated.record);
          this.cache.set(key, parsed);
          this.currentRecord = parsed;
        }
        if (validated.details) {
          this.details = metadataDetailsSchema.parse(validated.details);
        } else {
          this.details = null;
        }

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
        const response = await api.post<MetadataRecordApiResponse>(`/api/v2/private/${key}/burn`, {
          passphrase,
          continue: true,
        });

        const validated = transformResponse(metadataRecordResponseSchema, response.data);

        if (validated.record) {
          this.clearRecord(key);
          const parsed = metadataSchema.parse(validated.record);
          this.currentRecord = parsed;
          if (validated.details) {
            this.details = metadataDetailsSchema.parse(validated.details);
          } else {
            this.details = null;
          }

          // Update the record in the list if it exists
          this.records = this.records.map((r) =>
            r.key === key ? { ...r, state: parsed.state } : r
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
      const record = this.cache.get(key);
      if (record && record.state !== newState) {
        this.clearRecord(key);

        const updated = { ...record, state: newState };
        if (record === this.currentRecord) {
          this.currentRecord = updated as Metadata;
        }

        // Update the record in the list if it exists
        this.records = this.records.map((r) => (r.key === key ? { ...r, state: newState } : r));
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
          rawData: error.data,
        });
      }
      this.error = error instanceof Error ? error.message : 'Unknown error';
    },
  },
});

function formatErrorDetails(details: ZodIssue[] | string): string | Record<string, string> {
  if (typeof details === 'string') {
    return details;
  }

  return details.reduce(
    (acc, issue) => {
      const path = issue.path.join('.');
      acc[path] = issue.message;
      return acc;
    },
    {} as Record<string, string>
  );
}
