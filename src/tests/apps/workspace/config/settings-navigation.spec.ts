// src/tests/apps/workspace/config/settings-navigation.spec.ts

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { ComposerTranslation } from 'vue-i18n';

// Mock feature flags before importing the module under test
vi.mock('@/utils/features', () => ({
  isFullAuthMode: vi.fn(() => false),
  isWebAuthnEnabled: vi.fn(() => false),
}));

import {
  getSettingsNavigation,
  getSettingsNavigationSections,
} from '@/apps/workspace/config/settings-navigation';
import { isFullAuthMode, isWebAuthnEnabled } from '@/utils/features';

const mockedIsFullAuthMode = vi.mocked(isFullAuthMode);
const mockedIsWebAuthnEnabled = vi.mocked(isWebAuthnEnabled);

// Minimal translation stub that returns the key path
const t = ((key: string) => key) as unknown as ComposerTranslation;

describe('settings-navigation config', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockedIsFullAuthMode.mockReturnValue(false);
    mockedIsWebAuthnEnabled.mockReturnValue(false);
  });

  describe('Security section visibility', () => {
    it('security section has visible callback that checks auth mode', () => {
      const sections = getSettingsNavigationSections(t);
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');

      expect(securityItem).toBeDefined();
      expect(securityItem?.visible).toBeTypeOf('function');
    });

    it('security section is visible when auth mode is full', () => {
      mockedIsFullAuthMode.mockReturnValue(true);

      const sections = getSettingsNavigationSections(t);
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');

      expect(securityItem?.visible?.()).toBe(true);
    });

    it('security section is hidden when auth mode is not full', () => {
      mockedIsFullAuthMode.mockReturnValue(false);

      const sections = getSettingsNavigationSections(t);
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');

      expect(securityItem?.visible?.()).toBe(false);
    });

    it('security item in flat navigation still carries visible callback', () => {
      // getSettingsNavigation (deprecated) does not filter item-level visibility;
      // that filtering happens in SettingsLayout.vue. The item is present but
      // callers must check visible() themselves.
      mockedIsFullAuthMode.mockReturnValue(false);

      const items = getSettingsNavigation(t);
      const securityItem = items.find((i) => i.id === 'security');

      expect(securityItem).toBeDefined();
      expect(securityItem?.visible?.()).toBe(false);
    });

    it('SettingsLayout-style filtering excludes security when not full mode', () => {
      mockedIsFullAuthMode.mockReturnValue(false);

      const sections = getSettingsNavigationSections(t);
      // Replicate SettingsLayout.vue filtering logic
      const visibleItems = sections.flatMap((section) =>
        section.items.filter((item) => (item.visible ? item.visible() : true))
      );
      const securityItem = visibleItems.find((i) => i.id === 'security');

      expect(securityItem).toBeUndefined();
    });

    it('SettingsLayout-style filtering includes security when full mode', () => {
      mockedIsFullAuthMode.mockReturnValue(true);

      const sections = getSettingsNavigationSections(t);
      const visibleItems = sections.flatMap((section) =>
        section.items.filter((item) => (item.visible ? item.visible() : true))
      );
      const securityItem = visibleItems.find((i) => i.id === 'security');

      expect(securityItem).toBeDefined();
      expect(securityItem?.to).toBe('/account/settings/security');
    });
  });

  describe('Security section children', () => {
    it('includes password, mfa, sessions, and recovery-codes children', () => {
      mockedIsFullAuthMode.mockReturnValue(true);

      const items = getSettingsNavigation(t);
      const securityItem = items.find((i) => i.id === 'security');
      const childIds = securityItem?.children?.map((c) => c.id) ?? [];

      expect(childIds).toContain('password');
      expect(childIds).toContain('mfa');
      expect(childIds).toContain('sessions');
      expect(childIds).toContain('recovery-codes');
    });

    it('passkeys child is visible only when WebAuthn is enabled', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedIsWebAuthnEnabled.mockReturnValue(false);

      const items = getSettingsNavigation(t);
      const securityItem = items.find((i) => i.id === 'security');
      const passkeysChild = securityItem?.children?.find((c) => c.id === 'passkeys');

      expect(passkeysChild).toBeDefined();
      expect(passkeysChild?.visible?.()).toBe(false);

      mockedIsWebAuthnEnabled.mockReturnValue(true);
      expect(passkeysChild?.visible?.()).toBe(true);
    });
  });

  describe('Non-security sections always present', () => {
    it('profile section is always included regardless of auth mode', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      const items = getSettingsNavigation(t);
      expect(items.find((i) => i.id === 'profile')).toBeDefined();

      mockedIsFullAuthMode.mockReturnValue(true);
      const itemsFull = getSettingsNavigation(t);
      expect(itemsFull.find((i) => i.id === 'profile')).toBeDefined();
    });

    it('caution section is always included regardless of auth mode', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      const items = getSettingsNavigation(t);
      expect(items.find((i) => i.id === 'caution')).toBeDefined();
    });

    it('region section is always included regardless of auth mode', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      const items = getSettingsNavigation(t);
      expect(items.find((i) => i.id === 'region')).toBeDefined();
    });
  });

  describe('API section visibility', () => {
    it('API section is visible', () => {
      const sections = getSettingsNavigationSections(t);
      const accountSection = sections.find((s) => s.id === 'account');
      const apiItem = accountSection?.items.find((i) => i.id === 'api');

      expect(apiItem?.visible?.()).toBe(true);
    });
  });
});
