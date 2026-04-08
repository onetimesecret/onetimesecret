// src/utils/features.ts

import { getBootstrapValue } from '@/services/bootstrap.service';
import { debugLog } from '@/utils/debug';

/**
 * Feature detection utilities for checking enabled authentication methods
 * Features are configured on the backend via environment variables and
 * exposed through window.__BOOTSTRAP_ME__, accessed via bootstrap.service.ts
 */

/**
 * Valid values for the restrict_to single-auth-method override.
 */
export type RestrictTo = 'password' | 'email_auth' | 'webauthn' | 'sso';

export interface AuthFeatures {
  magicLinksEnabled: boolean;
  webauthnEnabled: boolean;
  ssoEnabled: boolean;
  restrictTo: RestrictTo | null;
}

/**
 * Checks if magic link authentication is enabled.
 *
 * The backend currently exposes two related flags:
 * - `magic_links`: preferred flag for magic link authentication.
 * - `email_auth`: legacy/compatibility flag used by older configurations.
 *
 * To remain backwards compatible, magic links are considered enabled if either
 * flag is explicitly set to `true`. Once all backends use a single flag, this
 * logic can be simplified.
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
  if (Array.isArray(sso.providers)) {
    return sso.providers;
  }

  return [];
}

// ── Single-auth-method restriction ──────────────────────────────────

const VALID_RESTRICT_TO: readonly string[] = ['password', 'email_auth', 'webauthn', 'sso'];

/**
 * Returns the active single-auth-method restriction, or null when all
 * enabled authentication methods are shown.
 *
 * Possible values: 'password', 'email_auth', 'webauthn', 'sso'.
 */
export function getRestrictTo(): RestrictTo | null {
  if (typeof window === 'undefined') return null;

  const features = getBootstrapValue('features');
  const value = features?.restrict_to;
  if (typeof value === 'string' && VALID_RESTRICT_TO.includes(value)) {
    return value as RestrictTo;
  }
  return null;
}

/**
 * Checks if SSO-only mode is active.
 * When true, password-based auth routes are disabled and the sign-in page
 * shows only SSO provider buttons.
 *
 * The backend only sets restrict_to='sso' when SSO is enabled and at
 * least one provider is configured, so no additional frontend guard is
 * needed.
 */
export function isSsoOnlyMode(): boolean {
  if (typeof window === 'undefined') return false;

  const result = getRestrictTo() === 'sso';
  debugLog.features('features.isSsoOnlyMode', { restrict_to: getRestrictTo(), result });
  return result;
}

/**
 * Checks if password-only mode is active.
 * When true, only the password form is shown on the login page;
 * other enabled auth methods (SSO, WebAuthn, magic links) are hidden.
 */
export function isPasswordOnlyMode(): boolean {
  return getRestrictTo() === 'password';
}

/**
 * Checks if email-auth-only (magic links) mode is active.
 * When true, only the email link form is shown on the login page.
 */
export function isEmailAuthOnlyMode(): boolean {
  return getRestrictTo() === 'email_auth';
}

/**
 * Checks if WebAuthn-only mode is active.
 * When true, only biometric/security-key authentication is shown.
 */
export function isWebAuthnOnlyMode(): boolean {
  return getRestrictTo() === 'webauthn';
}

/**
 * Checks if authentication mode is 'full' (Rodauth with SQL db).
 * When mode is 'simple' (or undefined), security features like
 * password change, MFA, sessions, and passkeys are not available.
 */
export function isFullAuthMode(): boolean {
  if (typeof window === 'undefined') return false;

  const authentication = getBootstrapValue('authentication');
  const result = authentication?.mode === 'full';
  debugLog.features('features.isFullAuthMode', { mode: authentication?.mode, result });
  return result;
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
    restrictTo: getRestrictTo(),
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
 * Default is OFF - requires explicit opt-in via ENABLE_ORGS=true.
 */
export function isOrganizationSwitcherEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  const result = features?.organizations?.enabled === true;
  debugLog.features('features.isOrganizationSwitcherEnabled', { enabled: features?.organizations?.enabled, result });
  return result;
}

/**
 * Checks if organization-level SSO configuration is enabled.
 * When true, organizations with manage_sso entitlement can configure
 * SSO for their custom domains.
 * Default is OFF - requires explicit opt-in via ORGS_SSO_ENABLED=true.
 */
export function isOrgsSsoEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  const result = features?.organizations?.sso_enabled === true;
  debugLog.features('features.isOrgsSsoEnabled', { sso_enabled: features?.organizations?.sso_enabled, result });
  return result;
}

/**
 * Checks if organization-level custom mail configuration is enabled.
 * When true, organizations with custom_mail_sender entitlement can configure
 * custom email sending for their domains.
 * Default is OFF - requires explicit opt-in via ORGS_CUSTOM_MAIL_ENABLED=true.
 */
export function isOrgsCustomMailEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  const result = features?.organizations?.custom_mail_enabled === true;
  debugLog.features('features.isOrgsCustomMailEnabled', { custom_mail_enabled: features?.organizations?.custom_mail_enabled, result });
  return result;
}

/**
 * Checks if organization-level incoming secrets configuration is enabled.
 * When true, organizations with incoming_secrets entitlement can configure
 * incoming secret receiving for their domains.
 * Default is OFF - requires explicit opt-in via ORGS_INCOMING_SECRETS_ENABLED=true.
 */
export function isOrgsIncomingSecretsEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  const result = features?.organizations?.incoming_secrets_enabled === true;
  debugLog.features('features.isOrgsIncomingSecretsEnabled', { incoming_secrets_enabled: features?.organizations?.incoming_secrets_enabled, result });
  return result;
}
