// src/tests/apps/admin/adminSessionExpiry.spec.ts

import { AxiosError } from 'axios';
import { beforeEach, describe, expect, it } from 'vitest';

/**
 * The single recogniser for the #4331 expired-admin-session 401, and its wiring
 * into the mutation path.
 *
 * The marker is a string contract shared with
 * `lib/onetime/application/auth_strategies/base_session_auth_strategy.rb`, and
 * matching too loosely is the failure mode that matters: an ordinary 401
 * (signed out, session missing) must NOT raise a banner telling the operator
 * their admin window expired, and a 403 from the step-up gate must not either.
 */

import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
import {
  ADMIN_SESSION_EXPIRED_PREFIX,
  adminSessionExpired,
  clearAdminSessionExpired,
  noteAdminSessionExpiry,
} from '@/apps/admin/utils/adminSessionExpiry';

function axiosError(status: number, data: Record<string, unknown>): AxiosError {
  const error = new AxiosError(`Request failed with status code ${status}`);
  error.response = {
    status,
    statusText: '',
    headers: {},
    config: {} as never,
    data,
  };
  return error;
}

const expiredBody = {
  error: 'Authentication Required',
  message: `${ADMIN_SESSION_EXPIRED_PREFIX} Admin session idle timeout exceeded; sign in again`,
};

describe('noteAdminSessionExpiry', () => {
  beforeEach(() => {
    clearAdminSessionExpired();
  });

  // Otto renders an auth failure as {error: 'Authentication Required',
  // message: '<reason>'}, so the marker arrives in `message`.
  it('recognises the marker in the Otto auth-failure message', () => {
    expect(noteAdminSessionExpiry(axiosError(401, expiredBody))).toBe(true);
    expect(adminSessionExpired.value).toBe(true);
  });

  it('also recognises it in a top-level error field', () => {
    const error = axiosError(401, { error: `${ADMIN_SESSION_EXPIRED_PREFIX} whatever` });

    expect(noteAdminSessionExpiry(error)).toBe(true);
    expect(adminSessionExpired.value).toBe(true);
  });

  it('ignores an ordinary 401', () => {
    const error = axiosError(401, {
      error: 'Authentication Required',
      message: '[SESSION_NOT_AUTHENTICATED] Not authenticated',
    });

    expect(noteAdminSessionExpiry(error)).toBe(false);
    expect(adminSessionExpired.value).toBe(false);
  });

  // The marker only ever rides a 401. A 403 carrying the same text would be a
  // different control (#4326/#4327) and must not end the console session.
  it('ignores the marker on any other status', () => {
    expect(noteAdminSessionExpiry(axiosError(403, expiredBody))).toBe(false);
    expect(adminSessionExpired.value).toBe(false);
  });

  it('ignores a network error with no response', () => {
    expect(noteAdminSessionExpiry(new Error('Network Error'))).toBe(false);
    expect(noteAdminSessionExpiry(null)).toBe(false);
    expect(adminSessionExpired.value).toBe(false);
  });
});

describe('useAdminMutation', () => {
  beforeEach(() => {
    clearAdminSessionExpired();
  });

  it('raises the shared flag when a mutation is refused for an expired window', async () => {
    const mutation = useAdminMutation(() => Promise.reject(axiosError(401, expiredBody)));

    expect(await mutation.run()).toBe(false);
    expect(adminSessionExpired.value).toBe(true);
    // The per-action error is still populated: the dialog shows the reason too.
    expect(mutation.error.value).toBeTruthy();
  });

  it('leaves the flag alone for an ordinary failure', async () => {
    const mutation = useAdminMutation(() =>
      Promise.reject(axiosError(422, { error: 'Cannot purge your own account' }))
    );

    expect(await mutation.run()).toBe(false);
    expect(adminSessionExpired.value).toBe(false);
  });
});
