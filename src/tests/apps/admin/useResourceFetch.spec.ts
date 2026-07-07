// src/tests/apps/admin/useResourceFetch.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};

vi.mock('@/shared/composables/useApi', () => ({
  useApi: () => mockApi,
}));

import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';

// A minimal single-record envelope so the composable is exercised generically
// (independent of any specific colonel resource) while running the REAL
// gracefulParse path.
const responseSchema = z.object({
  record: z.object({ id: z.string(), name: z.string() }),
  details: z.object({ count: z.number() }).optional(),
});
type Response = z.infer<typeof responseSchema>;

function makeFetcher(url: string | (() => string) = '/api/test/thing') {
  return useResourceFetch<Response>({
    url,
    schema: responseSchema,
    context: 'TestThingResponse',
  });
}

function validPayload() {
  return { record: { id: 'a', name: 'Alice' }, details: { count: 2 } };
}

describe('useResourceFetch', () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.clearAllMocks());

  describe('happy path', () => {
    it('GETs the url and exposes the validated envelope', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const r = makeFetcher();

      const result = await r.load();

      expect(mockApi.get).toHaveBeenCalledWith('/api/test/thing', undefined);
      expect(result).not.toBeNull();
      expect(r.data.value?.record.name).toBe('Alice');
      expect(r.data.value?.details?.count).toBe(2);
      expect(r.error.value).toBeNull();
      expect(r.validationError.value).toBeNull();
      expect(r.notFound.value).toBe(false);
    });

    it('resolves the url lazily from a getter (id read at load time)', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      let id = 'first';
      const r = makeFetcher(() => `/api/test/${id}`);

      await r.load();
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/test/first', undefined);

      id = 'second';
      await r.load();
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/test/second', undefined);
    });

    it('forwards query params only when provided', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const r = makeFetcher();

      await r.load({ expand: 'secrets' });

      expect(mockApi.get).toHaveBeenCalledWith('/api/test/thing', {
        params: { expand: 'secrets' },
      });
    });

    it('refresh() re-issues the last request (same params)', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const r = makeFetcher();

      await r.load({ expand: 'secrets' });
      await r.refresh();

      expect(mockApi.get).toHaveBeenCalledTimes(2);
      expect(mockApi.get).toHaveBeenLastCalledWith('/api/test/thing', {
        params: { expand: 'secrets' },
      });
    });
  });

  describe('loading state ownership', () => {
    it('flips loading true during the request and false after success', async () => {
      let loadingDuringCall = false;
      mockApi.get.mockImplementation(() => {
        loadingDuringCall = r.loading.value;
        return Promise.resolve({ data: validPayload() });
      });
      const r = makeFetcher();

      expect(r.loading.value).toBe(false);
      await r.load();

      expect(loadingDuringCall).toBe(true);
      expect(r.loading.value).toBe(false);
    });

    it('resets loading to false even after a thrown error', async () => {
      mockApi.get.mockRejectedValue(new Error('boom'));
      const r = makeFetcher();

      await expect(r.load()).rejects.toThrow('boom');
      expect(r.loading.value).toBe(false);
    });
  });

  describe('failure-mode split (validation vs network vs not-found)', () => {
    it('schema mismatch: resolves null, sets validationError, does NOT throw', async () => {
      mockApi.get.mockResolvedValue({ data: { record: { id: 1 } } });
      const r = makeFetcher();

      const result = await r.load();

      expect(result).toBeNull();
      expect(r.data.value).toBeNull();
      expect(r.validationError.value).toBe('TestThingResponse');
      expect(r.error.value).toBeNull();
      expect(r.notFound.value).toBe(false);
    });

    it('network/HTTP error: throws, sets error, leaves validationError null', async () => {
      const httpError = Object.assign(new Error('Request failed with status code 500'), {
        response: { status: 500 },
      });
      mockApi.get.mockRejectedValue(httpError);
      const r = makeFetcher();

      await expect(r.load()).rejects.toThrow('Request failed with status code 500');
      expect(r.error.value).toBe(httpError);
      expect(r.validationError.value).toBeNull();
      expect(r.notFound.value).toBe(false);
    });

    it('flags notFound on an HTTP 404 (first-class not-found state)', async () => {
      const notFound = Object.assign(new Error('Not Found'), { response: { status: 404 } });
      mockApi.get.mockRejectedValue(notFound);
      const r = makeFetcher();

      await expect(r.load()).rejects.toThrow('Not Found');
      expect(r.notFound.value).toBe(true);
      expect(r.error.value).toBe(notFound);
    });

    it('clears a prior validationError + notFound on the next successful fetch', async () => {
      const r = makeFetcher();

      mockApi.get.mockResolvedValueOnce({ data: { record: 42 } });
      await r.load();
      expect(r.validationError.value).toBe('TestThingResponse');

      mockApi.get.mockResolvedValueOnce({ data: validPayload() });
      await r.load();
      expect(r.validationError.value).toBeNull();
      expect(r.notFound.value).toBe(false);
    });
  });

  describe('reset', () => {
    it('restores data + all flags to initial values', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const r = makeFetcher();
      await r.load();
      expect(r.data.value).not.toBeNull();

      r.reset();

      expect(r.data.value).toBeNull();
      expect(r.loading.value).toBe(false);
      expect(r.error.value).toBeNull();
      expect(r.validationError.value).toBeNull();
      expect(r.notFound.value).toBe(false);
    });
  });
});
