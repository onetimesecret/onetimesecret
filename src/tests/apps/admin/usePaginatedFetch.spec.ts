// src/tests/apps/admin/usePaginatedFetch.spec.ts

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

import {
  usePaginatedFetch,
  DEFAULT_PER_PAGE,
} from '@/apps/admin/composables/usePaginatedFetch';

// A minimal, self-contained response schema so the composable is exercised
// generically (independent of any specific colonel resource) while still
// running the REAL gracefulParse path.
const itemSchema = z.object({ id: z.string() });
const responseSchema = z.object({
  items: z.array(itemSchema),
  pagination: z.object({
    page: z.number(),
    per_page: z.number(),
    total_count: z.number(),
    total_pages: z.number(),
  }),
});
type Response = z.infer<typeof responseSchema>;
type Item = z.infer<typeof itemSchema>;

function makePager(perPage?: number) {
  return usePaginatedFetch<Response, Item>({
    url: '/api/test/things',
    schema: responseSchema,
    context: 'TestThingsResponse',
    select: (data) => ({ items: data.items, pagination: data.pagination }),
    perPage,
  });
}

function validPayload(overrides: Partial<Response['pagination']> = {}) {
  return {
    items: [{ id: 'a' }, { id: 'b' }],
    pagination: {
      page: 1,
      per_page: DEFAULT_PER_PAGE,
      total_count: 2,
      total_pages: 1,
      ...overrides,
    },
  };
}

describe('usePaginatedFetch', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('happy path', () => {
    it('fetches ONE server page and maps items + pagination via select', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const pager = makePager();

      const result = await pager.fetchPage(1);

      expect(result).not.toBeNull();
      expect(result!.items).toEqual([{ id: 'a' }, { id: 'b' }]);
      expect(result!.pagination).toEqual({
        page: 1,
        per_page: DEFAULT_PER_PAGE,
        total_count: 2,
        total_pages: 1,
      });
    });

    it('requests page + per_page as query params (server-paginated, not client-sliced)', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const pager = makePager(25);

      await pager.fetchPage(3);

      expect(mockApi.get).toHaveBeenCalledTimes(1);
      expect(mockApi.get).toHaveBeenCalledWith('/api/test/things', {
        params: { page: 3, per_page: 25 },
      });
    });

    it('merges extra filter params and drops empty/nullish ones', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const pager = makePager();

      await pager.fetchPage(1, { role: 'colonel', status: '', extra: undefined, cursor: null });

      expect(mockApi.get).toHaveBeenCalledWith('/api/test/things', {
        params: { page: 1, per_page: DEFAULT_PER_PAGE, role: 'colonel' },
      });
    });

    it('reconciles page/perPage from the server-echoed pagination', async () => {
      mockApi.get.mockResolvedValue({
        data: validPayload({ page: 2, per_page: 10, total_pages: 5 }),
      });
      const pager = makePager();

      await pager.fetchPage(2);

      expect(pager.page.value).toBe(2);
      expect(pager.perPage.value).toBe(10);
    });

    it('defaults targetPage to the current page ref when omitted', async () => {
      mockApi.get.mockResolvedValue({ data: validPayload() });
      const pager = makePager();
      pager.page.value = 4;

      await pager.fetchPage();

      expect(mockApi.get).toHaveBeenCalledWith('/api/test/things', {
        params: { page: 4, per_page: DEFAULT_PER_PAGE },
      });
    });
  });

  describe('loading state ownership', () => {
    it('flips loading true during the request and false after success', async () => {
      let loadingDuringCall = false;
      mockApi.get.mockImplementation(() => {
        loadingDuringCall = pager.loading.value;
        return Promise.resolve({ data: validPayload() });
      });
      const pager = makePager();

      expect(pager.loading.value).toBe(false);
      await pager.fetchPage(1);

      expect(loadingDuringCall).toBe(true);
      expect(pager.loading.value).toBe(false);
    });

    it('resets loading to false even after a thrown error', async () => {
      mockApi.get.mockRejectedValue(new Error('boom'));
      const pager = makePager();

      await expect(pager.fetchPage(1)).rejects.toThrow('boom');
      expect(pager.loading.value).toBe(false);
    });
  });

  describe('failure-mode split (validation vs network)', () => {
    it('schema mismatch: resolves null, sets validationError, does NOT throw', async () => {
      mockApi.get.mockResolvedValue({ data: { items: 'not-an-array', pagination: {} } });
      const pager = makePager();

      const result = await pager.fetchPage(1);

      expect(result).toBeNull();
      expect(pager.validationError.value).toBe('TestThingsResponse');
      expect(pager.error.value).toBeNull();
    });

    it('network/HTTP error: throws, sets error, leaves validationError null', async () => {
      const httpError = new Error('Request failed with status code 500');
      mockApi.get.mockRejectedValue(httpError);
      const pager = makePager();

      await expect(pager.fetchPage(1)).rejects.toThrow('Request failed with status code 500');
      expect(pager.error.value).toBe(httpError);
      expect(pager.validationError.value).toBeNull();
    });

    it('clears a prior validationError on the next successful fetch', async () => {
      const pager = makePager();

      mockApi.get.mockResolvedValueOnce({ data: { items: 42 } });
      await pager.fetchPage(1);
      expect(pager.validationError.value).toBe('TestThingsResponse');

      mockApi.get.mockResolvedValueOnce({ data: validPayload() });
      await pager.fetchPage(1);
      expect(pager.validationError.value).toBeNull();
    });
  });

  describe('reset', () => {
    it('restores loading/error/validationError/page/perPage to initial values', async () => {
      mockApi.get.mockResolvedValue({
        data: validPayload({ page: 3, per_page: 10 }),
      });
      const pager = makePager();
      await pager.fetchPage(3);
      expect(pager.page.value).toBe(3);
      expect(pager.perPage.value).toBe(10);

      pager.reset();

      expect(pager.loading.value).toBe(false);
      expect(pager.error.value).toBeNull();
      expect(pager.validationError.value).toBeNull();
      expect(pager.page.value).toBe(1);
      expect(pager.perPage.value).toBe(DEFAULT_PER_PAGE);
    });
  });
});
