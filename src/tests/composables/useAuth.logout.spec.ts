// src/tests/composables/useAuth.logout.spec.ts

/**
 * Tests for the useAuth logout flow — verifying that the composable
 * uses logoutMinimal() (not the full logout()) and that hard navigation
 * follows cleanup, preventing brand-dependent components from flashing
 * to defaults during logout.
 *
 * Bug context: Previously, logout() called authStore.logout() which
 * ran bootstrapStore.$reset() before window.location.href was set.
 * This caused brand-dependent components (logo, colors) to briefly
 * flash to defaults before the navigation completed.
 *
 * Fix: logout() now calls authStore.logoutMinimal() (cookies + session
 * storage only, no reactive resets) and then sets window.location.href.
 *
 * NOTE: Direct import of useAuth is blocked by a pre-existing Zod v3/v4
 * incompatibility (z.email() and zod/v4 subpath are not available in
 * Zod 3.24.4). The same issue affects useAuth.billing.spec.ts and
 * useAuth.emailChange.spec.ts. These tests verify the invariants through
 * store-level behavior and source code pattern assertions until the Zod
 * dependency is resolved.
 */

import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';
import { mockCustomer } from '../setup-bootstrap';

describe('useAuth logout flow — no brand flash', () => {
  let authStore: ReturnType<typeof useAuthStore>;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  beforeEach(async () => {
    await setupTestPinia();

    bootstrapStore = useBootstrapStore();
    authStore = useAuthStore();

    // Hydrate with brand-specific state that would visibly flash if reset
    bootstrapStore.update({
      authenticated: true,
      cust: mockCustomer,
      email: mockCustomer.email,
      domain_logo: 'https://acme.example.com/logo.png',
      domain_branding: {
        primary_color: '#ff6600',
        allow_public_homepage: false,
        button_text_light: true,
        corner_style: 'rounded',
        font_family: 'sans',
        instructions_post_reveal: '',
        instructions_pre_reveal: '',
        instructions_reveal: '',
      },
      display_domain: 'acme.example.com',
      shrimp: 'test-shrimp',
    });

    authStore.init();
  });

  afterEach(() => {
    authStore.$reset();
    bootstrapStore.$reset();
    vi.clearAllMocks();
    vi.restoreAllMocks();
    sessionStorage.clear();
  });

  describe('source code invariants', () => {
    // These tests read the actual source code to verify critical patterns.
    // This guards against regressions where someone changes the wiring
    // without updating or running the full test suite.

    let useAuthSource: string;

    beforeEach(() => {
      const filePath = resolve(__dirname, '../../shared/composables/useAuth.ts');
      useAuthSource = readFileSync(filePath, 'utf-8');
    });

    it('logout function calls authStore.logoutMinimal(), not authStore.logout()', () => {
      // Extract the logout function body from the source
      // The logout function is defined as: async function logout(redirectTo?: string)
      const logoutMatch = useAuthSource.match(
        /async function logout\(redirectTo\?.*?\{([\s\S]*?)^\s{2}\}/m
      );
      expect(logoutMatch).not.toBeNull();

      const logoutBody = logoutMatch![1];

      // Must call logoutMinimal
      expect(logoutBody).toContain('authStore.logoutMinimal()');

      // Must NOT call authStore.logout() (the full reset version)
      // We need to be specific: "authStore.logout()" should not appear
      // but "authStore.logoutMinimal()" should. The regex ensures we
      // match the exact method call, not a substring.
      const fullLogoutCalls = logoutBody.match(/authStore\.logout\(\)/g);
      expect(fullLogoutCalls).toBeNull();
    });

    it('window.location.href is set AFTER logoutMinimal call', () => {
      const logoutMatch = useAuthSource.match(
        /async function logout\(redirectTo\?.*?\{([\s\S]*?)^\s{2}\}/m
      );
      expect(logoutMatch).not.toBeNull();

      const logoutBody = logoutMatch![1];

      const minimalIndex = logoutBody.indexOf('authStore.logoutMinimal()');
      const hrefIndex = logoutBody.indexOf('window.location.href');

      expect(minimalIndex).toBeGreaterThan(-1);
      expect(hrefIndex).toBeGreaterThan(-1);
      expect(hrefIndex).toBeGreaterThan(minimalIndex);
    });

    it('logout function does NOT call bootstrapStore.$reset() (ignoring comments)', () => {
      const logoutMatch = useAuthSource.match(
        /async function logout\(redirectTo\?.*?\{([\s\S]*?)^\s{2}\}/m
      );
      expect(logoutMatch).not.toBeNull();

      const logoutBody = logoutMatch![1];

      // Strip single-line comments before checking, so references in
      // explanatory comments (like "Skip bootstrapStore.$reset()") don't
      // trigger a false positive.
      const codeOnly = logoutBody
        .split('\n')
        .filter((line) => !line.trim().startsWith('//'))
        .join('\n');

      expect(codeOnly).not.toContain('bootstrapStore.$reset()');
    });
  });

  describe('store-level behavior: logoutMinimal preserves brand state', () => {
    it('logoutMinimal does not reset domain_logo', async () => {
      expect(bootstrapStore.domain_logo).toBe('https://acme.example.com/logo.png');

      await authStore.logoutMinimal();

      expect(bootstrapStore.domain_logo).toBe('https://acme.example.com/logo.png');
    });

    it('logoutMinimal does not reset domain_branding', async () => {
      expect(bootstrapStore.domain_branding.primary_color).toBe('#ff6600');

      await authStore.logoutMinimal();

      expect(bootstrapStore.domain_branding.primary_color).toBe('#ff6600');
    });

    it('logoutMinimal does not reset display_domain', async () => {
      expect(bootstrapStore.display_domain).toBe('acme.example.com');

      await authStore.logoutMinimal();

      expect(bootstrapStore.display_domain).toBe('acme.example.com');
    });

    it('logoutMinimal does not reset authenticated ref', async () => {
      expect(authStore.isAuthenticated).toBe(true);

      await authStore.logoutMinimal();

      expect(authStore.isAuthenticated).toBe(true);
    });

    it('logoutMinimal does not call bootstrapStore.$reset()', async () => {
      const resetSpy = vi.spyOn(bootstrapStore, '$reset');

      await authStore.logoutMinimal();

      expect(resetSpy).not.toHaveBeenCalled();
    });

    it('logoutMinimal still clears cookies and session storage', async () => {
      document.cookie = 'sess=abc123; path=/';
      document.cookie = 'locale=en; path=/';
      sessionStorage.setItem('ots_auth_state', 'true');

      await authStore.logoutMinimal();

      expect(document.cookie).not.toContain('sess=abc123');
      expect(document.cookie).not.toContain('locale=en');
      expect(sessionStorage.getItem('ots_auth_state')).toBeNull();
    });

    it('logoutMinimal stops the auth check timer', async () => {
      vi.useFakeTimers();
      authStore.$patch({ isAuthenticated: true });
      authStore.$scheduleNextCheck();
      expect(authStore.authCheckTimer).not.toBeNull();

      await authStore.logoutMinimal();

      expect(authStore.authCheckTimer).toBeNull();
      vi.useRealTimers();
    });
  });

  describe('contrast: full logout() DOES reset brand state (demonstrating the bug)', () => {
    it('full logout resets domain_logo to null', async () => {
      expect(bootstrapStore.domain_logo).toBe('https://acme.example.com/logo.png');

      await authStore.logout();

      // This is the flash: domain_logo reverts to the DEFAULTS value (null)
      expect(bootstrapStore.domain_logo).toBeNull();
    });

    it('full logout resets domain_branding to empty defaults', async () => {
      expect(bootstrapStore.domain_branding.primary_color).toBe('#ff6600');

      await authStore.logout();

      // domain_branding reverts to DEFAULTS (empty BrandSettings)
      expect(bootstrapStore.domain_branding).not.toHaveProperty('primary_color');
    });

    it('full logout resets authenticated to null', async () => {
      expect(authStore.isAuthenticated).toBe(true);

      await authStore.logout();

      expect(authStore.isAuthenticated).toBeNull();
    });
  });
});
