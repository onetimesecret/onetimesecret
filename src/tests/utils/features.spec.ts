// src/tests/utils/features.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  isMagicLinksEnabled,
  isWebAuthnEnabled,
  hasPasswordlessMethods,
  getAuthFeatures,
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

  describe('getAuthFeatures', () => {
    it('returns correct object when all features enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: true, magic_links: true });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: true,
        webauthnEnabled: true,
      });
    });

    it('returns correct object when no features enabled', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: false, magic_links: false });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
      });
    });

    it('returns correct object when features is undefined', () => {
      getBootstrapValueMock.mockReturnValue(undefined);

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
      });
    });

    it('returns correct object with mixed enabled states', () => {
      getBootstrapValueMock.mockReturnValue({ webauthn: true, magic_links: false });

      const result = getAuthFeatures();

      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: true,
      });
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

    it('hasPasswordlessMethods returns false when window is undefined', () => {
      const result = hasPasswordlessMethods();
      expect(result).toBe(false);
    });

    it('getAuthFeatures returns all false when window is undefined', () => {
      const result = getAuthFeatures();
      expect(result).toEqual({
        magicLinksEnabled: false,
        webauthnEnabled: false,
      });
    });
  });
});
