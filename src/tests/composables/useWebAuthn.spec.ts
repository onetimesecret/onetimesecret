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

      // Rodauth's JSON layer emits the webauthn-login challenge under the
      // webauthn_auth key family (json.rb) — webauthn_login* keys never exist
      // on the wire. Raw JSON objects, not base64. The challenge arrives in a
      // 422 body: before_webauthn_login_route populates the keys without
      // returning early, then the credential-less POST hits the route's
      // invalid_field throw (json.rb:157-165 + webauthn.rb).
      const challengeOptions = { challenge: 'test-challenge', rpId: 'localhost' };
      const challengeResponse = {
        error: 'There was an error authenticating via WebAuthn',
        'field-error': ['webauthn_auth', 'invalid webauthn authentication param'],
        webauthn_auth: challengeOptions, // Raw JSON object, not base64
        webauthn_auth_challenge: 'challenge-data',
        webauthn_auth_challenge_hmac: 'hmac-data',
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
      axiosMock.onPost('/auth/webauthn-login').replyOnce(422, challengeResponse);
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

      // Phase 2 posts webauthn_auth* param names (webauthn_login.rb reads
      // those) plus login — the route resolves the account by login.
      const verifyBody = JSON.parse(axiosMock.history.post[1].data);
      expect(verifyBody.webauthn_auth).toEqual(mockAssertion);
      expect(verifyBody.webauthn_auth_challenge).toBe('challenge-data');
      expect(verifyBody.webauthn_auth_challenge_hmac).toBe('hmac-data');
      expect(verifyBody.login).toBe('user@example.com');
      expect(verifyBody).toHaveProperty('shrimp');
      expect(verifyBody).not.toHaveProperty('webauthn_login');
      expect(verifyBody).not.toHaveProperty('webauthn_login_challenge');
    });

    it('tolerates a 2xx challenge body carrying the same keys', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      const challengeOptions = { challenge: 'test-challenge', rpId: 'localhost' };
      startAuthenticationMock.mockResolvedValue({ id: 'cred' } as any);

      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, {
        webauthn_auth: challengeOptions,
        webauthn_auth_challenge: 'challenge',
        webauthn_auth_challenge_hmac: 'hmac',
      });
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, { success: 'Authenticated' });
      axiosMock.onGet('/bootstrap/me').reply(200, { authenticated: true });

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn('user@example.com');

      expect(result).toBe(true);
      expect(error.value).toBeNull();
      expect(startAuthenticationMock).toHaveBeenCalledWith({ optionsJSON: challengeOptions });
    });

    it('requires an email and fails fast without posting', async () => {
      // Without a login param the route 401s at no_matching_login before ever
      // emitting a challenge (webauthn_login.rb) — no autofill in this version.
      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn();

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.emailRequired');
      expect(axiosMock.history.post).toHaveLength(0);
    });

    it('handles invalid challenge response', async () => {
      // 2xx response without the webauthn_auth field
      axiosMock.onPost('/auth/webauthn-login').reply(200, {});

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn('user@example.com');

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid challenge response');
    });

    it('surfaces a 401 no-matching-login error (unknown email)', async () => {
      // Unknown login: no challenge keys in the body, so this is a real error
      axiosMock.onPost('/auth/webauthn-login').reply(401, {
        error: 'There was an error authenticating via WebAuthn',
        'field-error': ['login', 'no matching login'],
      });

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn('unknown@example.com');

      expect(result).toBe(false);
      expect(error.value).toBe('There was an error authenticating via WebAuthn');
    });

    it('handles NotAllowedError when user cancels', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      const challengeOptions = { challenge: 'test', rpId: 'localhost' };
      axiosMock.onPost('/auth/webauthn-login').reply(422, {
        error: 'There was an error authenticating via WebAuthn',
        webauthn_auth: challengeOptions, // Raw JSON object
        webauthn_auth_challenge: 'challenge',
        webauthn_auth_challenge_hmac: 'hmac',
      });

      // Simulate user cancellation — must be a DOMException (not Error) because
      // the composable checks `err instanceof DOMException`
      const cancelError = new DOMException('User cancelled', 'NotAllowedError');
      startAuthenticationMock.mockRejectedValue(cancelError);

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn('user@example.com');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.webauthn.cancelled');
    });

    it('handles server verification error', async () => {
      const { startAuthentication } = await import('@simplewebauthn/browser');
      const startAuthenticationMock = vi.mocked(startAuthentication);

      const challengeOptions = { challenge: 'test', rpId: 'localhost' };
      startAuthenticationMock.mockResolvedValue({ id: 'cred' } as any);

      // First call: challenge (422 delivery)
      axiosMock.onPost('/auth/webauthn-login').replyOnce(422, {
        error: 'There was an error authenticating via WebAuthn',
        webauthn_auth: challengeOptions, // Raw JSON object
        webauthn_auth_challenge: 'challenge',
        webauthn_auth_challenge_hmac: 'hmac',
      });
      // Second call: verification returns error
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, {
        error: 'Invalid credential',
      });

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn('user@example.com');

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid credential');
    });

    it('handles API error response', async () => {
      axiosMock.onPost('/auth/webauthn-login').reply(500, {
        error: 'Server error',
      });

      const { authenticateWebAuthn, error } = useWebAuthn();
      const result = await authenticateWebAuthn('user@example.com');

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
      axiosMock.onPost('/auth/webauthn-login').replyOnce(422, {
        error: 'There was an error authenticating via WebAuthn',
        webauthn_auth: challengeOptions, // Raw JSON object
        webauthn_auth_challenge: 'challenge',
        webauthn_auth_challenge_hmac: 'hmac',
      });
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, { success: 'OK' });

      const { authenticateWebAuthn, isLoading } = useWebAuthn();

      expect(isLoading.value).toBe(false);

      const resultPromise = authenticateWebAuthn('user@example.com');

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

      // Phase 1 challenge arrives in a 422 body (Rodauth json.rb quirk)
      axiosMock.onPost('/auth/webauthn-auth').replyOnce(422, {
        error: 'Error authenticating via WebAuthn',
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

      // Mock setup challenge: 422 delivery with raw JSON credential options
      // (before_webauthn_setup_route populates the keys, then the missing
      // webauthn_setup param hits invalid_field_error_status)
      axiosMock.onPost('/auth/webauthn-setup').replyOnce(422, {
        error: 'There was an error setting up WebAuthn authentication',
        'field-error': ['webauthn_setup', 'invalid webauthn setup param'],
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

      // Password accompanies both the challenge request and the verify request
      const challengeBody = JSON.parse(axiosMock.history.post[0].data);
      const verifyBody = JSON.parse(axiosMock.history.post[1].data);
      expect(challengeBody.password).toBe('testpassword');
      expect(verifyBody.password).toBe('testpassword');
    });

    it('registers without a password (SSO-only account) and omits the password key', async () => {
      const { startRegistration } = await import('@simplewebauthn/browser');
      const startRegistrationMock = vi.mocked(startRegistration);

      const challengeOptions = { challenge: 'reg-challenge', rp: { name: 'Test' } };
      startRegistrationMock.mockResolvedValue({ id: 'cred' } as any);

      axiosMock.onPost('/auth/webauthn-setup').replyOnce(422, {
        error: 'There was an error setting up WebAuthn authentication',
        webauthn_setup: challengeOptions,
        webauthn_setup_challenge: 'setup-challenge',
        webauthn_setup_challenge_hmac: 'setup-hmac',
      });
      axiosMock.onPost('/auth/webauthn-setup').replyOnce(200, {
        success: 'Credential registered',
      });

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn();

      expect(result).toBe(true);
      expect(error.value).toBeNull();

      // The password key must be absent entirely — not undefined/empty-string
      const challengeBody = JSON.parse(axiosMock.history.post[0].data);
      const verifyBody = JSON.parse(axiosMock.history.post[1].data);
      expect(challengeBody).not.toHaveProperty('password');
      expect(verifyBody).not.toHaveProperty('password');
      expect(challengeBody).toHaveProperty('shrimp');
      expect(verifyBody).toHaveProperty('shrimp');
    });

    it('handles invalid setup challenge response', async () => {
      axiosMock.onPost('/auth/webauthn-setup').reply(200, {});

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('testpassword');

      expect(result).toBe(false);
      expect(error.value).toBe('Invalid challenge response');
    });

    it('surfaces a wrong-password 401 from phase 1', async () => {
      // invalid_password throws with invalid_password_error_status (401), so
      // the challenge-tolerant path must NOT swallow it
      axiosMock.onPost('/auth/webauthn-setup').reply(401, {
        error: 'invalid password',
        'field-error': ['password', 'invalid password'],
      });

      const { registerWebAuthn, error } = useWebAuthn();
      const result = await registerWebAuthn('wrongpassword');

      expect(result).toBe(false);
      expect(error.value).toBe('invalid password');
    });

    it('handles NotAllowedError when user cancels registration', async () => {
      const { startRegistration } = await import('@simplewebauthn/browser');
      const startRegistrationMock = vi.mocked(startRegistration);

      const challengeOptions = { challenge: 'test', rp: { name: 'Test' } };
      axiosMock.onPost('/auth/webauthn-setup').reply(422, {
        error: 'There was an error setting up WebAuthn authentication',
        webauthn_setup: challengeOptions, // Raw JSON object
        webauthn_setup_challenge: 'challenge',
        webauthn_setup_challenge_hmac: 'hmac',
      });

      // Must be a DOMException — the composable checks `err instanceof DOMException`
      const cancelError = new DOMException('User cancelled', 'NotAllowedError');
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

      axiosMock.onPost('/auth/webauthn-setup').replyOnce(422, {
        error: 'There was an error setting up WebAuthn authentication',
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
      // 200-body challenge here doubles as tolerance coverage for the setup
      // route (proves the ceremony starts from a 2xx delivery too)
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

  describe('fetchWebAuthnCredentials', () => {
    it('returns the parsed credential list', async () => {
      const credentials = [
        { id: 'credential-aaa-a1b2c3', last_used_at: '2026-08-10T12:00:00Z' },
        { id: 'credential-bbb-d4e5f6', last_used_at: null },
      ];
      axiosMock.onGet('/auth/webauthn-credentials').reply(200, {
        credentials,
        count: 2,
      });

      const { fetchWebAuthnCredentials, error, isLoading } = useWebAuthn();
      const result = await fetchWebAuthnCredentials();

      expect(result).toEqual(credentials);
      expect(error.value).toBeNull();
      expect(isLoading.value).toBe(false);
    });

    it('returns an empty list when no credentials are registered', async () => {
      axiosMock.onGet('/auth/webauthn-credentials').reply(200, {
        credentials: [],
        count: 0,
      });

      const { fetchWebAuthnCredentials, error } = useWebAuthn();
      const result = await fetchWebAuthnCredentials();

      expect(result).toEqual([]);
      expect(error.value).toBeNull();
    });

    it('returns null and sets error on 401', async () => {
      axiosMock.onGet('/auth/webauthn-credentials').reply(401, {
        error: 'Authentication required',
      });

      const { fetchWebAuthnCredentials, error, isLoading } = useWebAuthn();
      const result = await fetchWebAuthnCredentials();

      expect(result).toBeNull();
      expect(error.value).toBe('Authentication required');
      expect(isLoading.value).toBe(false);
    });
  });

  describe('removeWebAuthn', () => {
    it('removes a credential with password confirmation', async () => {
      axiosMock.onPost('/auth/webauthn-remove').reply(200, { success: 'Removed' });

      const { removeWebAuthn, error } = useWebAuthn();
      const result = await removeWebAuthn('credential-id-123', 'testpassword');

      expect(result).toBe(true);
      expect(error.value).toBeNull();

      const body = JSON.parse(axiosMock.history.post[0].data);
      expect(body.webauthn_remove).toBe('credential-id-123');
      expect(body.password).toBe('testpassword');
      expect(body).toHaveProperty('shrimp');
    });

    it('removes a credential without a password and omits the password key', async () => {
      axiosMock.onPost('/auth/webauthn-remove').reply(200, { success: 'Removed' });

      const { removeWebAuthn, error } = useWebAuthn();
      const result = await removeWebAuthn('credential-id-123');

      expect(result).toBe(true);
      expect(error.value).toBeNull();

      const body = JSON.parse(axiosMock.history.post[0].data);
      expect(body.webauthn_remove).toBe('credential-id-123');
      expect(body).not.toHaveProperty('password');
      expect(body).toHaveProperty('shrimp');
    });

    it('returns false and sets error on a 200 error-body response', async () => {
      axiosMock.onPost('/auth/webauthn-remove').reply(200, {
        error: 'invalid password',
      });

      const { removeWebAuthn, error } = useWebAuthn();
      const result = await removeWebAuthn('credential-id-123', 'wrong');

      expect(result).toBe(false);
      expect(error.value).toBe('invalid password');
    });

    it('returns false and sets error on an HTTP error response', async () => {
      axiosMock.onPost('/auth/webauthn-remove').reply(401, {
        error: 'Authentication required',
      });

      const { removeWebAuthn, error, isLoading } = useWebAuthn();
      const result = await removeWebAuthn('credential-id-123');

      expect(result).toBe(false);
      expect(error.value).toBe('Authentication required');
      expect(isLoading.value).toBe(false);
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
      axiosMock.onPost('/auth/webauthn-login').replyOnce(422, {
        error: 'There was an error authenticating via WebAuthn',
        webauthn_auth: challengeOptions, // Raw JSON object
        webauthn_auth_challenge: 'challenge',
        webauthn_auth_challenge_hmac: 'hmac',
      });
      axiosMock.onPost('/auth/webauthn-login').replyOnce(200, { success: 'OK' });

      const { authenticateWebAuthn, isLoading } = useWebAuthn();

      await authenticateWebAuthn('user@example.com');
      expect(isLoading.value).toBe(false);
    });

    it('resets loading state after failed operation', async () => {
      axiosMock.onPost('/auth/webauthn-login').networkError();

      const { authenticateWebAuthn, isLoading } = useWebAuthn();

      await authenticateWebAuthn('user@example.com');
      expect(isLoading.value).toBe(false);
    });
  });
});
