// src/tests/stores/authStore.logoutMinimal.spec.ts

/**
 * Tests for authStore.logoutMinimal() — the minimal logout method that
 * clears cookies and session storage WITHOUT resetting reactive Pinia state.
 *
 * This method exists to prevent a visual flash during logout where
 * brand-dependent components (logo, colors) would briefly revert to
 * defaults as bootstrapStore.$reset() triggers reactive flushes before
 * the hard navigation completes.
 *
 * The invariant: logoutMinimal() must NEVER call $reset() or
 * bootstrapStore.$reset(). If it did, the brand flash bug returns.
 */

import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';
import { mockCustomer } from '../setup-bootstrap';

describe('authStore.logoutMinimal', () => {
  let store: ReturnType<typeof useAuthStore>;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  beforeEach(async () => {
    await setupTestPinia();

    bootstrapStore = useBootstrapStore();
    store = useAuthStore();

    // Hydrate bootstrapStore with brand-specific values that would
    // visibly flash if reset during logout
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
      site_host: 'acme.example.com',
      shrimp: 'csrf-token-abc',
    });

    store.init();

    // Set a cookie so we can verify deletion
    document.cookie = 'sess=session123; path=/';
    document.cookie = 'locale=en; path=/';
    sessionStorage.setItem('ots_auth_state', 'true');
    sessionStorage.setItem('some_other_key', 'value');
  });

  afterEach(() => {
    store.$reset();
    bootstrapStore.$reset();
    vi.clearAllMocks();
    vi.restoreAllMocks();
    sessionStorage.clear();
    document.cookie = 'sess=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
    document.cookie = 'locale=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
  });

  it('clears session storage', async () => {
    expect(sessionStorage.getItem('ots_auth_state')).toBe('true');
    expect(sessionStorage.getItem('some_other_key')).toBe('value');

    await store.logoutMinimal();

    expect(sessionStorage.getItem('ots_auth_state')).toBeNull();
    expect(sessionStorage.getItem('some_other_key')).toBeNull();
  });

  it('deletes the sess cookie', async () => {
    expect(document.cookie).toContain('sess=session123');

    await store.logoutMinimal();

    expect(document.cookie).not.toContain('sess=session123');
  });

  it('deletes the locale cookie', async () => {
    expect(document.cookie).toContain('locale=en');

    await store.logoutMinimal();

    expect(document.cookie).not.toContain('locale=en');
  });

  it('stops the auth check timer', async () => {
    vi.useFakeTimers();
    store.$patch({ isAuthenticated: true });
    store.$scheduleNextCheck();

    expect(store.authCheckTimer).not.toBeNull();

    await store.logoutMinimal();

    expect(store.authCheckTimer).toBeNull();

    vi.useRealTimers();
  });

  it('does NOT reset bootstrapStore reactive state (domain_logo preserved)', async () => {
    expect(bootstrapStore.domain_logo).toBe('https://acme.example.com/logo.png');

    await store.logoutMinimal();

    // The whole point: brand values must survive logoutMinimal
    expect(bootstrapStore.domain_logo).toBe('https://acme.example.com/logo.png');
  });

  it('does NOT reset bootstrapStore reactive state (domain_branding preserved)', async () => {
    expect(bootstrapStore.domain_branding.primary_color).toBe('#ff6600');

    await store.logoutMinimal();

    expect(bootstrapStore.domain_branding.primary_color).toBe('#ff6600');
  });

  it('does NOT reset bootstrapStore reactive state (display_domain preserved)', async () => {
    expect(bootstrapStore.display_domain).toBe('acme.example.com');

    await store.logoutMinimal();

    expect(bootstrapStore.display_domain).toBe('acme.example.com');
  });

  it('does NOT reset authStore isAuthenticated', async () => {
    expect(store.isAuthenticated).toBe(true);

    await store.logoutMinimal();

    // isAuthenticated should remain unchanged — the hard navigation
    // will discard all in-memory state anyway
    expect(store.isAuthenticated).toBe(true);
  });

  it('does NOT call bootstrapStore.$reset()', async () => {
    const resetSpy = vi.spyOn(bootstrapStore, '$reset');

    await store.logoutMinimal();

    expect(resetSpy).not.toHaveBeenCalled();
  });

  it('does NOT call authStore.$reset()', async () => {
    const resetSpy = vi.spyOn(store, '$reset');

    await store.logoutMinimal();

    expect(resetSpy).not.toHaveBeenCalled();
  });

  describe('contrast with full logout()', () => {
    it('full logout() DOES reset bootstrapStore, confirming the difference', async () => {
      expect(bootstrapStore.domain_logo).toBe('https://acme.example.com/logo.png');

      await store.logout();

      // Full logout resets bootstrapStore — domain_logo reverts to default (null)
      expect(bootstrapStore.domain_logo).toBeNull();
    });

    it('full logout() DOES reset authStore isAuthenticated to null', async () => {
      expect(store.isAuthenticated).toBe(true);

      await store.logout();

      expect(store.isAuthenticated).toBeNull();
    });
  });
});
