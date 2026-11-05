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

    it('updates CSRF token from 403 CSRF-rejected response header', async () => {
      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse(
          { message: 'Forbidden' },
          { status: 403, headers: { 'x-csrf-token': 'recovered-token' } }
        )
      );

      const { submitForm, error } = createSubmission();
      await submitForm();

      // The composable surfaces the error but still refreshes the token
      // so the next submission can succeed without a page reload.
      expect(csrfStore.shrimp).toBe('recovered-token');
      expect(error.value).toBe('Forbidden');
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

    it('ignores empty x-csrf-token header', async () => {
      vi.mocked(global.fetch).mockResolvedValue(
        createMockResponse({ message: 'ok' }, {
          headers: { 'x-csrf-token': '' },
        })
      );

      const { submitForm } = createSubmission();
      await submitForm();

      // Empty header should not overwrite the existing token
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

  describe('redirect validation [L-7]', () => {
    let warnSpy: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
      vi.useFakeTimers();
      warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      vi.mocked(global.fetch).mockResolvedValue(createMockResponse({ message: 'ok' }));
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it('schedules navigation for a valid internal path', async () => {
      const { submitForm, success } = createSubmission({
        redirectUrl: '/dashboard',
        redirectDelay: 100,
      });
      await submitForm();

      expect(success.value).toBe('Done');
      // Navigation timer is scheduled for the internal path
      expect(vi.getTimerCount()).toBe(1);
      expect(warnSpy).not.toHaveBeenCalled();
    });

    it.each([
      'https://evil.example.com/phish',
      'http://evil.example.com',
      '//evil.example.com',
      'javascript:alert(1)',
      '/valid/../but%20has/a://protocol',
    ])('refuses to navigate to %s', async (redirectUrl) => {
      const { submitForm } = createSubmission({ redirectUrl, redirectDelay: 100 });
      await submitForm();

      // No navigation timer scheduled, and a warning is logged
      expect(vi.getTimerCount()).toBe(0);
      expect(warnSpy).toHaveBeenCalledWith(
        '[useFormSubmission] Ignoring non-internal redirect URL:',
        redirectUrl
      );
    });

    it('rejects an invalid redirect even when onSuccess throws', async () => {
      const redirectUrl = 'https://evil.example.com/phish';
      const { submitForm, error } = createSubmission({
        redirectUrl,
        redirectDelay: 100,
        onSuccess: () => {
          throw new Error('onSuccess blew up');
        },
      });
      await submitForm();

      // Validation ran eagerly (before the fetch/onSuccess), so the warning
      // is logged despite the throw, and no navigation timer was scheduled.
      expect(warnSpy).toHaveBeenCalledWith(
        '[useFormSubmission] Ignoring non-internal redirect URL:',
        redirectUrl
      );
      expect(vi.getTimerCount()).toBe(0);
      expect(error.value).toBe('onSuccess blew up');
    });

    it('still reports success when the redirect is refused', async () => {
      const { submitForm, success, error } = createSubmission({
        redirectUrl: '//evil.example.com',
      });
      await submitForm();

      expect(success.value).toBe('Done');
      expect(error.value).toBe('');
      expect(vi.getTimerCount()).toBe(0);
    });
  });
});
