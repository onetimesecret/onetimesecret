// src/tests/plugins/axios/interceptors.rejection.spec.ts
//
// #4460: a rejected API call REQUESTS reconciliation through the refresh
// coordinator. No API error handler writes authentication state directly.

import type { AxiosError, InternalAxiosRequestConfig } from 'axios';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const { touched, noteApiRejection } = vi.hoisted(() => ({
  touched: [] as string[],
  noteApiRejection: vi.fn(),
}));

// Every member the interceptor reaches for on the auth store is recorded, so
// "it only ever calls noteApiRejection" is asserted rather than assumed.
vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: () =>
    new Proxy(
      {},
      {
        get: (_target, member: string) => {
          touched.push(member);
          return member === 'noteApiRejection' ? noteApiRejection : vi.fn();
        },
        set: (_target, member: string) => {
          touched.push(`set:${member}`);
          return true;
        },
      }
    ),
}));

vi.mock('@sentry/vue', () => ({ addBreadcrumb: vi.fn() }));
vi.mock('@/shared/stores/csrfStore', () => ({
  useCsrfStore: () => ({ shrimp: 'token', updateShrimp: vi.fn() }),
}));
vi.mock('@/shared/stores', () => ({ useLanguageStore: () => ({ getCurrentLocale: 'en' }) }));
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({ currentOrganization: null }),
}));

import { errorInterceptor } from '@/plugins/axios/interceptors';

function rejection(status: number | null, data: unknown = {}): AxiosError {
  const config = { method: 'get', url: '/api/account/', headers: {} } as InternalAxiosRequestConfig;
  return {
    name: 'AxiosError',
    message: 'Request failed',
    config,
    isAxiosError: true,
    toJSON: () => ({}),
    response: status === null ? undefined : { status, statusText: '', headers: {}, config, data },
  } as AxiosError;
}

describe('errorInterceptor: session rejections (#4460)', () => {
  beforeEach(() => {
    touched.length = 0;
    noteApiRejection.mockClear();
  });

  it('reports a coded 401 with its parsed code and scope', async () => {
    const error = rejection(401, {
      error: 'Authentication Required',
      // What a sessionauth,basicauth route really says: the LAST strategy's text.
      message: '[AUTH_HEADER_MISSING] No authorization header',
      code: 'active_session_revoked',
      code_scope: 'customer_session',
    });

    await expect(errorInterceptor(error)).rejects.toBe(error);

    expect(noteApiRejection).toHaveBeenCalledTimes(1);
    expect(noteApiRejection).toHaveBeenCalledWith({
      code: 'active_session_revoked',
      code_scope: 'customer_session',
    });
  });

  it('reports an uncoded 401 as null: no statement about the customer session', async () => {
    await expect(errorInterceptor(rejection(401, { error: 'Invalid credentials' }))).rejects.toBeDefined();

    expect(noteApiRejection).toHaveBeenCalledWith(null);
  });

  it('treats a 401 with an unknown scope as uncoded', async () => {
    await expect(
      errorInterceptor(rejection(401, { code: 'whatever', code_scope: 'from_the_future' }))
    ).rejects.toBeDefined();

    expect(noteApiRejection).toHaveBeenCalledWith(null);
  });

  it.each([
    ['a network error', null],
    ['a timeout-shaped error with no response', null],
    ['403', 403],
    ['404', 404],
    ['422', 422],
    ['500', 500],
    ['503', 503],
  ])('%s is not an authentication verdict: nothing is reported', async (_name, status) => {
    await expect(
      errorInterceptor(rejection(status, { code: 'session_missing', code_scope: 'customer_session' }))
    ).rejects.toBeDefined();

    expect(noteApiRejection).not.toHaveBeenCalled();
    expect(touched).toEqual([]);
  });

  it('never touches any auth store member other than noteApiRejection', async () => {
    for (const scope of ['customer_session', 'verification_unavailable', 'admin_session']) {
      await expect(
        errorInterceptor(rejection(401, { code: 'x', code_scope: scope }))
      ).rejects.toBeDefined();
    }

    expect(new Set(touched)).toEqual(new Set(['noteApiRejection']));
  });

  it('still rejects with the original error: no gate-keeping', async () => {
    const error = rejection(401, { code: 'session_missing', code_scope: 'customer_session' });

    await expect(errorInterceptor(error)).rejects.toBe(error);
  });
});
