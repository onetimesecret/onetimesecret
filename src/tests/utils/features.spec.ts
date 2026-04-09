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
  getRestrictTo,
  hasPasswordlessMethods,
  getAuthFeatures,
  isOrganizationSwitcherEnabled,
  isOrgsSsoEnabled,
  isOrgsCustomMailEnabled,
  isOrgsIncomingSecretsEnabled,
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

  // ── restrict_to / single-auth-method tests ────────────────────────

  describe('getRestrictTo', () => {
    it('returns null when restrict_to is not set', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(getRestrictTo()).toBeNull();
    });

    it('returns null when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(getRestrictTo()).toBeNull();
    });

    it('returns null when restrict_to is null', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: null });
      expect(getRestrictTo()).toBeNull();
    });

    it('returns "password" when restrict_to is "password"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'password' });
      expect(getRestrictTo()).toBe('password');
    });

    it('returns "email_auth" when restrict_to is "email_auth"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'email_auth' });
      expect(getRestrictTo()).toBe('email_auth');
    });

    it('returns "webauthn" when restrict_to is "webauthn"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'webauthn' });
      expect(getRestrictTo()).toBe('webauthn');
    });

    it('returns "sso" when restrict_to is "sso"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'sso' });
      expect(getRestrictTo()).toBe('sso');
    });

    it('returns null for unrecognised values', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'carrier_pigeon' });
      expect(getRestrictTo()).toBeNull();
    });

    it('returns null for boolean true (not a valid value)', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: true });
      expect(getRestrictTo()).toBeNull();
    });

    it('returns null for number (not a valid value)', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 42 });
      expect(getRestrictTo()).toBeNull();
    });
  });

  describe('isSsoOnlyMode', () => {
    it('returns true when restrict_to is "sso"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'sso' });
      expect(isSsoOnlyMode()).toBe(true);
    });

    it('returns false when restrict_to is null', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(isSsoOnlyMode()).toBe(false);
    });

    it('returns false when restrict_to is "password"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'password' });
      expect(isSsoOnlyMode()).toBe(false);
    });

    it('returns false when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(isSsoOnlyMode()).toBe(false);
    });
  });

  describe('isPasswordOnlyMode', () => {
    it('returns true when restrict_to is "password"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'password' });
      expect(isPasswordOnlyMode()).toBe(true);
    });

    it('returns false when restrict_to is null', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(isPasswordOnlyMode()).toBe(false);
    });

    it('returns false when restrict_to is "sso"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'sso' });
      expect(isPasswordOnlyMode()).toBe(false);
    });

    it('returns false when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(isPasswordOnlyMode()).toBe(false);
    });
  });

  describe('isEmailAuthOnlyMode', () => {
    it('returns true when restrict_to is "email_auth"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'email_auth' });
      expect(isEmailAuthOnlyMode()).toBe(true);
    });

    it('returns false when restrict_to is null', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(isEmailAuthOnlyMode()).toBe(false);
    });

    it('returns false when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(isEmailAuthOnlyMode()).toBe(false);
    });
  });

  describe('isWebAuthnOnlyMode', () => {
    it('returns true when restrict_to is "webauthn"', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'webauthn' });
      expect(isWebAuthnOnlyMode()).toBe(true);
    });

    it('returns false when restrict_to is null', () => {
      getBootstrapValueMock.mockReturnValue({});
      expect(isWebAuthnOnlyMode()).toBe(false);
    });

    it('returns false when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);
      expect(isWebAuthnOnlyMode()).toBe(false);
    });
  });

  // ── getAuthFeatures ───────────────────────────────────────────────

  describe('getAuthFeatures', () => {
    it('returns correct object when all features enabled with sso restriction', () => {
      getBootstrapValueMock.mockReturnValue({
        webauthn: true, magic_links: true, sso: true, restrict_to: 'sso',
      });

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: true,
        webauthnEnabled: true,
        ssoEnabled: true,
        restrictTo: 'sso',
      });
    });

    it('returns correct object when no features enabled', () => {
      getBootstrapValueMock.mockReturnValue({
        webauthn: false, magic_links: false, sso: false,
      });

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        restrictTo: null,
      });
    });

    it('returns correct object when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        restrictTo: null,
      });
    });

    it('returns restrictTo: "password" when set', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'password' });

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        restrictTo: 'password',
      });
    });

    it('returns restrictTo: "email_auth" when set', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'email_auth' });

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        restrictTo: 'email_auth',
      });
    });

    it('returns restrictTo: "webauthn" when set', () => {
      getBootstrapValueMock.mockReturnValue({ restrict_to: 'webauthn' });

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        restrictTo: 'webauthn',
      });
    });

    it('returns correct object with sso as object with enabled: true', () => {
      getBootstrapValueMock.mockReturnValue({
        webauthn: false,
        magic_links: false,
        sso: { enabled: true, provider_name: 'Zitadel' },
      });

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: true,
        restrictTo: null,
      });
    });

    it('returns correct object with sso as object with enabled: false', () => {
      getBootstrapValueMock.mockReturnValue({
        webauthn: true,
        magic_links: true,
        sso: { enabled: false },
      });

      expect(getAuthFeatures()).toEqual({
        magicLinksEnabled: true,
        webauthnEnabled: true,
        ssoEnabled: false,
        restrictTo: null,
      });
    });
  });

  // ── Organizations ─────────────────────────────────────────────────

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

  describe('isOrgsCustomMailEnabled', () => {
    it('returns true when organizations.custom_mail_enabled is true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { custom_mail_enabled: true } });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when organizations.custom_mail_enabled is false', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { custom_mail_enabled: false } });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations object is empty', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: {} });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.custom_mail_enabled is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { custom_mail_enabled: 'yes' } });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.custom_mail_enabled is null', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { custom_mail_enabled: null } });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.custom_mail_enabled is 1 (number)', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { custom_mail_enabled: 1 } });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });

    it('returns true when both enabled and custom_mail_enabled are true', () => {
      getBootstrapValueMock.mockReturnValue({
        organizations: { enabled: true, custom_mail_enabled: true },
      });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(true);
    });

    it('returns false when enabled is true but custom_mail_enabled is false', () => {
      getBootstrapValueMock.mockReturnValue({
        organizations: { enabled: true, custom_mail_enabled: false },
      });

      const result = isOrgsCustomMailEnabled();

      expect(result).toBe(false);
    });
  });

  describe('isOrgsIncomingSecretsEnabled', () => {
    it('returns true when organizations.incoming_secrets_enabled is true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { incoming_secrets_enabled: true } });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(true);
      expect(getBootstrapValueMock).toHaveBeenCalledWith('features');
    });

    it('returns false when organizations.incoming_secrets_enabled is false', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { incoming_secrets_enabled: false } });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations object is empty', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: {} });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations is undefined', () => {
      getBootstrapValueMock.mockReturnValue({});

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when features object is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.incoming_secrets_enabled is truthy but not exactly true', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { incoming_secrets_enabled: 'yes' } });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.incoming_secrets_enabled is null', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { incoming_secrets_enabled: null } });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });

    it('returns false when organizations.incoming_secrets_enabled is 1 (number)', () => {
      getBootstrapValueMock.mockReturnValue({ organizations: { incoming_secrets_enabled: 1 } });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });

    it('returns true when both enabled and incoming_secrets_enabled are true', () => {
      getBootstrapValueMock.mockReturnValue({
        organizations: { enabled: true, incoming_secrets_enabled: true },
      });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(true);
    });

    it('returns false when enabled is true but incoming_secrets_enabled is false', () => {
      getBootstrapValueMock.mockReturnValue({
        organizations: { enabled: true, incoming_secrets_enabled: false },
      });

      const result = isOrgsIncomingSecretsEnabled();

      expect(result).toBe(false);
    });
  });

  // ── SSR safety (window undefined) ─────────────────────────────────

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

    it('getRestrictTo returns null when window is undefined', () => {
      const result = getRestrictTo();
      expect(result).toBeNull();
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

    it('getAuthFeatures returns all defaults when window is undefined', () => {
      const result = getAuthFeatures();
      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
        ssoEnabled: false,
        restrictTo: null,
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

    it('isOrgsCustomMailEnabled returns false when window is undefined', () => {
      const result = isOrgsCustomMailEnabled();
      expect(result).toBe(false);
    });

    it('isOrgsIncomingSecretsEnabled returns false when window is undefined', () => {
      const result = isOrgsIncomingSecretsEnabled();
      expect(result).toBe(false);
    });
  });
});
