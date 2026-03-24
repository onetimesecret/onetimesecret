// src/utils/features.ts

import { getBootstrapValue } from '@/services/bootstrap.service';

/**
 * Feature detection utilities for checking enabled authentication methods
 * Features are configured on the backend via environment variables and
 * exposed through window.__BOOTSTRAP_ME__, accessed via bootstrap.service.ts
 */

export interface AuthFeatures {
  magicLinksEnabled: boolean;
  webauthnEnabled: boolean;
  ssoEnabled: boolean;
  ssoOnly: boolean;
}

/**
 * Checks if magic link authentication is enabled
 */
export function isMagicLinksEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  return features?.magic_links === true || features?.email_auth === true;
}

/**
 * Checks if MFA (TOTP + recovery codes) is enabled
 */
export function isMfaEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  return features?.mfa === true;
}

/**
 * Checks if WebAuthn authentication is enabled
 */
export function isWebAuthnEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  return features?.webauthn === true;
}

/**
 * Checks if account lockout (after failed login attempts) is enabled
 */
export function isLockoutEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  return features?.lockout === true;
}

/**
 * Checks if password complexity requirements are enabled
 */
export function isPasswordRequirementsEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  return features?.password_requirements === true;
}

/**
 * Checks if SSO authentication is enabled
 */
export function isSsoEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  // sso can be boolean (false) or object with enabled property
  const sso = features?.sso;
  if (typeof sso === 'boolean') return sso;
  return sso?.enabled === true;
}

/**
 * Provider entry from bootstrap state
 */
export interface SsoProvider {
  route_name: string;
  display_name: string;
}

/**
 * Returns the list of configured SSO providers from bootstrap state.
 * Each provider has a route_name (for constructing /auth/sso/{route_name})
 * and a display_name (for "Sign in with X" button text).
 *
 * Used by AuthMethodSelector and available for any component needing the
 * configured provider list (e.g., account settings, admin views).
 */
export function getSsoProviders(): SsoProvider[] {
  if (typeof window === 'undefined') return [];

  const features = getBootstrapValue('features');
  const sso = features?.sso;

  // Disabled or not configured
  if (!sso || typeof sso === 'boolean') return [];
  if (!sso.enabled) return [];

  // Return providers array, or empty if not configured
  if (Array.isArray(sso.providers) && sso.providers.length > 0) {
    return sso.providers;
  }

  return [];
}

/**
 * Checks if SSO-only mode is active.
 * When true, password-based auth routes are disabled and the sign-in page
 * shows only SSO provider buttons.
 *
 * This is a no-op when SSO is not enabled -- the UI falls through to
 * default auth forms.
 */
export function isSsoOnlyMode(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  return features?.sso_only === true;
}

/**
 * Checks if authentication mode is 'full' (Rodauth with SQL db).
 * When mode is 'simple' (or undefined), security features like
 * password change, MFA, sessions, and passkeys are not available.
 */
export function isFullAuthMode(): boolean {
  if (typeof window === 'undefined') return false;

  const authentication = getBootstrapValue('authentication');
  return authentication?.mode === 'full';
}

/**
 * Checks if the current authenticated user has a password set.
 * SSO-only accounts (Entra, Google, GitHub) return false.
 * Used to hide password-based security settings for SSO-only users.
 */
export function hasPassword(): boolean {
  if (typeof window === 'undefined') return false;

  return getBootstrapValue('has_password') === true;
}

/**
 * Gets all enabled authentication features
 */
export function getAuthFeatures(): AuthFeatures {
  return {
    magicLinksEnabled: isMagicLinksEnabled(),
    webauthnEnabled: isWebAuthnEnabled(),
    ssoEnabled: isSsoEnabled(),
    ssoOnly: isSsoOnlyMode(),
  };
}

/**
 * Checks if any passwordless methods are enabled
 */
export function hasPasswordlessMethods(): boolean {
  return isMagicLinksEnabled() || isWebAuthnEnabled();
}

/**
 * Checks if the organization switcher UI is enabled.
 * Organizations always exist (every customer has one for Stripe billing).
 * This controls whether the multi-org switcher is visible in navigation.
 * Default is OFF - requires explicit opt-in via SHOW_ORGANIZATION_SWITCHER=true.
 */
export function isOrganizationSwitcherEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  return features?.organizations?.enabled === true;
}
