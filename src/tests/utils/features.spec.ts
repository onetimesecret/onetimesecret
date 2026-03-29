// src/tests/utils/features.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  isMagicLinksEnabled,
  isWebAuthnEnabled,
  isSsoEnabled,
  isSsoOnlyMode,
  isLockoutEnabled,
  isPasswordRequirementsEnabled,
  isPasswordOnlyMode,
  isEmailAuthOnlyMode,
  isWebAuthnOnlyMode,
  activeSingleAuthMethod,
  hasPasswordlessMethods,
  getAuthFeatures,
  isOrganizationSwitcherEnabled,
  isOrgsSsoEnabled,
} from '@/utils/features';
import { _resetForTesting } from '@/services/bootstrap.service';

// Mock the bootstrap service
vi.mock('@/services/bootstrap.service', async () => {
  const actual = await vi.importActual<typeof import('@/services/bootstrap.service')>(
    '@/services/bootstrap.service'
  );
  return {
    ...actual,
    getBootstrapValue: vi.fn(),
  };
});

describe('features utility', () => {
  // Import the mocked function for configuration in tests
  let getBootstrapValueMock: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    // Get the mocked function reference
    const bootstrapService = await import('@/services/bootstrap.service');
    getBootstrapValueMock = vi.mocked(bootstrapService.getBootstrapValue);

    // Reset all mocks before each test
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('isWebAuthnEnabled', () => {
    it('returns true when webauthn feature is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: true });

      const result = isWebAuthnEnabled();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when webauthn feature is disabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: false });

      const result = isWebAuthnEnabled();

      expect(result).toBe(false);
    });

    it('returns false when webauthn feature is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isWebAuthnEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isWebAuthnEnabled();

      expect(result).toBe(false);
    });

    it('returns false when webauthn is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: 'yes' });

      const result = isWebAuthnEnabled();

      expect(result).toBe(false);
    });
  });

  describe('isMagicLinksEnabled', () => {
    it('returns true when magic_links feature is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ magic_links: true });

      const result = isMagicLinksEnabled();

      expect(result).toBe(true);
    });

    it('returns true when email_auth feature is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ email_auth: true });

      const result = isMagicLinksEnabled();

      expect(result).toBe(true);
    });

    it('returns true when both magic_links and email_auth are enabled', () => {
      getBootstrapValueMock.mockReturnValue({ magic_links: true, email_auth: true });

      const result = isMagicLinksEnabled();

      expect(result).toBe(true);
    });

    it('returns false when both magic_links and email_auth are disabled', () => {
      getBootstrapValueMock.mockReturnValue({ magic_links: false, email_auth: false });

      const result = isMagicLinksEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isMagicLinksEnabled();

      expect(result).toBe(false);
    });

    it('returns false when neither magic_links nor email_auth exist', () => {
      getBootstrapValueMock.mockReturnValue({ other_feature: true });

      const result = isMagicLinksEnabled();

      expect(result).toBe(false);
    });

    it('returns true with only email_auth and magic_links false', () => {
      getBootstrapValueMock.mockReturnValue({ magic_links: false, email_auth: true });

      const result = isMagicLinksEnabled();

      expect(result).toBe(true);
    });
  });

  describe('isLockoutEnabled', () => {
    it('returns true when lockout feature is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ lockout: true });

      const result = isLockoutEnabled();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when lockout feature is disabled', () => {
      getBootstrapValueMock.mockReturnValue({ lockout: false });

      const result = isLockoutEnabled();

      expect(result).toBe(false);
    });

    it('returns false when lockout feature is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isLockoutEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isLockoutEnabled();

      expect(result).toBe(false);
    });

    it('returns false when lockout is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ lockout: 'yes' });

      const result = isLockoutEnabled();

      expect(result).toBe(false);
    });
  });

  describe('isPasswordRequirementsEnabled', () => {
    it('returns true when password_requirements feature is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ password_requirements: true });

      const result = isPasswordRequirementsEnabled();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when password_requirements feature is disabled', () => {
      getBootstrapValueMock.mockReturnValue({ password_requirements: false });

      const result = isPasswordRequirementsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when password_requirements feature is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isPasswordRequirementsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isPasswordRequirementsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when password_requirements is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ password_requirements: 'yes' });

      const result = isPasswordRequirementsEnabled();

      expect(result).toBe(false);
    });
  });

  describe('hasPasswordlessMethods', () => {
    it('returns true when only WebAuthn is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: true, magic_links: false });

      const result = hasPasswordlessMethods();

      expect(result).toBe(true);
    });

    it('returns true when only magic links is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: false, magic_links: true });

      const result = hasPasswordlessMethods();

      expect(result).toBe(true);
    });

    it('returns true when only email_auth is enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: false, email_auth: true });

      const result = hasPasswordlessMethods();

      expect(result).toBe(true);
    });

    it('returns true when both WebAuthn and magic links are enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: true, magic_links: true });

      const result = hasPasswordlessMethods();

      expect(result).toBe(true);
    });

    it('returns false when no passwordless methods are enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: false, magic_links: false, email_auth: false });

      const result = hasPasswordlessMethods();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = hasPasswordlessMethods();

      expect(result).toBe(false);
    });
  });

  describe('isSsoEnabled', () => {
    describe('boolean form', () => {
      it('returns true when sso feature is enabled (boolean true)', () => {
        getBootstrapValueMock.mockReturnValue({ sso: true });

        const result = isSsoEnabled();

        expect(result).toBe(true);
        expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
      });

      it('returns false when sso feature is disabled (boolean false)', () => {
        getBootstrapValueMock.mockReturnValue({ sso: false });

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });

      it('returns false when sso is truthy but not exactly true', () => {
        getBootstrapValueMock.mockReturnValue({ sso: 'yes' });

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });
    });

    describe('object form', () => {
      it('returns true when sso is object with enabled: true', () => {
        getBootstrapValueMock.mockReturnValue({
          sso: { enabled: true },
        });

        const result = isSsoEnabled();

        expect(result).toBe(true);
      });

      it('returns true when sso is object with enabled: true and provider_name', () => {
        getBootstrapValueMock.mockReturnValue({
          sso: { enabled: true, provider_name: 'Okta' },
        });

        const result = isSsoEnabled();

        expect(result).toBe(true);
      });

      it('returns false when sso is object with enabled: false', () => {
        getBootstrapValueMock.mockReturnValue({
          sso: { enabled: false },
        });

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });

      it('returns false when sso is object with enabled: false and provider_name', () => {
        getBootstrapValueMock.mockReturnValue({
          sso: { enabled: false, provider_name: 'Okta' },
        });

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });

      it('returns false when sso is object without enabled property', () => {
        getBootstrapValueMock.mockReturnValue({
          sso: { provider_name: 'Okta' },
        });

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });

      it('returns false when sso is empty object', () => {
        getBootstrapValueMock.mockReturnValue({
          sso: {},
        });

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });
    });

    describe('edge cases', () => {
      it('returns false when sso feature is undefined', () => {
        getBootstrapValueMock.mockReturnValue({});

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });

      it('returns false when features object is undefined', () => {
        getBootstrapValueMock.mockReturnValue(undefined);

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });

      it('returns false when sso is null', () => {
        getBootstrapValueMock.mockReturnValue({ sso: null });

        const result = isSsoEnabled();

        expect(result).toBe(false);
      });
    });
  });

  describe('isSsoOnlyMode', () => {
    it('returns true when sso_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ sso_only: true });

      const result = isSsoOnlyMode();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when sso_only is false', () => {
      getBootstrapValueMock.mockReturnValue({ sso_only: false });

      const result = isSsoOnlyMode();

      expect(result).toBe(false);
    });

    it('returns false when sso_only is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isSsoOnlyMode();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isSsoOnlyMode();

      expect(result).toBe(false);
    });

    it('returns false when sso_only is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ sso_only: 'yes' });

      const result = isSsoOnlyMode();

      expect(result).toBe(false);
    });

    it('returns false when sso_only is null', () => {
      getBootstrapValueMock.mockReturnValue({ sso_only: null });

      const result = isSsoOnlyMode();

      expect(result).toBe(false);
    });
  });

  describe('isPasswordOnlyMode', () => {
    it('returns true when password_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ password_only: true });
      expect(isPasswordOnlyMode()).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when password_only is false', () => {
      getBootstrapValueMock.mockReturnValue({ password_only: false });
      expect(isPasswordOnlyMode()).toBe(false);
    });

    it('returns false when password_only is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(isPasswordOnlyMode()).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(isPasswordOnlyMode()).toBe(false);
    });

    it('returns false when password_only is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ password_only: 'yes' });
      expect(isPasswordOnlyMode()).toBe(false);
    });
  });

  describe('isEmailAuthOnlyMode', () => {
    it('returns true when email_auth_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ email_auth_only: true });
      expect(isEmailAuthOnlyMode()).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when email_auth_only is false', () => {
      getBootstrapValueMock.mockReturnValue({ email_auth_only: false });
      expect(isEmailAuthOnlyMode()).toBe(false);
    });

    it('returns false when email_auth_only is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(isEmailAuthOnlyMode()).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(isEmailAuthOnlyMode()).toBe(false);
    });

    it('returns false when email_auth_only is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ email_auth_only: 'yes' });
      expect(isEmailAuthOnlyMode()).toBe(false);
    });
  });

  describe('isWebAuthnOnlyMode', () => {
    it('returns true when webauthn_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn_only: true });
      expect(isWebAuthnOnlyMode()).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when webauthn_only is false', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn_only: false });
      expect(isWebAuthnOnlyMode()).toBe(false);
    });

    it('returns false when webauthn_only is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(isWebAuthnOnlyMode()).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(isWebAuthnOnlyMode()).toBe(false);
    });

    it('returns false when webauthn_only is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn_only: 'yes' });
      expect(isWebAuthnOnlyMode()).toBe(false);
    });
  });

  describe('activeSingleAuthMethod', () => {
    it('returns null when no *_only flag is set', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(activeSingleAuthMethod()).toBeNull();
    });

    it('returns null when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(activeSingleAuthMethod()).toBeNull();
    });

    it('returns "password_only" when password_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ password_only: true });
      expect(activeSingleAuthMethod()).toBe('password_only');
    });

    it('returns "email_auth_only" when email_auth_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ email_auth_only: true });
      expect(activeSingleAuthMethod()).toBe('email_auth_only');
    });

    it('returns "webauthn_only" when webauthn_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn_only: true });
      expect(activeSingleAuthMethod()).toBe('webauthn_only');
    });

    it('returns "sso_only" when sso_only is true', () => {
      getBootstrapValueMock.mockReturnValue({ sso_only: true });
      expect(activeSingleAuthMethod()).toBe('sso_only');
    });

    it('returns first match when multiple are set (password_only wins)', () => {
      getBootstrapValueMock.mockReturnValue({ password_only: true, sso_only: true });
      expect(activeSingleAuthMethod()).toBe('password_only');
    });
  });

  describe('getAuthFeatures', () => {
    it('returns correct object when all features enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: true, magic_links: true, sso: true, sso_only: true });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: true,
        webauthnEnabled: true,
        ssoEnabled: true,
        ssoOnly: true,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns correct object when no features enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: false, magic_links: false, sso: false, sso_only: false });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns correct object when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns correct object with mixed enabled states', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: true, magic_links: false, sso: true });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: true,
        ssoEnabled: true,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns correct object with only sso enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: false, magic_links: false, sso: true });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: true,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns correct object with sso as object with enabled: true', () => {
      getBootstrapValueMock.mockReturnValue({
        webauthn: false,
        magic_links: false,
        sso: { enabled: true, provider_name: 'Zitadel' },
      });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: true,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns correct object with sso as object with enabled: false', () => {
      getBootstrapValueMock.mockReturnValue({
        webauthn: true,
        magic_links: true,
        sso: { enabled: false },
      });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: true,
        webauthnEnabled: true,
        ssoEnabled: false,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns ssoOnly true when sso_only flag is set', () => {
      getBootstrapValueMock.mockReturnValue({
        webauthn: false,
        magic_links: false,
        sso: { enabled: true },
        sso_only: true,
      });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: true,
        ssoOnly: true,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns passwordOnly true when password_only flag is set', () => {
      getBootstrapValueMock.mockReturnValue({ password_only: true });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        ssoOnly: false,
        passwordOnly: true,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('returns emailAuthOnly true when email_auth_only flag is set', () => {
      getBootstrapValueMock.mockReturnValue({ email_auth_only: true });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: true,
        webauthnOnly: false,
      });
    });

    it('returns webauthnOnly true when webauthn_only flag is set', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn_only: true });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: true,
      });
    });
  });

  describe('isOrganizationSwitcherEnabled', () => {
    it('returns true when organizations.enabled is true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { enabled: true } });

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when organizations.enabled is false', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { enabled: false } });

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations object is empty', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: {} });

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.enabled is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { enabled: 'yes' } });

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.enabled is null', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { enabled: null } });

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.enabled is 1 (number)', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { enabled: 1 } });

      const result = isOrganizationSwitcherEnabled();

      expect(result).toBe(false);
    });
  });

  describe('isOrgsSsoEnabled', () => {
    it('returns true when organizations.sso_enabled is true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { sso_enabled: true } });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when organizations.sso_enabled is false', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { sso_enabled: false } });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations object is empty', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: {} });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.sso_enabled is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { sso_enabled: 'yes' } });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.sso_enabled is null', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { sso_enabled: null } });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.sso_enabled is 1 (number)', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { sso_enabled: 1 } });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });

    it('returns true when both enabled and sso_enabled are true', () => {
      getBootstrapValueMock.mockReturnValue({
        organizations: { enabled: true, sso_enabled: true },
      });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(true);
    });

    it('returns false when enabled is true but sso_enabled is false', () => {
      getBootstrapValueMock.mockReturnValue({
        organizations: { enabled: true, sso_enabled: false },
      });

      const result = isOrgsSsoEnabled();

      expect(result).toBe(false);
    });
  });

  describe('SSR safety (window undefined)', () => {
    // Store original window reference
    const originalWindow = global.window;

    beforeEach(() => {
      // Temporarily remove window to simulate SSR
      // @ts-expect-error - intentionally setting to undefined for SSR simulation
      delete global.window;
    });

    afterEach(() => {
      // Restore window
      global.window = originalWindow;
    });

    it('isWebAuthnEnabled returns false when window is undefined', () => {
      const result = isWebAuthnEnabled();
      expect(result).toBe(false);
    });

    it('isMagicLinksEnabled returns false when window is undefined', () => {
      const result = isMagicLinksEnabled();
      expect(result).toBe(false);
    });

    it('isLockoutEnabled returns false when window is undefined', () => {
      const result = isLockoutEnabled();
      expect(result).toBe(false);
    });

    it('isPasswordRequirementsEnabled returns false when window is undefined', () => {
      const result = isPasswordRequirementsEnabled();
      expect(result).toBe(false);
    });

    it('hasPasswordlessMethods returns false when window is undefined', () => {
      const result = hasPasswordlessMethods();
      expect(result).toBe(false);
    });

    it('isSsoEnabled returns false when window is undefined', () => {
      const result = isSsoEnabled();
      expect(result).toBe(false);
    });

    it('isSsoOnlyMode returns false when window is undefined', () => {
      const result = isSsoOnlyMode();
      expect(result).toBe(false);
    });

    it('isPasswordOnlyMode returns false when window is undefined', () => {
      const result = isPasswordOnlyMode();
      expect(result).toBe(false);
    });

    it('isEmailAuthOnlyMode returns false when window is undefined', () => {
      const result = isEmailAuthOnlyMode();
      expect(result).toBe(false);
    });

    it('isWebAuthnOnlyMode returns false when window is undefined', () => {
      const result = isWebAuthnOnlyMode();
      expect(result).toBe(false);
    });

    it('activeSingleAuthMethod returns null when window is undefined', () => {
      const result = activeSingleAuthMethod();
      expect(result).toBeNull();
    });

    it('getAuthFeatures returns all false when window is undefined', () => {
      const result = getAuthFeatures();
      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        ssoOnly: false,
        passwordOnly: false,
        emailAuthOnly: false,
        webauthnOnly: false,
      });
    });

    it('isOrganizationSwitcherEnabled returns false when window is undefined', () => {
      const result = isOrganizationSwitcherEnabled();
      expect(result).toBe(false);
    });

    it('isOrgsSsoEnabled returns false when window is undefined', () => {
      const result = isOrgsSsoEnabled();
      expect(result).toBe(false);
    });
  });
});
