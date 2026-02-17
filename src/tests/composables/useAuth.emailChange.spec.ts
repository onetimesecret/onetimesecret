// src/tests/composables/useAuth.emailChange.spec.ts

/**
 * Tests for email change methods in useAuth composable.
 *
 * These tests verify that requestEmailChange() and confirmEmailChange():
 * 1. Make correct API calls with expected payloads
 * 2. Validate responses through Zod schemas
 * 3. Handle success responses correctly
 * 4. Handle error responses (field errors, server errors)
 * 5. Handle network failures gracefully
 */

import { useAuth } from '@/shared/composables/useAuth';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useRoute, useRouter } from 'vue-router';
import { getRouter } from 'vue-router-mock';
import { setupTestPinia } from '../setup';

// Mock vue-router
vi.mock('vue-router');

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
    locale: { value: 'en' },
  }),
}));

// Mock logging service
vi.mock('@/services/logging.service', () => ({
  loggingService: {
    debug: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

describe('useAuth - Email Change', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    // Wire up vue-router mocks
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue({ query: {} } as any);

    // Set up CSRF store with a shrimp token
    const csrfStore = useCsrfStore();
    csrfStore.shrimp = 'test-shrimp';
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  describe('requestEmailChange', () => {
    it('returns true on successful request', async () => {
      axiosMock
        .onPost('/api/account/change-email')
        .reply(200, { sent: true });

      const { requestEmailChange } = useAuth();
      const result = await requestEmailChange('new@example.com', 'password123');

      expect(result).toBe(true);
    });

    it('sends correct payload with new_email, password, shrimp, and locale', async () => {
      axiosMock
        .onPost('/api/account/change-email')
        .reply(200, { sent: true });

      const { requestEmailChange } = useAuth();
      await requestEmailChange('new@example.com', 'mypassword');

      const requestData = JSON.parse(axiosMock.history.post[0].data);
      expect(requestData.new_email).toBe('new@example.com');
      expect(requestData.password).toBe('mypassword');
      expect(requestData.shrimp).toBe('test-shrimp');
      expect(requestData.locale).toBe('en');
    });

    it('returns false when server returns error response', async () => {
      axiosMock
        .onPost('/api/account/change-email')
        .reply(200, { error: 'Current password is incorrect' });

      const { requestEmailChange, error } = useAuth();
      const result = await requestEmailChange('new@example.com', 'wrongpass');

      expect(result).toBe(false);
      expect(error.value).toBe('Current password is incorrect');
    });

    it('populates fieldError from field-error tuple', async () => {
      axiosMock
        .onPost('/api/account/change-email')
        .reply(200, {
          error: 'Validation failed',
          'field-error': ['new_email', 'is not a valid email'],
        });

      const { requestEmailChange, fieldError } = useAuth();
      await requestEmailChange('bad-email', 'password123');

      expect(fieldError.value).toEqual(['new_email', 'is not a valid email']);
    });

    it('returns false on network error', async () => {
      axiosMock
        .onPost('/api/account/change-email')
        .networkError();

      const { requestEmailChange } = useAuth();
      const result = await requestEmailChange('new@example.com', 'password123');

      expect(result).toBe(false);
    });

    it('returns false on server 500 error', async () => {
      axiosMock
        .onPost('/api/account/change-email')
        .reply(500, { error: 'Internal server error' });

      const { requestEmailChange } = useAuth();
      const result = await requestEmailChange('new@example.com', 'password123');

      expect(result).toBe(false);
    });

    it('clears previous errors before making request', async () => {
      // First call fails
      axiosMock
        .onPost('/api/account/change-email')
        .replyOnce(200, { error: 'First error' });

      const { requestEmailChange, error } = useAuth();
      await requestEmailChange('new@example.com', 'wrong');
      expect(error.value).toBe('First error');

      // Second call succeeds - error should be cleared
      axiosMock
        .onPost('/api/account/change-email')
        .replyOnce(200, { sent: true });

      await requestEmailChange('new@example.com', 'correct');
      expect(error.value).toBeNull();
    });

    it('handles sent: false response as success (no error)', async () => {
      axiosMock
        .onPost('/api/account/change-email')
        .reply(200, { sent: false });

      const { requestEmailChange, error } = useAuth();
      const result = await requestEmailChange('new@example.com', 'password123');

      // sent: false passes schema validation and is not an error response
      expect(result).toBe(true);
      expect(error.value).toBeNull();
    });
  });

  describe('confirmEmailChange', () => {
    it('returns true on successful confirmation', async () => {
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .reply(200, { confirmed: true, redirect: '/signin' });

      const { confirmEmailChange } = useAuth();
      const result = await confirmEmailChange('valid-token-123');

      expect(result).toBe(true);
    });

    it('sends correct payload with token and shrimp', async () => {
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .reply(200, { confirmed: true, redirect: '/signin' });

      const { confirmEmailChange } = useAuth();
      await confirmEmailChange('my-token');

      const requestData = JSON.parse(axiosMock.history.post[0].data);
      expect(requestData.token).toBe('my-token');
      expect(requestData.shrimp).toBe('test-shrimp');
    });

    it('returns false when server returns error response', async () => {
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .reply(200, { error: 'This link has expired' });

      const { confirmEmailChange, error } = useAuth();
      const result = await confirmEmailChange('expired-token');

      expect(result).toBe(false);
      expect(error.value).toBe('This link has expired');
    });

    it('returns false on network error', async () => {
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .networkError();

      const { confirmEmailChange } = useAuth();
      const result = await confirmEmailChange('some-token');

      expect(result).toBe(false);
    });

    it('returns false on server 500 error', async () => {
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .reply(500, { error: 'Internal server error' });

      const { confirmEmailChange } = useAuth();
      const result = await confirmEmailChange('some-token');

      expect(result).toBe(false);
    });

    it('handles error with field-error tuple', async () => {
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .reply(200, {
          error: 'Invalid token',
          'field-error': ['token', 'has expired'],
        });

      const { confirmEmailChange, error } = useAuth();
      const result = await confirmEmailChange('bad-token');

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid token');
    });

    it('clears previous errors before making request', async () => {
      // First call fails
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .replyOnce(200, { error: 'Token expired' });

      const { confirmEmailChange, error } = useAuth();
      await confirmEmailChange('expired');
      expect(error.value).toBe('Token expired');

      // Second call succeeds
      axiosMock
        .onPost('/api/account/confirm-email-change')
        .replyOnce(200, { confirmed: true, redirect: '/signin' });

      await confirmEmailChange('valid');
      expect(error.value).toBeNull();
    });
  });
});
