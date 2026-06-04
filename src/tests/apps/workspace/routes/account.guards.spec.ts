// src/tests/apps/workspace/routes/account.guards.spec.ts
//
// Tests for the per-route beforeEnter guards defined in account.ts.
// The guards (checkOwnerOrAdminAccess, checkPasswordSecurityAccess,
// checkSecurityAccess) are not exported, so we test them indirectly by
// invoking beforeEnter on the route records themselves.

import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock features before importing routes (the guards call these at invocation time)
vi.mock('@/utils/features', () => ({
  isFullAuthMode: vi.fn(() => false),
  hasPassword: vi.fn(() => false),
  isOwnerOrAdmin: vi.fn(() => false),
}));

import accountRoutes from '@/apps/workspace/routes/account';
import { isFullAuthMode, hasPassword, isOwnerOrAdmin } from '@/utils/features';
import type { RouteRecordRaw, NavigationGuardWithThis } from 'vue-router';

const mockedIsFullAuthMode = vi.mocked(isFullAuthMode);
const mockedHasPassword = vi.mocked(hasPassword);
const mockedIsOwnerOrAdmin = vi.mocked(isOwnerOrAdmin);

/**
 * Extract the beforeEnter guard from a route found by path.
 * Handles function or array-of-functions form (account.ts uses functions).
 */
function getGuardForPath(path: string): NavigationGuardWithThis<undefined> {
  const route = accountRoutes.find((r: RouteRecordRaw) => r.path === path);
  if (!route) throw new Error(`No route found for path: ${path}`);
  if (!route.beforeEnter) throw new Error(`No beforeEnter guard on path: ${path}`);
  if (typeof route.beforeEnter === 'function') {
    return route.beforeEnter as NavigationGuardWithThis<undefined>;
  }
  // Array form: return first guard
  return (route.beforeEnter as NavigationGuardWithThis<undefined>[])[0];
}

/** Invoke a sync guard and return its result. */
function invokeGuard(path: string): ReturnType<NavigationGuardWithThis<undefined>> {
  const guard = getGuardForPath(path);
  // Account route guards are synchronous (no async/await needed).
  // They take (to, from, next) but use the return-value form, not next().
  // We can call with minimal args since the guards only read feature flags.
  return guard(
    {} as any, // to (unused by these guards)
    {} as any, // from (unused)
    undefined as any, // next (unused, return-value form)
  );
}

describe('Account route guards', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockedIsFullAuthMode.mockReturnValue(false);
    mockedHasPassword.mockReturnValue(false);
    mockedIsOwnerOrAdmin.mockReturnValue(false);
  });

  // ── Guard wiring verification ─────────────────────────────────────

  describe('guard wiring', () => {
    it('region routes use checkOwnerOrAdminAccess', () => {
      const regionPaths = [
        '/account/region',
        '/account/region/current',
        '/account/region/available',
        '/account/region/why',
      ];
      for (const path of regionPaths) {
        const route = accountRoutes.find((r: RouteRecordRaw) => r.path === path);
        expect(route?.beforeEnter, `${path} should have beforeEnter`).toBeDefined();
      }
    });

    it('caution route uses checkOwnerOrAdminAccess', () => {
      const route = accountRoutes.find((r: RouteRecordRaw) => r.path === '/account/settings/caution');
      expect(route?.beforeEnter).toBeDefined();
    });

    it('password security routes have beforeEnter guards', () => {
      const passwordPaths = [
        '/account/settings/security/password',
        '/account/settings/security/reset-password',
        '/account/settings/security/mfa',
        '/account/settings/security/recovery-codes',
      ];
      for (const path of passwordPaths) {
        const route = accountRoutes.find((r: RouteRecordRaw) => r.path === path);
        expect(route?.beforeEnter, `${path} should have beforeEnter`).toBeDefined();
      }
    });

    it('change email route has beforeEnter guard (checkOwnerWithPasswordAccess)', () => {
      const route = accountRoutes.find((r: RouteRecordRaw) => r.path === '/account/settings/profile/email');
      expect(route?.beforeEnter).toBeDefined();
    });

    it('security overview, sessions, and passkeys routes have beforeEnter guards', () => {
      const securityPaths = [
        '/account/settings/security',
        '/account/settings/security/sessions',
        '/account/settings/security/passkeys',
      ];
      for (const path of securityPaths) {
        const route = accountRoutes.find((r: RouteRecordRaw) => r.path === path);
        expect(route?.beforeEnter, `${path} should have beforeEnter`).toBeDefined();
      }
    });

    it('profile and preferences routes have no beforeEnter guard', () => {
      const openPaths = [
        '/account',
        '/account/settings/profile/preferences',
        '/account/settings/profile/privacy',
        '/account/settings/profile/notifications',
        '/account/settings/api',
      ];
      for (const path of openPaths) {
        const route = accountRoutes.find((r: RouteRecordRaw) => r.path === path);
        expect(route?.beforeEnter, `${path} should NOT have beforeEnter`).toBeUndefined();
      }
    });

    it('no account routes use excludeSsoOnly meta', () => {
      for (const route of accountRoutes) {
        if (route.meta) {
          expect(
            (route.meta as Record<string, unknown>).excludeSsoOnly,
            `${route.path} should not have excludeSsoOnly`
          ).toBeUndefined();
        }
      }
    });
  });

  // ── checkOwnerOrAdminAccess ───────────────────────────────────────

  describe('checkOwnerOrAdminAccess (region + caution routes)', () => {
    const guardedPaths = [
      '/account/region',
      '/account/region/current',
      '/account/settings/caution',
    ];

    for (const path of guardedPaths) {
      describe(path, () => {
        it('allows owner in full auth mode', () => {
          mockedIsFullAuthMode.mockReturnValue(true);
          mockedIsOwnerOrAdmin.mockReturnValue(true);

          expect(invokeGuard(path)).toBe(true);
        });

        it('redirects to Account when not full auth mode', () => {
          mockedIsFullAuthMode.mockReturnValue(false);
          mockedIsOwnerOrAdmin.mockReturnValue(true);

          expect(invokeGuard(path)).toEqual({ name: 'Account' });
        });

        it('redirects to Account when user is a member', () => {
          mockedIsFullAuthMode.mockReturnValue(true);
          mockedIsOwnerOrAdmin.mockReturnValue(false);

          expect(invokeGuard(path)).toEqual({ name: 'Account' });
        });

        it('redirects to Account when both conditions fail', () => {
          mockedIsFullAuthMode.mockReturnValue(false);
          mockedIsOwnerOrAdmin.mockReturnValue(false);

          expect(invokeGuard(path)).toEqual({ name: 'Account' });
        });
      });
    }
  });

  // ── checkPasswordSecurityAccess ───────────────────────────────────

  describe('checkPasswordSecurityAccess (password-dependent routes)', () => {
    const guardedPaths = [
      '/account/settings/security/password',
      '/account/settings/security/reset-password',
      '/account/settings/security/mfa',
      '/account/settings/security/recovery-codes',
    ];

    for (const path of guardedPaths) {
      describe(path, () => {
        it('allows user with password in full auth mode', () => {
          mockedIsFullAuthMode.mockReturnValue(true);
          mockedHasPassword.mockReturnValue(true);

          expect(invokeGuard(path)).toBe(true);
        });

        it('redirects to Account when not full auth mode', () => {
          mockedIsFullAuthMode.mockReturnValue(false);
          mockedHasPassword.mockReturnValue(true);

          expect(invokeGuard(path)).toEqual({ name: 'Account' });
        });

        it('redirects to Account when user has no password (SSO account)', () => {
          mockedIsFullAuthMode.mockReturnValue(true);
          mockedHasPassword.mockReturnValue(false);

          expect(invokeGuard(path)).toEqual({ name: 'Account' });
        });

        it('redirects to Account when both conditions fail', () => {
          mockedIsFullAuthMode.mockReturnValue(false);
          mockedHasPassword.mockReturnValue(false);

          expect(invokeGuard(path)).toEqual({ name: 'Account' });
        });
      });
    }
  });

  // ── checkOwnerWithPasswordAccess ────────────────────────────────────

  describe('checkOwnerWithPasswordAccess (change email)', () => {
    const path = '/account/settings/profile/email';

    it('allows owner with password in full auth mode', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedIsOwnerOrAdmin.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);

      expect(invokeGuard(path)).toBe(true);
    });

    it('redirects when not full auth mode', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      mockedIsOwnerOrAdmin.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);

      expect(invokeGuard(path)).toEqual({ name: 'Account' });
    });

    it('redirects when user is a member (not owner/admin)', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedIsOwnerOrAdmin.mockReturnValue(false);
      mockedHasPassword.mockReturnValue(true);

      expect(invokeGuard(path)).toEqual({ name: 'Account' });
    });

    it('redirects when user has no password (SSO account)', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedIsOwnerOrAdmin.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(false);

      expect(invokeGuard(path)).toEqual({ name: 'Account' });
    });

    it('redirects when all three conditions fail', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      mockedIsOwnerOrAdmin.mockReturnValue(false);
      mockedHasPassword.mockReturnValue(false);

      expect(invokeGuard(path)).toEqual({ name: 'Account' });
    });
  });

  // ── checkSecurityAccess ───────────────────────────────────────────

  describe('checkSecurityAccess (auth-mode-only routes)', () => {
    const guardedPaths = [
      '/account/settings/security',
      '/account/settings/security/sessions',
      '/account/settings/security/passkeys',
    ];

    for (const path of guardedPaths) {
      describe(path, () => {
        it('allows any user in full auth mode', () => {
          mockedIsFullAuthMode.mockReturnValue(true);

          expect(invokeGuard(path)).toBe(true);
        });

        it('redirects to Account when not full auth mode', () => {
          mockedIsFullAuthMode.mockReturnValue(false);

          expect(invokeGuard(path)).toEqual({ name: 'Account' });
        });

        it('allows SSO user (no password) in full auth mode', () => {
          mockedIsFullAuthMode.mockReturnValue(true);
          mockedHasPassword.mockReturnValue(false);
          mockedIsOwnerOrAdmin.mockReturnValue(false);

          expect(invokeGuard(path)).toBe(true);
        });
      });
    }
  });

  // ── Cross-cutting persona scenarios ───────────────────────────────

  describe('persona scenarios (end-to-end guard behavior)', () => {
    it('owner with password can access all guarded routes', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);
      mockedIsOwnerOrAdmin.mockReturnValue(true);

      const allGuardedPaths = accountRoutes
        .filter((r: RouteRecordRaw) => r.beforeEnter)
        .map((r: RouteRecordRaw) => r.path);

      for (const path of allGuardedPaths) {
        expect(invokeGuard(path), `owner+password should access ${path}`).toBe(true);
      }
    });

    it('owner SSO (no password) can access region/caution/security/sessions but not password routes', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(false);
      mockedIsOwnerOrAdmin.mockReturnValue(true);

      // Should allow
      expect(invokeGuard('/account/region')).toBe(true);
      expect(invokeGuard('/account/settings/caution')).toBe(true);
      expect(invokeGuard('/account/settings/security')).toBe(true);
      expect(invokeGuard('/account/settings/security/sessions')).toBe(true);

      // Should redirect
      expect(invokeGuard('/account/settings/security/password')).toEqual({ name: 'Account' });
      expect(invokeGuard('/account/settings/security/mfa')).toEqual({ name: 'Account' });
      expect(invokeGuard('/account/settings/security/recovery-codes')).toEqual({ name: 'Account' });
    });

    it('member with password can access password/security routes but not region/caution', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(true);
      mockedIsOwnerOrAdmin.mockReturnValue(false);

      // Should allow
      expect(invokeGuard('/account/settings/security')).toBe(true);
      expect(invokeGuard('/account/settings/security/sessions')).toBe(true);
      expect(invokeGuard('/account/settings/security/password')).toBe(true);
      expect(invokeGuard('/account/settings/security/mfa')).toBe(true);

      // Should redirect
      expect(invokeGuard('/account/region')).toEqual({ name: 'Account' });
      expect(invokeGuard('/account/settings/caution')).toEqual({ name: 'Account' });
    });

    it('member SSO (no password) can only access security overview and sessions', () => {
      mockedIsFullAuthMode.mockReturnValue(true);
      mockedHasPassword.mockReturnValue(false);
      mockedIsOwnerOrAdmin.mockReturnValue(false);

      // Should allow
      expect(invokeGuard('/account/settings/security')).toBe(true);
      expect(invokeGuard('/account/settings/security/sessions')).toBe(true);

      // Should redirect
      expect(invokeGuard('/account/settings/security/password')).toEqual({ name: 'Account' });
      expect(invokeGuard('/account/settings/security/mfa')).toEqual({ name: 'Account' });
      expect(invokeGuard('/account/region')).toEqual({ name: 'Account' });
      expect(invokeGuard('/account/settings/caution')).toEqual({ name: 'Account' });
    });

    it('simple auth mode blocks all guarded routes regardless of role', () => {
      mockedIsFullAuthMode.mockReturnValue(false);
      mockedHasPassword.mockReturnValue(true);
      mockedIsOwnerOrAdmin.mockReturnValue(true);

      const allGuardedPaths = accountRoutes
        .filter((r: RouteRecordRaw) => r.beforeEnter)
        .map((r: RouteRecordRaw) => r.path);

      for (const path of allGuardedPaths) {
        expect(invokeGuard(path), `simple auth should block ${path}`).toEqual({ name: 'Account' });
      }
    });
  });
});
