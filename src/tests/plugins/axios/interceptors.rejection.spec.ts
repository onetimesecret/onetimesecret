// src/tests/plugins/axios/interceptors.rejection.spec.ts
//
// #4460: a rejected API call REQUESTS reconciliation through the refresh
// coordinator. No API error handler writes authentication state directly.

import { AxiosError, type InternalAxiosRequestConfig } from 'axios';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const { touched, noteApiRejection, DISPOSITION_KEY } = vi.hoisted(() => ({
  touched: [] as string[],
  noteApiRejection: vi.fn(),
  DISPOSITION_KEY: Symbol('coordinatorDisposition'),
}));

// Every member the interceptor reaches for on the auth store is recorded, so
// "it only ever calls noteApiRejection" is asserted rather than assumed.
vi.mock('@/shared/stores/authStore', () => ({
  COORDINATOR_DISPOSITION_KEY: DISPOSITION_KEY,
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

  // A 403 credential refusal (a locked-out account) carries the pair, but the
  // interceptor reports 401s only: a rejected credential never reconciles.
  it('does not report a 403 credential refusal', async () => {
    await expect(
      errorInterceptor(rejection(403, { error: 'locked', code: 'account_locked', code_scope: 'credential' }))
    ).rejects.toBeDefined();

    expect(noteApiRejection).not.toHaveBeenCalled();
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

  // #4469: a session the server could not verify is an outage, answered 503
  // with the same coded body the 401 carried. It is reported exactly as the
  // 401 was; the coordinator's policy for the scope is unchanged.
  describe('a verification outage on a 503', () => {
    const outage = {
      error: 'Authentication Required',
      message: '[AUTH_HEADER_MISSING] No authorization header',
      code: 'active_session_unavailable',
      code_scope: 'verification_unavailable',
    };

    it('reports a 503 carrying verification_unavailable with its parsed code and scope', async () => {
      const error = rejection(503, outage);

      await expect(errorInterceptor(error)).rejects.toBe(error);

      expect(noteApiRejection).toHaveBeenCalledTimes(1);
      // A 503 classifies as a technical error, not of human interest, so the
      // fallback-notice message rides along as null (ADR-046#rejection-disposition).
      expect(noteApiRejection).toHaveBeenCalledWith(
        { code: 'active_session_unavailable', code_scope: 'verification_unavailable' },
        null
      );
      expect(new Set(touched)).toEqual(new Set(['noteApiRejection']));
    });

    it('stamps the coordinator disposition on the 503 as on a 401', async () => {
      noteApiRejection.mockReturnValueOnce({ ownedByCoordinator: true, reason: 'reconciling' });
      const error = rejection(503, outage);

      await expect(errorInterceptor(error)).rejects.toBe(error);

      expect((error as unknown as Record<symbol, unknown>)[DISPOSITION_KEY]).toEqual({
        ownedByCoordinator: true,
        reason: 'reconciling',
      });
    });

    it.each([
      ['an uncoded 503', { error: 'Service unavailable' }],
      ['the GET /bootstrap/me allocation 503 (ADR-046)', { error_type: 'SnapshotOrderingUnavailable' }],
      ['a 503 coded in another scope', { code: 'session_missing', code_scope: 'customer_session' }],
      ['a 503 coded in the credential scope', { code: 'api_key_invalid', code_scope: 'credential' }],
      ['a 503 with an unknown scope', { code: 'x', code_scope: 'from_the_future' }],
    ])('%s keeps its current handling: nothing is reported', async (_name, body) => {
      await expect(errorInterceptor(rejection(503, body))).rejects.toBeDefined();

      expect(noteApiRejection).not.toHaveBeenCalled();
      expect(touched).toEqual([]);
    });

    it('does not extend to other 5xx statuses', async () => {
      for (const status of [500, 502, 504]) {
        await expect(errorInterceptor(rejection(status, outage))).rejects.toBeDefined();
      }

      expect(noteApiRejection).not.toHaveBeenCalled();
    });
  });

  it('never touches any auth store member other than noteApiRejection', async () => {
    for (const scope of ['customer_session', 'verification_unavailable', 'admin_session']) {
      await expect(
        errorInterceptor(rejection(401, { code: 'x', code_scope: scope }))
      ).rejects.toBeDefined();
    }
    await expect(
      errorInterceptor(rejection(503, { code: 'customer_unavailable', code_scope: 'verification_unavailable' }))
    ).rejects.toBeDefined();

    expect(new Set(touched)).toEqual(new Set(['noteApiRejection']));
  });

  it('still rejects with the original error: no gate-keeping', async () => {
    const error = rejection(401, { code: 'session_missing', code_scope: 'customer_session' });

    await expect(errorInterceptor(error)).rejects.toBe(error);
  });
});
