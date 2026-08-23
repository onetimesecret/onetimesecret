// src/tests/apps/session/components/PasswordlessFirstSignIn.spec.ts

/**
 * PasswordlessFirstSignIn — initial tab selection.
 *
 * The `initialMode` prop is a contextual default (e.g. "password" right after
 * email verification): it preselects a tab on first render, takes precedence
 * over the remembered localStorage preference, and is never persisted. Absent
 * the prop, the first available tab (Magic Link) is selected.
 */

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ref } from 'vue';

import PasswordlessFirstSignIn from '@/apps/session/components/PasswordlessFirstSignIn.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
}));

vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: () => ({
    login: vi.fn(),
    isLoading: ref(false),
    error: ref(null),
    lockoutStatus: ref(null),
    clearErrors: vi.fn(),
  }),
}));

vi.mock('@/shared/composables/useMagicLink', () => ({
  useMagicLink: () => ({
    requestMagicLink: vi.fn(),
    sent: ref(false),
    isLoading: ref(false),
    error: ref(null),
    clearState: vi.fn(),
  }),
}));

vi.mock('@/shared/composables/useWebAuthn', () => ({
  useWebAuthn: () => ({
    supported: ref(true),
    isLoading: ref(false),
    error: ref(null),
    authenticateWebAuthn: vi.fn(),
    clearError: vi.fn(),
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span />', props: ['collection', 'name', 'size'] },
}));

describe('PasswordlessFirstSignIn initial tab', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    localStorage.clear();
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  const mountWith = (props: Record<string, unknown> = {}) =>
    mount(PasswordlessFirstSignIn, {
      props: { magicLinksEnabled: true, webauthnEnabled: false, ...props },
    });

  it('selects the password tab when initialMode="password"', () => {
    wrapper = mountWith({ initialMode: 'password' });

    expect(wrapper.find('[data-testid="tab-password"]').attributes('aria-selected')).toBe('true');
    // Only the selected panel is rendered by HeadlessUI.
    expect(wrapper.find('[data-testid="password-panel"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="magic-link-panel"]').exists()).toBe(false);
  });

  it('defaults to the magic link tab when no initialMode is given', () => {
    wrapper = mountWith();

    expect(wrapper.find('[data-testid="tab-passwordless"]').attributes('aria-selected')).toBe(
      'true'
    );
    expect(wrapper.find('[data-testid="magic-link-panel"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="password-panel"]').exists()).toBe(false);
  });

  it('emits mode-change for a non-default initial mode', () => {
    wrapper = mountWith({ initialMode: 'password' });

    const events = wrapper.emitted('mode-change');
    expect(events).toBeTruthy();
    expect(events![0]).toEqual(['password']);
  });
});

describe('PasswordlessFirstSignIn passwordEnabled (single-method restriction)', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    localStorage.clear();
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  const mountWith = (props: Record<string, unknown> = {}) =>
    mount(PasswordlessFirstSignIn, {
      props: { magicLinksEnabled: true, webauthnEnabled: false, ...props },
    });

  it('offers the password tab by default', () => {
    wrapper = mountWith();
    expect(wrapper.find('[data-testid="tab-password"]').exists()).toBe(true);
  });

  it('withholds the password tab when passwordEnabled=false (magic links only)', () => {
    wrapper = mountWith({ passwordEnabled: false });

    expect(wrapper.find('[data-testid="tab-password"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="tab-passwordless"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="magic-link-panel"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="password-panel"]').exists()).toBe(false);
  });

  it('withholds the password tab when passwordEnabled=false (passkeys only)', () => {
    wrapper = mountWith({
      magicLinksEnabled: false,
      webauthnEnabled: true,
      passwordEnabled: false,
    });

    expect(wrapper.find('[data-testid="tab-password"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="tab-passkey"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="passkey-panel"]').exists()).toBe(true);
  });

  it('falls back to the password tab when every method prop is off (never zero tabs)', () => {
    wrapper = mountWith({
      magicLinksEnabled: false,
      webauthnEnabled: false,
      passwordEnabled: false,
    });

    expect(wrapper.find('[data-testid="tab-password"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="password-panel"]').exists()).toBe(true);
  });

  it('ignores a remembered preference for a withheld tab', () => {
    localStorage.setItem(
      'onetimeSigninMode',
      JSON.stringify({ mode: 'password', expiresAt: Date.now() + 60_000 })
    );
    wrapper = mountWith({ passwordEnabled: false });

    expect(wrapper.find('[data-testid="tab-passwordless"]').attributes('aria-selected')).toBe(
      'true'
    );
    expect(wrapper.find('[data-testid="password-panel"]').exists()).toBe(false);
  });
});
