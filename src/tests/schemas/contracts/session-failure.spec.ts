// src/tests/schemas/contracts/session-failure.spec.ts
//
// Session-failure codes on API and /auth 401s (#4462).

import {
  RESERVED_SESSION_FAILURE_SCOPE,
  SESSION_FAILURE_CODES,
  parseSessionFailure,
  sessionFailureCodeSchema,
  sessionFailureSchema,
  sessionFailureScopeValues,
} from '@/schemas/contracts/session-failure';
import { describe, expect, it } from 'vitest';

// What Otto renders for a session refusal, after the server adds the pair.
const ottoBody = {
  error: 'Authentication Required',
  message: '[SESSION_SURFACE_MISMATCH] Session surface does not match request; sign in again',
  timestamp: 1_700_000_000,
  code: 'surface_mismatch',
  code_scope: 'customer_session',
};

const axiosError = (status: number, data: unknown) => ({ isAxiosError: true, response: { status, data } });

describe('session failure contract', () => {
  it('scopes every code, and only with a scope the server emits', () => {
    for (const scope of Object.values(SESSION_FAILURE_CODES)) {
      expect(sessionFailureScopeValues).toContain(scope);
    }
    expect(Object.keys(SESSION_FAILURE_CODES)).toHaveLength(12);
  });

  it('does not emit the reserved credential scope', () => {
    expect(sessionFailureScopeValues).not.toContain(RESERVED_SESSION_FAILURE_SCOPE);
    expect(sessionFailureSchema.safeParse({ code: 'x', code_scope: 'credential' }).success).toBe(false);
  });

  it('keeps outages apart from rejections', () => {
    expect(SESSION_FAILURE_CODES.active_session_unavailable).toBe('verification_unavailable');
    expect(SESSION_FAILURE_CODES.customer_unavailable).toBe('verification_unavailable');
    expect(SESSION_FAILURE_CODES.admin_session_expired).toBe('admin_session');
    expect(SESSION_FAILURE_CODES.surface_mismatch).toBe('customer_session');
  });

  it('knows each code by name', () => {
    expect(sessionFailureCodeSchema.safeParse('stale_credentials').success).toBe(true);
    expect(sessionFailureCodeSchema.safeParse('Authentication Required').success).toBe(false);
  });
});

describe('parseSessionFailure', () => {
  it('reads the pair from an axios 401', () => {
    expect(parseSessionFailure(axiosError(401, ottoBody))).toEqual({
      code: 'surface_mismatch',
      code_scope: 'customer_session',
    });
  });

  it('reads the pair from the /auth refusal shape', () => {
    const body = {
      error: 'Session could not be verified; try again',
      error_type: 'SessionUnverified',
      code: 'customer_unavailable',
      code_scope: 'verification_unavailable',
    };
    expect(parseSessionFailure(axiosError(401, body))?.code_scope).toBe('verification_unavailable');
  });

  it('reads a bare body', () => {
    expect(parseSessionFailure(ottoBody)?.code).toBe('surface_mismatch');
  });

  it('handles a code it has never seen by its scope', () => {
    const body = { ...ottoBody, code: 'some_future_reason' };
    expect(parseSessionFailure(axiosError(401, body))).toEqual({
      code: 'some_future_reason',
      code_scope: 'customer_session',
    });
  });

  it('treats an uncoded 401 as no statement about the session', () => {
    const { code: _c, code_scope: _s, ...uncoded } = ottoBody;
    expect(parseSessionFailure(axiosError(401, uncoded))).toBeNull();
    expect(parseSessionFailure(axiosError(401, { error: 'Authentication required' }))).toBeNull();
  });

  it('ignores a pair on any status other than 401', () => {
    for (const status of [200, 403, 500, 503]) {
      expect(parseSessionFailure(axiosError(status, ottoBody))).toBeNull();
    }
  });

  it('ignores an unknown scope, a partial pair, and non-objects', () => {
    expect(parseSessionFailure(axiosError(401, { ...ottoBody, code_scope: 'mystery' }))).toBeNull();
    expect(parseSessionFailure(axiosError(401, { code: 'surface_mismatch' }))).toBeNull();
    expect(parseSessionFailure(axiosError(401, { code: '', code_scope: 'customer_session' }))).toBeNull();
    expect(parseSessionFailure(axiosError(401, 'Unauthorized'))).toBeNull();
    expect(parseSessionFailure(new Error('Network Error'))).toBeNull();
    expect(parseSessionFailure(null)).toBeNull();
    expect(parseSessionFailure(undefined)).toBeNull();
  });
});
