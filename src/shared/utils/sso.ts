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
}

/**
 * Build and submit a POST form that initiates SSO login for the given
 * provider. Navigates the browser away to the IdP, so nothing runs after
 * `form.submit()` returns.
 */
export function submitSsoLogin({ routeName, shrimp, redirect }: SubmitSsoLoginOptions): void {
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = `/auth/sso/${routeName}`;

  if (shrimp) {
    const csrfInput = document.createElement('input');
    csrfInput.type = 'hidden';
    csrfInput.name = 'shrimp';
    csrfInput.value = shrimp;
    form.appendChild(csrfInput);
  }

  if (redirect) {
    const redirectInput = document.createElement('input');
    redirectInput.type = 'hidden';
    redirectInput.name = 'redirect';
    redirectInput.value = redirect;
    form.appendChild(redirectInput);
  }

  document.body.appendChild(form);
  form.submit();
}
