// src/tests/composables/useFormSubmission.spec.ts

import { useFormSubmission } from '@/shared/composables/useFormSubmission';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

/**
 * Creates a mock Response with configurable headers and JSON body.
 */
function createMockResponse(
  body: Record<string, unknown>,
  options: { status?: number; headers?: Record<string, string> } = {}
): Response {
  const { status = 200, headers = {} } = options;
  const headersObj = new Headers(headers);
  headersObj.set('content-type', 'application/json');

  return {
    ok: status >= 200 && status < 300,
    status,
    headers: headersObj,
    json: () => Promise.resolve(body),
  } as Response;
}

describe('useFormSubmission', () => {
  let csrfStore: ReturnType<typeof useCsrfStore>;
  const testUrl = '/api/v2/test';
  const testSchema = z.object({ message: z.string() }).passthrough();

  beforeEach(() => {
    csrfStore = useCsrfStore();
    csrfStore.init();
    csrfStore.updateShrimp('initial-shrimp-token');

    // Reset fetch mock before each test
    vi.mocked(global.fetch).mockReset();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  /**
   * Helper to create a composable instance with standard options.
   */
  function createSubmission(overrides: Record<string, unknown> = {}) {
    return useFormSubmission({
      url: testUrl,
      successMessage: 'Done',
      schema: testSchema,
      getFormData: () => new URLSearchParams({ field: 'value' }),
      ...overrides,
    });
  }

  describe('CSRF token in request', () => {
    it('sends CSRF token in X-CSRF-Token header', async () => {
      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse({ message: 'ok' }, {
          headers: { 'x-csrf-token': 'new-token' },
        })
      );

      const { submitForm } = createSubmission();
      await submitForm();

      const [, fetchInit] = vi.mocked(global.fetch).mock.calls[0];
      const headers = fetchInit?.headers as Record<string, string>;
      expect(headers['X-CSRF-Token']).toBe('initial-shrimp-token');
    });

    it('sends shrimp in form body', async () => {
      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse({ message: 'ok' })
      );

      const { submitForm } = createSubmission();
      await submitForm();

      const [, fetchInit] = vi.mocked(global.fetch).mock.calls[0];
      const body = new URLSearchParams(fetchInit?.body as string);
      expect(body.get('shrimp')).toBe('initial-shrimp-token');
    });
  });

  describe('CSRF token refresh from response header', () => {
    it('updates CSRF token from success response header', async () => {
      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse({ message: 'ok' }, {
          headers: { 'x-csrf-token': 'refreshed-token' },
        })
      );

      const { submitForm } = createSubmission();
      await submitForm();

      expect(csrfStore.shrimp).toBe('refreshed-token');
    });

    it('updates CSRF token from error response header', async () => {
      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse(
          { message: 'Bad request' },
          { status: 400, headers: { 'x-csrf-token': 'error-refreshed-token' } }
        )
      );

      const { submitForm } = createSubmission();
      await submitForm();

      expect(csrfStore.shrimp).toBe('error-refreshed-token');
    });

    it('handles missing x-csrf-token header gracefully', async () => {
      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse({ message: 'ok' })
      );

      const { submitForm } = createSubmission();
      await submitForm();

      // Token stays at initial value when no header present
      expect(csrfStore.shrimp).toBe('initial-shrimp-token');
    });
  });

  describe('backward compatibility: shrimp in JSON body', () => {
    it('updates shrimp from JSON response body', async () => {
      const responseSchema = z.object({
        message: z.string(),
        shrimp: z.string(),
      });

      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse({ message: 'ok', shrimp: 'body-shrimp-token' })
      );

      const { submitForm } = createSubmission({ schema: responseSchema });
      await submitForm();

      // JSON body shrimp overwrites header shrimp (it runs after)
      expect(csrfStore.shrimp).toBe('body-shrimp-token');
    });

    it('header token is applied even when JSON body also has shrimp', async () => {
      const responseSchema = z.object({
        message: z.string(),
        shrimp: z.string(),
      });

      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse(
          { message: 'ok', shrimp: 'body-token' },
          { headers: { 'x-csrf-token': 'header-token' } }
        )
      );

      const { submitForm } = createSubmission({ schema: responseSchema });
      await submitForm();

      // Body shrimp runs after header refresh, so body wins
      expect(csrfStore.shrimp).toBe('body-token');
    });
  });
});
