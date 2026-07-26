// src/shared/utils/sso.ts
//
// Shared helper for initiating an SSO sign-in. SSO login is a traditional
// form POST to /auth/sso/:provider (not a fetch) because the endpoint
// triggers the OmniAuth flow and redirects the browser to the identity
// provider — an XHR can't follow that cross-origin redirect.
//
// Used by both the dedicated SsoButton on /signin and the one-click SSO CTA
// on the disabled-homepage variants, so the form-building stays in one place.

export interface SubmitSsoLoginOptions {
  /**
   * SSO route name used to build the POST action URL (`/auth/sso/:routeName`).
   * Corresponds to the `name:` option in auth.omniauth_provider.
   * Example: 'oidc', 'google', 'entra', 'github'.
   */
  routeName: string;

  /**
   * CSRF (shrimp) token included for form consistency.
   *
   * Note: Rack::Protection skips /auth/sso/* routes (see security.rb);
   * OmniAuth's OAuth state parameter provides CSRF protection instead. The
   * token is submitted but not validated for these routes.
   */
  shrimp?: string;

  /**
   * URL to return to after successful SSO authentication (e.g. '/invite/abc').
   * When provided, the backend stores it and redirects there post-login.
   */
  redirect?: string;

  /**
   * Marks this as an authenticated account-linking initiation (Connected
   * Identities connect flow) rather than a plain sign-in. When true, a hidden
   * `connect=1` field is submitted; the backend `omniauth.rb` hook reads it to
   * authorize binding the returned identity to the CURRENT session account.
   * Omit (or false) for normal sign-in — an unmarked initiation must not bind.
   */
  connect?: boolean;
}

/** Append a hidden input to the form (skipped when the value is empty). */
function appendHiddenField(form: HTMLFormElement, name: string, value: string): void {
  if (!value) return;
  const input = document.createElement('input');
  input.type = 'hidden';
  input.name = name;
  input.value = value;
  form.appendChild(input);
}

/**
 * Build and submit a POST form that initiates SSO login for the given
 * provider. Navigates the browser away to the IdP, so nothing runs after
 * `form.submit()` returns.
 */
export function submitSsoLogin({
  routeName,
  shrimp,
  redirect,
  connect,
}: SubmitSsoLoginOptions): void {
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = `/auth/sso/${routeName}`;

  appendHiddenField(form, 'shrimp', shrimp ?? '');
  appendHiddenField(form, 'redirect', redirect ?? '');
  // Connect-intent: only the authenticated account-linking flow marks the
  // initiation. A plain sign-in leaves it unset so the backend never binds.
  appendHiddenField(form, 'connect', connect ? '1' : '');

  document.body.appendChild(form);
  form.submit();
}
