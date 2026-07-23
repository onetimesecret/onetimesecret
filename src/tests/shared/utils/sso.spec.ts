// src/tests/shared/utils/sso.spec.ts

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { submitSsoLogin } from '@/shared/utils/sso';

/**
 * submitSsoLogin builds and POSTs a form to /auth/sso/:routeName. It is SHARED
 * between plain sign-in (SsoButton, disabled-homepage CTA) and the authenticated
 * Connected Identities connect flow (#3840 Phase 2).
 *
 * SECURITY-CRITICAL: only the connect flow may pass `connect: true`, which emits
 * a hidden `connect=1` field. The backend omniauth.rb hook reads that field to
 * authorize binding the returned identity to the current session account; an
 * unmarked (plain sign-in) initiation must NOT bind.
 */
describe('submitSsoLogin', () => {
  beforeEach(() => {
    // Prevent real navigation; jsdom would otherwise warn/throw on submit().
    HTMLFormElement.prototype.submit = vi.fn();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    document.querySelectorAll('form[action^="/auth/sso/"]').forEach((form) => form.remove());
  });

  const lastForm = (): HTMLFormElement | null =>
    document.querySelector<HTMLFormElement>('form[action^="/auth/sso/"]');

  it('builds a POST form targeting /auth/sso/:routeName', () => {
    submitSsoLogin({ routeName: 'oidc' });

    const form = lastForm();
    expect(form).not.toBeNull();
    expect(form?.getAttribute('action')).toBe('/auth/sso/oidc');
    expect(form?.method.toUpperCase()).toBe('POST');
  });

  it('includes the shrimp field when provided', () => {
    submitSsoLogin({ routeName: 'oidc', shrimp: 'my-shrimp' });

    const input = lastForm()?.querySelector<HTMLInputElement>('input[name="shrimp"]');
    expect(input).not.toBeNull();
    expect(input?.value).toBe('my-shrimp');
  });

  it('includes the redirect field when provided', () => {
    submitSsoLogin({ routeName: 'oidc', redirect: '/account/settings/security/connections' });

    const input = lastForm()?.querySelector<HTMLInputElement>('input[name="redirect"]');
    expect(input).not.toBeNull();
    expect(input?.value).toBe('/account/settings/security/connections');
  });

  it('emits a hidden connect=1 field when connect is true (account-linking flow)', () => {
    submitSsoLogin({ routeName: 'oidc', shrimp: 's', connect: true });

    const input = lastForm()?.querySelector<HTMLInputElement>('input[name="connect"]');
    expect(input).not.toBeNull();
    expect(input?.type).toBe('hidden');
    expect(input?.value).toBe('1');
  });

  it('omits the connect field when connect is false (plain sign-in must not bind)', () => {
    submitSsoLogin({ routeName: 'oidc', shrimp: 's', connect: false });

    expect(lastForm()?.querySelector('input[name="connect"]')).toBeNull();
  });

  it('omits the connect field when connect is not passed at all', () => {
    submitSsoLogin({ routeName: 'oidc', shrimp: 's' });

    expect(lastForm()?.querySelector('input[name="connect"]')).toBeNull();
  });

  it('submits the form after building it', () => {
    const submitSpy = vi.spyOn(HTMLFormElement.prototype, 'submit');

    submitSsoLogin({ routeName: 'oidc', connect: true });

    expect(submitSpy).toHaveBeenCalledTimes(1);
  });
});
