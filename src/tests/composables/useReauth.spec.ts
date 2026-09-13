// src/tests/composables/useReauth.spec.ts

import { useReauth } from '@/shared/composables/useReauth';
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
    useCsrfStore().init({ shrimp: 'csrf-token' });
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
      related_origins: [{ kind: 'canonical' }],
    });

    const { fetchOffer, offer, error } = useReauth();

    await expect(fetchOffer()).resolves.toEqual({
      surface: { kind: 'custom', id: 'tenant-a' },
      methods: ['webauthn', 'password'],
      webauthn_credentials: [{ scope: 'platform' }],
      related_origins: [{ kind: 'canonical' }],
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
});
