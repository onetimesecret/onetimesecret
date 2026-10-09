// src/tests/composables/useReauth.spec.ts

import { useReauth } from '@/shared/composables/useReauth';
import { useAuthStore } from '@/shared/stores/authStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

vi.mock('@simplewebauthn/browser', () => ({
  startAuthentication: vi.fn(),
}));

describe('useReauth', () => {
  let axiosMock: AxiosMockAdapter;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    // init() already ran (auto-init plugin); set the token the way the app
    // does after a response.
    useCsrfStore().updateShrimp('csrf-token');
    Object.defineProperty(window, 'PublicKeyCredential', {
      value: function PublicKeyCredential() {},
      writable: true,
      configurable: true,
    });
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
  });

  it('loads and validates the re-authentication offer', async () => {
    axiosMock.onGet('/auth/reauth-offer').reply(200, {
      surface: { kind: 'custom', id: 'tenant-a' },
      methods: ['webauthn', 'password'],
      webauthn_credentials: [{ scope: 'platform' }],
      related_origins: ['https://example.com'],
    });

    const { fetchOffer, offer, error } = useReauth();

    await expect(fetchOffer()).resolves.toEqual({
      surface: { kind: 'custom', id: 'tenant-a' },
      methods: ['webauthn', 'password'],
      webauthn_credentials: [{ scope: 'platform' }],
      related_origins: ['https://example.com'],
    });
    expect(offer.value?.surface).toEqual({ kind: 'custom', id: 'tenant-a' });
    expect(error.value).toBeNull();
  });

  it('submits password and MFA values with the current CSRF token', async () => {
    axiosMock.onPost('/auth/reauth').replyOnce(200, {
      mfa_required: true,
      mfa_methods: ['otp', 'recovery_code'],
    });
    axiosMock.onPost('/auth/reauth').replyOnce(200, {
      success: 'Re-authentication complete',
    });

    const { submitPassword, mfaMethods } = useReauth();

    await expect(submitPassword('correct horse')).resolves.toBe('mfa_required');
    expect(mfaMethods.value).toEqual(['otp', 'recovery_code']);
    await expect(submitPassword('correct horse', '123456')).resolves.toBe('success');

    expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({
      method: 'password',
      password: 'correct horse',
      shrimp: 'csrf-token',
    });
    expect(JSON.parse(axiosMock.history.post[1].data)).toEqual({
      method: 'password',
      password: 'correct horse',
      otp_code: '123456',
      shrimp: 'csrf-token',
    });
  });

  it('completes password plus required WebAuthn without dropping the primary', async () => {
    const { startAuthentication } = await import('@simplewebauthn/browser');
    vi.mocked(startAuthentication).mockResolvedValue({ id: 'assertion' } as never);

    axiosMock.onPost('/auth/reauth').replyOnce(200, {
      webauthn_auth: { challenge: 'challenge', rpId: 'example.test' },
      webauthn_auth_challenge: 'challenge-state',
      webauthn_auth_challenge_hmac: 'challenge-hmac',
    });
    axiosMock.onPost('/auth/reauth').replyOnce(200, {
      success: 'Re-authentication complete',
    });

    const { submitPasswordWebauthn } = useReauth();

    await expect(submitPasswordWebauthn('correct horse')).resolves.toBe('success');
    expect(JSON.parse(axiosMock.history.post[1].data)).toMatchObject({
      method: 'password',
      password: 'correct horse',
      mfa_method: 'webauthn',
      webauthn_auth: { id: 'assertion' },
    });
  });

  it('completes a WebAuthn challenge delivered in a 422 response', async () => {
    const { startAuthentication } = await import('@simplewebauthn/browser');
    vi.mocked(startAuthentication).mockResolvedValue({ id: 'assertion' } as never);

    axiosMock.onPost('/auth/reauth').replyOnce(422, {
      webauthn_auth: { challenge: 'challenge', rpId: 'example.test' },
      webauthn_auth_challenge: 'challenge-state',
      webauthn_auth_challenge_hmac: 'challenge-hmac',
    });
    axiosMock.onPost('/auth/reauth').replyOnce(200, {
      success: 'Re-authentication complete',
    });

    const { submitWebauthn } = useReauth();

    await expect(submitWebauthn()).resolves.toBe('success');
    expect(startAuthentication).toHaveBeenCalledWith({
      optionsJSON: { challenge: 'challenge', rpId: 'example.test' },
    });
    expect(JSON.parse(axiosMock.history.post[1].data)).toEqual({
      method: 'webauthn',
      shrimp: 'csrf-token',
      webauthn_auth: { id: 'assertion' },
      webauthn_auth_challenge: 'challenge-state',
      webauthn_auth_challenge_hmac: 'challenge-hmac',
    });
  });

  it('surfaces structured API errors and their codes', async () => {
    axiosMock.onPost('/auth/reauth').reply(401, {
      error: 'Password is incorrect',
      error_code: 'invalid_password',
    });

    const { submitPassword, error, errorCode } = useReauth();

    await expect(submitPassword('wrong')).resolves.toBe('error');
    expect(error.value).toBe('Password is incorrect');
    expect(errorCode.value).toBe('invalid_password');
  });

  // The proof is recorded under a new session id (#4466), and with it a new
  // snapshot epoch (ADR-046). One auth-mutation refresh adopts it in place;
  // the next ordinary refresh would otherwise read it as a replaced session
  // and force a page load.
  it('asks the auth store for one auth-mutation snapshot after a completed ceremony', async () => {
    const authRefresh = vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
    axiosMock.onPost('/auth/reauth').replyOnce(200, {
      mfa_required: true,
      mfa_methods: ['otp'],
    });
    axiosMock.onPost('/auth/reauth').replyOnce(200, {
      success: 'Re-authentication complete',
    });

    const { submitPassword } = useReauth();

    await expect(submitPassword('correct horse')).resolves.toBe('mfa_required');
    expect(authRefresh).not.toHaveBeenCalled();

    await expect(submitPassword('correct horse', '123456')).resolves.toBe('success');
    expect(authRefresh).toHaveBeenCalledTimes(1);
    expect(authRefresh).toHaveBeenCalledWith({ kind: 'auth-mutation', reason: 'reauth' });
  });

  it.each(['password', 'webauthn'] as const)(
    'adopts a confirmed rotation after a failed %s proof write without reporting success',
    async (method) => {
      const authRefresh = vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
      if (method === 'webauthn') {
        const { startAuthentication } = await import('@simplewebauthn/browser');
        vi.mocked(startAuthentication).mockResolvedValue({ id: 'assertion' } as never);
        axiosMock.onPost('/auth/reauth').replyOnce(200, {
          webauthn_auth: { challenge: 'challenge', rpId: 'example.test' },
          webauthn_auth_challenge: 'challenge-state',
          webauthn_auth_challenge_hmac: 'challenge-hmac',
        });
      }
      axiosMock.onPost('/auth/reauth').replyOnce(503, {
        error: 'Re-authentication could not be recorded. Please try again.',
        error_code: 'reauth_not_recorded',
        session_rotated: true,
      });

      const { submitPassword, submitWebauthn, error, errorCode } = useReauth();
      const result = method === 'password' ? submitPassword('correct horse') : submitWebauthn();

      await expect(result).resolves.toBe('error');
      expect(error.value).toBe('Re-authentication could not be recorded. Please try again.');
      expect(errorCode.value).toBe('reauth_not_recorded');
      expect(authRefresh).toHaveBeenCalledTimes(1);
      expect(authRefresh).toHaveBeenCalledWith({ kind: 'auth-mutation', reason: 'reauth' });
    }
  );

  it.each([undefined, false, 'true'])(
    'does not adopt an epoch on a proof error with rotation signal %s',
    async (sessionRotated) => {
      const authRefresh = vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
      axiosMock.onPost('/auth/reauth').replyOnce(403, {
        error: 'Re-authentication is unavailable on this surface.',
        error_code: 'invalid_surface',
        ...(sessionRotated === undefined ? {} : { session_rotated: sessionRotated }),
      });

      await expect(useReauth().submitPassword('correct horse')).resolves.toBe('error');
      expect(authRefresh).not.toHaveBeenCalled();
    }
  );

  it('does not adopt an epoch after a network failure', async () => {
    const authRefresh = vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
    axiosMock.onPost('/auth/reauth').networkError();

    await expect(useReauth().submitPassword('correct horse')).resolves.toBe('error');
    expect(authRefresh).not.toHaveBeenCalled();
  });

  it('does not ask for a snapshot when the ceremony is refused', async () => {
    const authRefresh = vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
    axiosMock.onPost('/auth/reauth').reply(503, {
      error: 'Re-authentication could not be completed. Please try again.',
      error_code: 'session_not_rotated',
    });

    const { submitPassword, errorCode } = useReauth();

    await expect(submitPassword('correct horse')).resolves.toBe('error');
    expect(errorCode.value).toBe('session_not_rotated');
    expect(authRefresh).not.toHaveBeenCalled();
  });
});
