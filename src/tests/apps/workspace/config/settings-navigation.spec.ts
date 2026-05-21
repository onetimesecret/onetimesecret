// src/tests/apps/workspace/config/settings-navigation.spec.ts

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { ComposerTranslation } from 'vue-i18n';

// Mock feature flags before importing the module under test
vi.mock('@/utils/features', () => ({
  isFullAuthMode: vi.fn(() => false),
  isSsoOnlyMode: vi.fn(() => false),
  isWebAuthnEnabled: vi.fn(() => false),
  hasPassword: vi.fn(() => false),
}));

import {
  getSettingsNavigation,
  getSettingsNavigationSections,
} from '@/apps/workspace/config/settings-navigation';
import { isFullAuthMode, isSsoOnlyMode, isWebAuthnEnabled, hasPassword } from '@/utils/features';

const mockedIsFullAuthMode = vi.mocked(isFullAuthMode);
const mockedIsSsoOnlyMode = vi.mocked(isSsoOnlyMode);
const mockedIsWebAuthnEnabled = vi.mocked(isWebAuthnEnabled);
const mockedHasPassword = vi.mocked(hasPassword);

// Minimal translation stub that returns the key path
const t = ((key: string) => key) as unknown as ComposerTranslation;

describe('settings-navigation config', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockedIsFullAuthMode.mockReturnValue(false);
    mockedIsSsoOnlyMode.mockReturnValue(false);
    mockedIsWebAuthnEnabled.mockReturnValue(false);
    mockedHasPassword.mockReturnValue(false);
  });

  describe('Security section visibility', () => {
    it('security section has visible callback that checks auth mode', () => {
      const sections = getSettingsNavigationSections(t);
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');

      expect(securityItem).toBeDefined();
      expect(securityItem?.visible).toBeTypeOf('function');
    });

    it('security section is visible when auth mode is full and user has password', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);

      const sections = getSettingsNavigationSections(t);
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');

      expect(securityItem?.visible?.()).toBe(true);
    });

    it('security section is hidden when auth mode is not full', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      mockedHasPassword.mockReturnValue(true);

      const sections = getSettingsNavigationSections(t);
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');

      expect(securityItem?.visible?.()).toBe(false);
    });

    it('security section is hidden in SSO-only mode even when isFullAuthMode()', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedIsSsoOnlyMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(false);

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

    it('SettingsLayout-style filtering includes security when full mode and has password', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);

      const sections = getSettingsNavigationSections(t);
      const visibleItems = sections.flatMap((section) =>
        section.items.filter((item) => (item.visible ? item.visible() : true))
      );
      const securityItem = visibleItems.find((i) => i.id === 'security');

      expect(securityItem).toBeDefined();
      expect(securityItem?.to).toBe('/account/settings/security');
    });

    it('SettingsLayout-style filtering excludes security for SSO-only users', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedIsSsoOnlyMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(false);

      const sections = getSettingsNavigationSections(t);
      const visibleItems = sections.flatMap((section) =>
        section.items.filter((item) => (item.visible ? item.visible() : true))
      );
      const securityItem = visibleItems.find((i) => i.id === 'security');

      expect(securityItem).toBeUndefined();
    });
  });

  describe('Security section children', () => {
    it('includes password, mfa, sessions, and recovery-codes children', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);

      const items = getSettingsNavigation(t);
      const securityItem = items.find((i) => i.id === 'security');
      const childIds = securityItem?.children?.map((c) => c.id) ?? [];

      expect(childIds).toContain('password');
      expect(childIds).toContain('mfa');
      expect(childIds).toContain('sessions');
      expect(childIds).toContain('recovery-codes');
    });

    it('password, mfa, recovery-codes children hidden when !hasPassword()', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(false);

      const items = getSettingsNavigation(t);
      const securityItem = items.find((i) => i.id === 'security');
      const children = securityItem?.children ?? [];

      const passwordChild = children.find((c) => c.id === 'password');
      const mfaChild = children.find((c) => c.id === 'mfa');
      const recoveryChild = children.find((c) => c.id === 'recovery-codes');

      expect(passwordChild?.visible?.()).toBe(false);
      expect(mfaChild?.visible?.()).toBe(false);
      expect(recoveryChild?.visible?.()).toBe(false);
    });

    it('password, mfa, recovery-codes children visible when hasPassword()', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);

      const items = getSettingsNavigation(t);
      const securityItem = items.find((i) => i.id === 'security');
      const children = securityItem?.children ?? [];

      const passwordChild = children.find((c) => c.id === 'password');
      const mfaChild = children.find((c) => c.id === 'mfa');
      const recoveryChild = children.find((c) => c.id === 'recovery-codes');

      expect(passwordChild?.visible?.()).toBe(true);
      expect(mfaChild?.visible?.()).toBe(true);
      expect(recoveryChild?.visible?.()).toBe(true);
    });

    it('sessions child visible when isFullAuthMode() regardless of hasPassword()', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(false);

      const items = getSettingsNavigation(t);
      const securityItem = items.find((i) => i.id === 'security');
      const sessionsChild = securityItem?.children?.find((c) => c.id === 'sessions');

      // sessions has no visible callback — always visible when parent is visible
      expect(sessionsChild).toBeDefined();
      expect(sessionsChild?.visible).toBeUndefined();
    });

    it('passkeys child is visible only when WebAuthn is enabled', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);
      mockedIsWebAuthnEnabled.mockReturnValue(false);

      const itemsOff = getSettingsNavigation(t);
      const passkeysOff = itemsOff
        .find((i) => i.id === 'security')
        ?.children?.find((c) => c.id === 'passkeys');
      expect(passkeysOff).toBeDefined();
      expect(passkeysOff?.visible?.()).toBe(false);

      // Features are resolved at build time, so callers must rebuild the
      // navigation to pick up flag changes (reactive consumers do this via
      // a Vue computed that re-runs when bootstrap state mutates).
      mockedIsWebAuthnEnabled.mockReturnValue(true);
      const itemsOn = getSettingsNavigation(t);
      const passkeysOn = itemsOn
        .find((i) => i.id === 'security')
        ?.children?.find((c) => c.id === 'passkeys');
      expect(passkeysOn?.visible?.()).toBe(true);
    });
  });

  describe('Explicit features parameter', () => {
    it('uses provided features object instead of imported predicates', () => {
      // Default features.ts mocks return false for everything. Passing an
      // explicit features object should override that — this is how
      // SettingsLayout.vue feeds reactive bootstrap state into the builder.
      const sections = getSettingsNavigationSections(t, {
        hasPassword: true,
        isFullAuthMode: true,
        isSsoOnlyMode: false,
        isWebAuthnEnabled: true,
      });
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');
      const passkeysChild = securityItem?.children?.find((c) => c.id === 'passkeys');

      expect(securityItem?.visible?.()).toBe(true);
      expect(passkeysChild?.visible?.()).toBe(true);
    });

    it('honours SSO-only flag in explicit features even when other flags would show tabs', () => {
      // Regression guard: the SSO-only intent must still hide Security/Region/Caution
      // even when isFullAuthMode and hasPassword would otherwise enable them.
      const sections = getSettingsNavigationSections(t, {
        hasPassword: true,
        isFullAuthMode: true,
        isSsoOnlyMode: true,
        isWebAuthnEnabled: true,
      });
      const security = sections.find((s) => s.id === 'account')?.items.find((i) => i.id === 'security');
      const region = sections.find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'region');
      const caution = sections.find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'caution');

      expect(security?.visible?.()).toBe(false);
      expect(region?.visible?.()).toBe(false);
      expect(caution?.visible?.()).toBe(false);
    });
  });

  describe('Non-security sections visibility', () => {
    it('profile section is always included regardless of auth mode', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      const items = getSettingsNavigation(t);
      expect(items.find((i) => i.id === 'profile')).toBeDefined();

      mockedIsFullAuthMode.mockReturnValue(true);
      const itemsFull = getSettingsNavigation(t);
      expect(itemsFull.find((i) => i.id === 'profile')).toBeDefined();
    });

    it('caution section is visible when not SSO-only', () => {
      mockedIsSsoOnlyMode.mockReturnValue(false);
      mockedHasPassword.mockReturnValue(true);
      const items = getSettingsNavigation(t);
      const cautionItem = items.find((i) => i.id === 'caution');
      expect(cautionItem).toBeDefined();
      expect(cautionItem?.visible?.()).toBe(true);
    });

    it('caution section is hidden in SSO-only mode', () => {
      mockedIsSsoOnlyMode.mockReturnValue(true);
      const items = getSettingsNavigation(t);
      const cautionItem = items.find((i) => i.id === 'caution');
      expect(cautionItem?.visible?.()).toBe(false);
    });

    it('region section is visible when not SSO-only', () => {
      mockedIsSsoOnlyMode.mockReturnValue(false);
      mockedHasPassword.mockReturnValue(true);
      const items = getSettingsNavigation(t);
      const regionItem = items.find((i) => i.id === 'region');
      expect(regionItem).toBeDefined();
      expect(regionItem?.visible?.()).toBe(true);
    });

    it('region section is hidden in SSO-only mode', () => {
      mockedIsSsoOnlyMode.mockReturnValue(true);
      const items = getSettingsNavigation(t);
      const regionItem = items.find((i) => i.id === 'region');
      expect(regionItem?.visible?.()).toBe(false);
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
