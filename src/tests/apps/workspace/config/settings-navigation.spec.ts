// src/tests/apps/workspace/config/settings-navigation.spec.ts

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { ComposerTranslation } from 'vue-i18n';
import type { NavigationFeatures } from '@/apps/workspace/config/settings-navigation';

// Mock feature flags before importing the module under test
vi.mock('@/utils/features', () => ({
  isFullAuthMode: vi.fn(() => false),
  isSsoOnlyMode: vi.fn(() => false),
  isWebAuthnEnabled: vi.fn(() => false),
  hasPassword: vi.fn(() => false),
  isOwnerOrAdmin: vi.fn(() => false),
}));

import {
  getSettingsNavigation,
  getSettingsNavigationSections,
} from '@/apps/workspace/config/settings-navigation';
import { isFullAuthMode, isSsoOnlyMode, isWebAuthnEnabled, hasPassword, isOwnerOrAdmin } from '@/utils/features';

const mockedIsFullAuthMode = vi.mocked(isFullAuthMode);
const mockedIsSsoOnlyMode = vi.mocked(isSsoOnlyMode);
const mockedIsWebAuthnEnabled = vi.mocked(isWebAuthnEnabled);
const mockedHasPassword = vi.mocked(hasPassword);
const mockedIsOwnerOrAdmin = vi.mocked(isOwnerOrAdmin);

// Minimal translation stub that returns the key path
const t = ((key: string) => key) as unknown as ComposerTranslation;

/** Helper: build a NavigationFeatures object from partial overrides. */
function makeFeatures(overrides: Partial<NavigationFeatures> = {}): NavigationFeatures {
  return {
    hasPassword: false,
    isFullAuthMode: true,
    isSsoOnlyMode: false,
    isOwnerOrAdmin: false,
    isWebAuthnEnabled: false,
    ...overrides,
  };
}

/** Helper: get visible section/item IDs using SettingsLayout filtering logic. */
function getVisibleItemIds(features: NavigationFeatures): string[] {
  const sections = getSettingsNavigationSections(t, features);
  return sections.flatMap((section) =>
    section.items.filter((item) => (item.visible ? item.visible() : true))
  ).map((i) => i.id);
}

/** Helper: get visible child IDs for a given parent item. */
function getVisibleChildIds(features: NavigationFeatures, parentId: string): string[] {
  const sections = getSettingsNavigationSections(t, features);
  const parent = sections.flatMap((s) => s.items).find((i) => i.id === parentId);
  if (!parent?.children) return [];
  return parent.children
    .filter((c) => (c.visible ? c.visible() : true))
    .map((c) => c.id);
}

describe('settings-navigation config', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockedIsFullAuthMode.mockReturnValue(false);
    mockedIsSsoOnlyMode.mockReturnValue(false);
    mockedIsWebAuthnEnabled.mockReturnValue(false);
    mockedHasPassword.mockReturnValue(false);
    mockedIsOwnerOrAdmin.mockReturnValue(false);
  });

  // ── Security section visibility ──────────────────────────────────

  describe('Security section visibility', () => {
    it('security section has visible callback that checks auth mode', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures());
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');

      expect(securityItem).toBeDefined();
      expect(securityItem?.visible).toBeTypeOf('function');
    });

    it('security section is visible when auth mode is full', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({ isFullAuthMode: true }));
      const securityItem = sections
        .find((s) => s.id === 'account')?.items.find((i) => i.id === 'security');

      expect(securityItem?.visible?.()).toBe(true);
    });

    it('security section is hidden when auth mode is not full', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({ isFullAuthMode: false }));
      const securityItem = sections
        .find((s) => s.id === 'account')?.items.find((i) => i.id === 'security');

      expect(securityItem?.visible?.()).toBe(false);
    });

    it('security section is visible in full auth mode regardless of SSO-only flag', () => {
      // After role-based gating change, security visibility is only f.isFullAuthMode.
      // SSO-only mode no longer hides the section itself (password sub-tabs handle
      // their own visibility via hasPassword).
      const sections = getSettingsNavigationSections(t, makeFeatures({
        isFullAuthMode: true,
        isSsoOnlyMode: true,
        hasPassword: false,
      }));
      const securityItem = sections
        .find((s) => s.id === 'account')?.items.find((i) => i.id === 'security');

      expect(securityItem?.visible?.()).toBe(true);
    });

    it('security item in flat navigation still carries visible callback', () => {
      const items = getSettingsNavigation(t, makeFeatures({ isFullAuthMode: false }));
      const securityItem = items.find((i) => i.id === 'security');

      expect(securityItem).toBeDefined();
      expect(securityItem?.visible?.()).toBe(false);
    });

    it('SettingsLayout-style filtering excludes security when not full mode', () => {
      const visibleIds = getVisibleItemIds(makeFeatures({ isFullAuthMode: false }));

      expect(visibleIds).not.toContain('security');
    });

    it('SettingsLayout-style filtering includes security when full mode', () => {
      const visibleIds = getVisibleItemIds(makeFeatures({ isFullAuthMode: true }));

      expect(visibleIds).toContain('security');
    });
  });

  // ── Security section children ────────────────────────────────────

  describe('Security section children', () => {
    it('includes password, mfa, sessions, and recovery-codes children', () => {
      const items = getSettingsNavigation(t, makeFeatures({ hasPassword: true }));
      const securityItem = items.find((i) => i.id === 'security');
      const childIds = securityItem?.children?.map((c) => c.id) ?? [];

      expect(childIds).toContain('password');
      expect(childIds).toContain('mfa');
      expect(childIds).toContain('sessions');
      expect(childIds).toContain('recovery-codes');
    });

    it('password, mfa, recovery-codes children hidden when !hasPassword', () => {
      const childIds = getVisibleChildIds(makeFeatures({ hasPassword: false }), 'security');

      expect(childIds).not.toContain('password');
      expect(childIds).not.toContain('mfa');
      expect(childIds).not.toContain('recovery-codes');
    });

    it('password, mfa, recovery-codes children visible when hasPassword', () => {
      const childIds = getVisibleChildIds(makeFeatures({ hasPassword: true }), 'security');

      expect(childIds).toContain('password');
      expect(childIds).toContain('mfa');
      expect(childIds).toContain('recovery-codes');
    });

    it('sessions child visible regardless of hasPassword', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({ hasPassword: false }));
      const securityItem = sections.flatMap((s) => s.items).find((i) => i.id === 'security');
      const sessionsChild = securityItem?.children?.find((c) => c.id === 'sessions');

      // sessions has no visible callback -- always visible when parent is visible
      expect(sessionsChild).toBeDefined();
      expect(sessionsChild?.visible).toBeUndefined();
    });

    it('passkeys child visible only when WebAuthn is enabled', () => {
      expect(
        getVisibleChildIds(makeFeatures({ isWebAuthnEnabled: false }), 'security')
      ).not.toContain('passkeys');

      expect(
        getVisibleChildIds(makeFeatures({ isWebAuthnEnabled: true }), 'security')
      ).toContain('passkeys');
    });
  });

  // ── Region and Caution Zone: role-based visibility ───────────────

  describe('Region section visibility (role-based)', () => {
    it('region section is visible when user is owner or admin', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({ isOwnerOrAdmin: true }));
      const regionItem = sections
        .find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'region');

      expect(regionItem?.visible?.()).toBe(true);
    });

    it('region section is hidden when user is a member', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({ isOwnerOrAdmin: false }));
      const regionItem = sections
        .find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'region');

      expect(regionItem?.visible?.()).toBe(false);
    });

    it('region section is hidden for members even with hasPassword', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({
        isOwnerOrAdmin: false,
        hasPassword: true,
      }));
      const regionItem = sections
        .find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'region');

      expect(regionItem?.visible?.()).toBe(false);
    });
  });

  describe('Caution Zone visibility (role-based)', () => {
    it('caution section is visible when user is owner or admin', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({ isOwnerOrAdmin: true }));
      const cautionItem = sections
        .find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'caution');

      expect(cautionItem?.visible?.()).toBe(true);
    });

    it('caution section is hidden when user is a member', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({ isOwnerOrAdmin: false }));
      const cautionItem = sections
        .find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'caution');

      expect(cautionItem?.visible?.()).toBe(false);
    });

    it('caution section is hidden for members even with hasPassword', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({
        isOwnerOrAdmin: false,
        hasPassword: true,
      }));
      const cautionItem = sections
        .find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'caution');

      expect(cautionItem?.visible?.()).toBe(false);
    });
  });

  // ── Explicit features parameter ─────────────────────────────────

  describe('Explicit features parameter', () => {
    it('uses provided features object instead of imported predicates', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({
        hasPassword: true,
        isFullAuthMode: true,
        isWebAuthnEnabled: true,
        isOwnerOrAdmin: true,
      }));
      const accountSection = sections.find((s) => s.id === 'account');
      const securityItem = accountSection?.items.find((i) => i.id === 'security');
      const passkeysChild = securityItem?.children?.find((c) => c.id === 'passkeys');

      expect(securityItem?.visible?.()).toBe(true);
      expect(passkeysChild?.visible?.()).toBe(true);
    });

    it('role-based gating hides Region/Caution for members with all other flags true', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures({
        hasPassword: true,
        isFullAuthMode: true,
        isSsoOnlyMode: false,
        isOwnerOrAdmin: false,
        isWebAuthnEnabled: true,
      }));
      const region = sections.find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'region');
      const caution = sections.find((s) => s.id === 'advanced')?.items.find((i) => i.id === 'caution');

      expect(region?.visible?.()).toBe(false);
      expect(caution?.visible?.()).toBe(false);
    });
  });

  // ── Visibility matrix (6 user personas) ──────────────────────────

  describe('Visibility matrix (user personas)', () => {
    // All personas assume isFullAuthMode: true (full Rodauth mode).
    // isSsoOnlyMode is not factored into visibility any more for account settings.

    const personas: Array<{
      label: string;
      features: NavigationFeatures;
      expectSecurity: boolean;
      expectPassword: boolean;
      expectMfa: boolean;
      expectRecovery: boolean;
      expectSessions: boolean;
      expectPasskeys: boolean;
      expectRegion: boolean;
      expectCaution: boolean;
    }> = [
      {
        label: 'Owner with password',
        features: makeFeatures({
          hasPassword: true, isOwnerOrAdmin: true, isWebAuthnEnabled: true,
        }),
        expectSecurity: true,
        expectPassword: true,
        expectMfa: true,
        expectRecovery: true,
        expectSessions: true,
        expectPasskeys: true,
        expectRegion: true,
        expectCaution: true,
      },
      {
        label: 'Owner (SSO, no password)',
        features: makeFeatures({
          hasPassword: false, isOwnerOrAdmin: true, isWebAuthnEnabled: true,
        }),
        expectSecurity: true,
        expectPassword: false,
        expectMfa: false,
        expectRecovery: false,
        expectSessions: true,
        expectPasskeys: true,
        expectRegion: true,
        expectCaution: true,
      },
      {
        label: 'Admin with password',
        features: makeFeatures({
          hasPassword: true, isOwnerOrAdmin: true, isWebAuthnEnabled: true,
        }),
        expectSecurity: true,
        expectPassword: true,
        expectMfa: true,
        expectRecovery: true,
        expectSessions: true,
        expectPasskeys: true,
        expectRegion: true,
        expectCaution: true,
      },
      {
        label: 'Admin (SSO, no password)',
        features: makeFeatures({
          hasPassword: false, isOwnerOrAdmin: true, isWebAuthnEnabled: true,
        }),
        expectSecurity: true,
        expectPassword: false,
        expectMfa: false,
        expectRecovery: false,
        expectSessions: true,
        expectPasskeys: true,
        expectRegion: true,
        expectCaution: true,
      },
      {
        label: 'Member with password (invited)',
        features: makeFeatures({
          hasPassword: true, isOwnerOrAdmin: false, isWebAuthnEnabled: true,
        }),
        expectSecurity: true,
        expectPassword: true,
        expectMfa: true,
        expectRecovery: true,
        expectSessions: true,
        expectPasskeys: true,
        expectRegion: false,
        expectCaution: false,
      },
      {
        label: 'Member (SSO, no password)',
        features: makeFeatures({
          hasPassword: false, isOwnerOrAdmin: false, isWebAuthnEnabled: true,
        }),
        expectSecurity: true,
        expectPassword: false,
        expectMfa: false,
        expectRecovery: false,
        expectSessions: true,
        expectPasskeys: true,
        expectRegion: false,
        expectCaution: false,
      },
    ];

    for (const p of personas) {
      describe(p.label, () => {
        it(`security section: ${p.expectSecurity ? 'visible' : 'hidden'}`, () => {
          const ids = getVisibleItemIds(p.features);
          if (p.expectSecurity) {
            expect(ids).toContain('security');
          } else {
            expect(ids).not.toContain('security');
          }
        });

        it(`password tab: ${p.expectPassword ? 'visible' : 'hidden'}`, () => {
          const childIds = getVisibleChildIds(p.features, 'security');
          if (p.expectPassword) {
            expect(childIds).toContain('password');
          } else {
            expect(childIds).not.toContain('password');
          }
        });

        it(`MFA tab: ${p.expectMfa ? 'visible' : 'hidden'}`, () => {
          const childIds = getVisibleChildIds(p.features, 'security');
          if (p.expectMfa) {
            expect(childIds).toContain('mfa');
          } else {
            expect(childIds).not.toContain('mfa');
          }
        });

        it(`recovery codes tab: ${p.expectRecovery ? 'visible' : 'hidden'}`, () => {
          const childIds = getVisibleChildIds(p.features, 'security');
          if (p.expectRecovery) {
            expect(childIds).toContain('recovery-codes');
          } else {
            expect(childIds).not.toContain('recovery-codes');
          }
        });

        it(`sessions tab: ${p.expectSessions ? 'visible' : 'hidden'}`, () => {
          const childIds = getVisibleChildIds(p.features, 'security');
          if (p.expectSessions) {
            expect(childIds).toContain('sessions');
          } else {
            expect(childIds).not.toContain('sessions');
          }
        });

        it(`passkeys tab: ${p.expectPasskeys ? 'visible' : 'hidden'}`, () => {
          const childIds = getVisibleChildIds(p.features, 'security');
          if (p.expectPasskeys) {
            expect(childIds).toContain('passkeys');
          } else {
            expect(childIds).not.toContain('passkeys');
          }
        });

        it(`region section: ${p.expectRegion ? 'visible' : 'hidden'}`, () => {
          const ids = getVisibleItemIds(p.features);
          if (p.expectRegion) {
            expect(ids).toContain('region');
          } else {
            expect(ids).not.toContain('region');
          }
        });

        it(`caution zone: ${p.expectCaution ? 'visible' : 'hidden'}`, () => {
          const ids = getVisibleItemIds(p.features);
          if (p.expectCaution) {
            expect(ids).toContain('caution');
          } else {
            expect(ids).not.toContain('caution');
          }
        });
      });
    }

    describe('WebAuthn off (passkeys hidden for all personas)', () => {
      it('passkeys tab hidden for owner with password when WebAuthn disabled', () => {
        const childIds = getVisibleChildIds(
          makeFeatures({ hasPassword: true, isOwnerOrAdmin: true, isWebAuthnEnabled: false }),
          'security'
        );
        expect(childIds).not.toContain('passkeys');
      });

      it('passkeys tab hidden for member with password when WebAuthn disabled', () => {
        const childIds = getVisibleChildIds(
          makeFeatures({ hasPassword: true, isOwnerOrAdmin: false, isWebAuthnEnabled: false }),
          'security'
        );
        expect(childIds).not.toContain('passkeys');
      });
    });
  });

  // ── Non-security sections ────────────────────────────────────────

  describe('Non-security sections visibility', () => {
    it('profile section is always included regardless of auth mode', () => {
      const items = getSettingsNavigation(t, makeFeatures({ isFullAuthMode: false }));
      expect(items.find((i) => i.id === 'profile')).toBeDefined();

      const itemsFull = getSettingsNavigation(t, makeFeatures({ isFullAuthMode: true }));
      expect(itemsFull.find((i) => i.id === 'profile')).toBeDefined();
    });
  });

  // ── API section ──────────────────────────────────────────────────

  describe('API section visibility', () => {
    it('API section is visible', () => {
      const sections = getSettingsNavigationSections(t, makeFeatures());
      const accountSection = sections.find((s) => s.id === 'account');
      const apiItem = accountSection?.items.find((i) => i.id === 'api');

      expect(apiItem?.visible?.()).toBe(true);
    });
  });
});
