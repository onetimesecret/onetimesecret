// src/tests/composables/useWebAuthn.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useWebAuthn } from '@/shared/composables/useWebAuthn';
import { setupTestPinia } from '../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';

// Mock @simplewebauthn/browser
vi.mock('@simplewebauthn/browser', () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}));

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

// Mock vue-router
const mockRouterPush = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: mockRouterPush,
  }),
}));

describe('useWebAuthn', () => {
  let axiosMock: AxiosMockAdapter;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    mockRouterPush.mockClear();
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
  });

  describe('browser support detection', () => {
    it('detects supported browser when PublicKeyCredential exists', async () => {
      // Setup: PublicKeyCredential is already mocked in jsdom environment
      // or we ensure it's defined
      const originalPKC = window.PublicKeyCredential;

      // Define PublicKeyCredential as a function (which it is in browsers)
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: function PublicKeyCredential() {},
        writable: true,
        configurable: true,
      });

      const { supported } = useWebAuthn();
      expect(supported.value).toBe(true);

      // Restore
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: originalPKC,
        writable: true,
        configurable: true,
      });
    });

    it('detects unsupported browser when PublicKeyCredential is undefined', async () => {
      const originalPKC = window.PublicKeyCredential;

      // Remove PublicKeyCredential
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: undefined,
        writable: true,
        configurable: true,
      });

      const { supported } = useWebAuthn();
      expect(supported.value).toBe(false);

      // Restore
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: originalPKC,
        writable: true,
        configurable: true,
      });
    });
  });

  describe('authenticateWebAuthn (passwordless login)', () => {
    beforeEach(() => {
      // Ensure WebAuthn is supported for these tests
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: function PublicKeyCredential() {},
        writable: true,
        configurable: true,
      });
    });

    it('returns false when browser does not support WebAuthn', async () => {
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: undefined,
        writable: true,
        configurable: true,
      });

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn();

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.notSupported');
    });

    it('successfully authenticates with valid credentials using webauthn-login route', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      // Mock challenge response (passwordless login uses webauthn_login fields)
      // Rodauth JSON API returns credential options as raw JSON objects (not base64)
      const challengeOptions = { challenge: 'test-challenge', rpId: 'localhost' };
      const challengeResponse = {
        webauthn_login: challengeOptions, // Raw JSON object, not base64
        webauthn_login_challenge: 'challenge-data',
        webauthn_login_challenge_hmac: 'hmac-data',
      };

      // Mock credential assertion
      const mockAssertion = {
        id: 'credential-id',
        rawId: 'raw-id',
        type: 'public-key',
        response: {
          authenticatorData: 'auth-data',
          clientDataJSON: 'client-data',
          signature: 'signature',
        },
      };

      startAuthenticationMock.mockResolvedValue(mockAssertion as any);

      // Mock API calls (uses /auth/webauthn-login for passwordless)
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, challengeResponse);
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, { success: 'Authenticated' });
      // Mock the bootstrap/me call that happens after setAuthenticated(true)
      axiosMock.onGet('/bootstrap/me').reply(200, { authenticated: true });

      const { authenticateWebAuthn, isLoading, error } = useWebAuthn();

      expect(isLoading.value).toBe(false);

      const result = await authenticateWebAuthn('user@example.com');

      expect(result).toBe(true);
      expect(error.value).toBeNull();
      expect(isLoading.value).toBe(false);
      // @simplewebauthn/browser v10+ uses { optionsJSON } wrapper
      expect(startAuthenticationMock).toHaveBeenCalledWith({ optionsJSON: challengeOptions });
      expect(mockRouterPush).toHaveBeenCalledWith('/');
    });

    it('handles invalid challenge response', async () => {
      // Return response without webauthn_login field
      axiosMock.onPost('/auth/webauthn-login').reply(200, {});

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn();

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid challenge response');
    });

    it('handles NotAllowedError when user cancels', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      const challengeOptions = { challenge: 'test', rpId: 'localhost' };
      axiosMock.onPost('/auth/webauthn-login').reply(200, {
        webauthn_login: challengeOptions, // Raw JSON object
        webauthn_login_challenge: 'challenge',
        webauthn_login_challenge_hmac: 'hmac',
      });

      // Simulate user cancellation
      const cancelError = new Error('User cancelled');
      cancelError.name = 'NotAllowedError';
      startAuthenticationMock.mockRejectedValue(cancelError);

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn();

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.cancelled');
    });

    it('handles server verification error', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      const challengeOptions = { challenge: 'test', rpId: 'localhost' };
      startAuthenticationMock.mockResolvedValue({ id: 'cred' } as any);

      // First call: challenge
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, {
        webauthn_login: challengeOptions, // Raw JSON object
        webauthn_login_challenge: 'challenge',
        webauthn_login_challenge_hmac: 'hmac',
      });
      // Second call: verification returns error
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, {
        error: 'Invalid credential',
      });

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn();

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid credential');
    });

    it('handles API error response', async () => {
      axiosMock.onPost('/auth/webauthn-login').reply(500, {
        error: 'Server error',
      });

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn();

      expect(result).toBe(false);
      expect(error.value).toBe('Server error');
    });

    it('manages loading state during authentication', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      // Use a deferred promise to control timing
      let resolveAuth: (value: any) => void;
      const authPromise = new Promise((resolve) => {
        resolveAuth = resolve;
      });
      startAuthenticationMock.mockReturnValue(authPromise as any);

      const challengeOptions = { challenge: 'test', rpId: 'localhost' };
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, {
        webauthn_login: challengeOptions, // Raw JSON object
        webauthn_login_challenge: 'challenge',
        webauthn_login_challenge_hmac: 'hmac',
      });
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, { success: 'OK' });

      const { authenticateWebAuthn, isLoading } = useWebAuthn();

      expect(isLoading.value).toBe(false);

      const resultPromise = authenticateWebAuthn();

      // Wait for the async operation to start
      await new Promise((r) => setTimeout(r, 10));
      expect(isLoading.value).toBe(true);

      // Resolve the authentication
      resolveAuth!({ id: 'cred' });
      await resultPromise;

      expect(isLoading.value).toBe(false);
    });
  });

  describe('verifyWebAuthnMfa (MFA verification)', () => {
    beforeEach(() => {
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: function PublicKeyCredential() {},
        writable: true,
        configurable: true,
      });
    });

    it('uses webauthn-auth route for MFA verification', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      const challengeOptions = { challenge: 'mfa-challenge', rpId: 'localhost' };
      startAuthenticationMock.mockResolvedValue({ id: 'cred' } as any);

      axiosMock.onPost('/auth/webauthn-auth').replyOnce(200, {
        webauthn_auth: challengeOptions, // Raw JSON object
        webauthn_auth_challenge: 'challenge',
        webauthn_auth_challenge_hmac: 'hmac',
      });
      axiosMock.onPost('/auth/webauthn-auth').replyOnce(200, { success: 'MFA verified' });

      const { verifyWebAuthnMfa, error } = useWebAuthn();
      const result = await verifyWebAuthnMfa();

      expect(result).toBe(true);
      expect(error.value).toBeNull();
    });

    it('returns false when browser does not support WebAuthn', async () => {
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: undefined,
        writable: true,
        configurable: true,
      });

      const { verifyWebAuthnMfa, error } = useWebAuthn();
      const result = await verifyWebAuthnMfa();

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.notSupported');
    });
  });

  describe('registerWebAuthn', () => {
    beforeEach(() => {
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: function PublicKeyCredential() {},
        writable: true,
        configurable: true,
      });
    });

    it('returns false when browser does not support WebAuthn', async () => {
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: undefined,
        writable: true,
        configurable: true,
      });

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn();

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.notSupported');
    });

    it('successfully registers a new credential', async () => {
      const { startRegistration } = await import('@simplewebauthn/browser');
      const startRegistrationMock = vi.mocked(startRegistration);

      const challengeOptions = {
        challenge: 'reg-challenge',
        rp: { name: 'Test', id: 'localhost' },
        user: { id: 'user-id', name: 'user@example.com', displayName: 'User' },
        pubKeyCredParams: [{ type: 'public-key', alg: -7 }],
      };

      const mockCredential = {
        id: 'new-credential-id',
        rawId: 'raw-id',
        type: 'public-key',
        response: {
          attestationObject: 'attestation',
          clientDataJSON: 'client-data',
        },
      };

      startRegistrationMock.mockResolvedValue(mockCredential as any);

      // Mock setup challenge (Rodauth returns raw JSON objects)
      axiosMock.onPost('/auth/webauthn-setup').replyOnce(200, {
        webauthn_setup: challengeOptions, // Raw JSON object, not base64
        webauthn_setup_challenge: 'setup-challenge',
        webauthn_setup_challenge_hmac: 'setup-hmac',
      });
      // Mock verification success
      axiosMock.onPost('/auth/webauthn-setup').replyOnce(200, {
        success: 'Credential registered',
      });

      const { registerWebAuthn, error, isLoading } = useWebAuthn();

      expect(isLoading.value).toBe(false);

      const result = await registerWebAuthn('testpassword');

      expect(result).toBe(true);
      expect(error.value).toBeNull();
      expect(isLoading.value).toBe(false);
      // @simplewebauthn/browser v10+ uses { optionsJSON } wrapper
      expect(startRegistrationMock).toHaveBeenCalledWith({ optionsJSON: challengeOptions });
    });

    it('returns false when password is not provided', async () => {
      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.passwordRequired');
    });

    it('handles invalid setup challenge response', async () => {
      axiosMock.onPost('/auth/webauthn-setup').reply(200, {});

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('testpassword');

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid challenge response');
    });

    it('handles NotAllowedError when user cancels registration', async () => {
      const { startRegistration } = await import('@simplewebauthn/browser');
      const startRegistrationMock = vi.mocked(startRegistration);

      const challengeOptions = { challenge: 'test', rp: { name: 'Test' } };
      axiosMock.onPost('/auth/webauthn-setup').reply(200, {
        webauthn_setup: challengeOptions, // Raw JSON object
        webauthn_setup_challenge: 'challenge',
        webauthn_setup_challenge_hmac: 'hmac',
      });

      const cancelError = new Error('User cancelled');
      cancelError.name = 'NotAllowedError';
      startRegistrationMock.mockRejectedValue(cancelError);

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('testpassword');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.cancelled');
    });

    it('handles server verification error during registration', async () => {
      const { startRegistration } = await import('@simplewebauthn/browser');
      const startRegistrationMock = vi.mocked(startRegistration);

      const challengeOptions = { challenge: 'test', rp: { name: 'Test' } };
      startRegistrationMock.mockResolvedValue({ id: 'cred' } as any);

      axiosMock.onPost('/auth/webauthn-setup').replyOnce(200, {
        webauthn_setup: challengeOptions, // Raw JSON object
        webauthn_setup_challenge: 'challenge',
        webauthn_setup_challenge_hmac: 'hmac',
      });
      axiosMock.onPost('/auth/webauthn-setup').replyOnce(200, {
        error: 'Registration failed',
      });

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('testpassword');

      expect(result).toBe(false);
      expect(error.value).toBe('Registration failed');
    });

    it('handles API error with response data', async () => {
      axiosMock.onPost('/auth/webauthn-setup').reply(403, {
        error: 'Forbidden',
      });

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('testpassword');

      expect(result).toBe(false);
      expect(error.value).toBe('Forbidden');
    });

    it('handles generic errors with fallback message', async () => {
      const { startRegistration } = await import('@simplewebauthn/browser');
      const startRegistrationMock = vi.mocked(startRegistration);

      const challengeOptions = { challenge: 'test', rp: { name: 'Test' } };
      axiosMock.onPost('/auth/webauthn-setup').reply(200, {
        webauthn_setup: challengeOptions, // Raw JSON object
        webauthn_setup_challenge: 'challenge',
        webauthn_setup_challenge_hmac: 'hmac',
      });

      // Simulate a generic error without specific message
      startRegistrationMock.mockRejectedValue(new Error());

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('testpassword');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.setupFailed');
    });
  });

  describe('clearError', () => {
    beforeEach(() => {
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: undefined,
        writable: true,
        configurable: true,
      });
    });

    it('clears the error state', async () => {
      const { authenticateWebAuthn, error, clearError } = useWebAuthn();

      // Trigger an error
      await authenticateWebAuthn();
      expect(error.value).toBe('web.auth.webauthn.notSupported');

      // Clear it
      clearError();
      expect(error.value).toBeNull();
    });

    it('can be called when no error exists', () => {
      const { error, clearError } = useWebAuthn();

      expect(error.value).toBeNull();
      clearError();
      expect(error.value).toBeNull();
    });
  });

  describe('loading state management', () => {
    beforeEach(() => {
      Object.defineProperty(window, 'PublicKeyCredential', {
        value: function PublicKeyCredential() {},
        writable: true,
        configurable: true,
      });
    });

    it('resets loading state after successful operation', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      vi.mocked(startAuthentication).mockResolvedValue({ id: 'cred' } as any);

      const challengeOptions = { challenge: 'test', rpId: 'localhost' };
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, {
        webauthn_login: challengeOptions, // Raw JSON object
        webauthn_login_challenge: 'challenge',
        webauthn_login_challenge_hmac: 'hmac',
      });
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, { success: 'OK' });

      const { authenticateWebAuthn, isLoading } = useWebAuthn();

      await authenticateWebAuthn();
      expect(isLoading.value).toBe(false);
    });

    it('resets loading state after failed operation', async () => {
      axiosMock.onPost('/auth/webauthn-login').networkError();

      const { authenticateWebAuthn, isLoading } = useWebAuthn();

      await authenticateWebAuthn();
      expect(isLoading.value).toBe(false);
    });
  });
});
