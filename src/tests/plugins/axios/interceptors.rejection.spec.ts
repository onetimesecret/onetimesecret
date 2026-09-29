// src/tests/plugins/axios/interceptors.rejection.spec.ts
//
// #4460: a rejected API call REQUESTS reconciliation through the refresh
// coordinator. No API error handler writes authentication state directly.

import { AxiosError, type InternalAxiosRequestConfig } from 'axios';
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

// A real AxiosError: the classifier the interceptor consults for the message
// recognises the class, not the `isAxiosError` flag.
function rejection(status: number | null, data: unknown = {}): AxiosError {
  const config = { method: 'get', url: '/api/account/', headers: {} } as InternalAxiosRequestConfig;
  const response =
    status === null ? undefined : { status, statusText: '', headers: {}, config, data };
  return new AxiosError('Request failed', undefined, config, undefined, response);
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
    expect(noteApiRejection).toHaveBeenCalledWith(
      { code: 'active_session_revoked', code_scope: 'customer_session' },
      'Authentication Required'
    );
  });

  it('reports an uncoded 401 as null: no statement about the customer session', async () => {
    await expect(errorInterceptor(rejection(401, { error: 'Invalid credentials' }))).rejects.toBeDefined();

    expect(noteApiRejection).toHaveBeenCalledWith(null, 'Invalid credentials');
  });

  it('treats a 401 with an unknown scope as uncoded', async () => {
    await expect(
      errorInterceptor(rejection(401, { code: 'whatever', code_scope: 'from_the_future' }))
    ).rejects.toBeDefined();

    expect(noteApiRejection).toHaveBeenCalledWith(null, null);
  });

  // The message rides along so the coordinator's fallback notice can say what
  // the suppressed caller would have (ADR-046#rejection-disposition): the
  // classified message when it is of human interest, else null.
  it('passes the human-interest message of the 401, and null when there is none', async () => {
    await expect(
      errorInterceptor(rejection(401, { error: 'Authentication Required', code: 'session_missing', code_scope: 'customer_session' }))
    ).rejects.toBeDefined();
    expect(noteApiRejection).toHaveBeenLastCalledWith(
      { code: 'session_missing', code_scope: 'customer_session' },
      'Authentication Required'
    );

    // No `error` field: the classifier files it as security, which
    // useAsyncHandler would render as the generic text.
    await expect(errorInterceptor(rejection(401, {}))).rejects.toBeDefined();
    expect(noteApiRejection).toHaveBeenLastCalledWith(null, null);
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
