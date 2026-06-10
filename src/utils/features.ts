// src/utils/features.ts

import { getBootstrapValue } from '@/services/bootstrap.service';
import {
  featuresSchema,
  type AuthenticationSettings,
  type Features,
} from '@/schemas/contracts/bootstrap';
import { debugLog } from '@/utils/debug';

/**
 * Feature detection utilities for checking enabled authentication methods
 * Features are configured on the backend via environment variables and
 * exposed through window.__BOOTSTRAP_ME__, accessed via bootstrap.service.ts
 *
 * Two predicate flavours:
 *
 * - Pure `*Of(state)` helpers operate on a bootstrap-shape input and are the
 *   single source of truth for predicate semantics. Use these from reactive
 *   contexts (Vue computeds reading the bootstrap Pinia store) so visibility
 *   updates without a page reload.
 *
 * - Snapshot-reading wrappers (`hasPassword()`, `isSsoOnlyMode()`, etc.) call
 *   the `*Of` helpers against the bootstrap snapshot. Use these from non-Vue
 *   callers (route guards, pre-Pinia consumers); they stay current because
 *   `bootstrapStore.update()` syncs the snapshot via `updateBootstrapSnapshot`.
 */

// Cached validated features object - parsed once, reused thereafter
let validatedFeaturesCache: Features | null = null;

/**
 * Returns validated features with schema enforcement.
 * Parses once and caches the result. Falls back to defaults on validation failure.
 */
function getValidatedFeatures(): Features {
  if (validatedFeaturesCache) return validatedFeaturesCache;

  if (typeof window === 'undefined') {
    return featuresSchema.parse({});
  }

  const features = getBootstrapValue('features');
  try {
    validatedFeaturesCache = featuresSchema.parse(features);
  } catch (error) {
    console.error('[Features] Bootstrap validation failed:', error);
    validatedFeaturesCache = featuresSchema.parse({});
  }

  return validatedFeaturesCache;
}

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
 * Pure predicate: MFA (TOTP + recovery codes) enabled in the given state.
 */
export function isMfaEnabledOf(state: { features?: Features }): boolean {
  return state.features?.mfa === true;
}

/**
 * Checks if MFA (TOTP + recovery codes) is enabled
 */
export function isMfaEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  return isMfaEnabledOf({ features: getBootstrapValue('features') });
}

/**
 * Pure predicate: WebAuthn enabled in the given state.
 */
export function isWebAuthnEnabledOf(state: { features?: Features }): boolean {
  return state.features?.webauthn === true;
}

/**
 * Checks if WebAuthn authentication is enabled
 */
export function isWebAuthnEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  return isWebAuthnEnabledOf({ features: getBootstrapValue('features') });
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

/**
 * Checks if SSO-only authentication is enforced for this domain.
 * When true, password-based authentication is disabled and users
 * must sign in via the configured SSO provider.
 *
 * This is a per-domain setting configured by domain administrators,
 * distinct from the app-level restrict_to='sso' mode.
 */
export function isSsoEnforcedForDomain(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getValidatedFeatures();
  const sso = features.sso;

  if (!sso || typeof sso === 'boolean') return false;

  return sso.enforce_sso_only === true;
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
 * Pure predicate: SSO-only mode active in the given state.
 */
export function isSsoOnlyModeOf(state: { features?: Features }): boolean {
  return state.features?.restrict_to === 'sso';
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

  const result = isSsoOnlyModeOf({ features: getBootstrapValue('features') });
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
 * Pure predicate: full auth mode (Rodauth with SQL db) in the given state.
 */
export function isFullAuthModeOf(state: { authentication?: AuthenticationSettings }): boolean {
  return state.authentication?.mode === 'full';
}

/**
 * Checks if authentication mode is 'full' (Rodauth with SQL db).
 * When mode is 'simple' (or undefined), security features like
 * password change, MFA, sessions, and passkeys are not available.
 */
export function isFullAuthMode(): boolean {
  if (typeof window === 'undefined') return false;

  const authentication = getBootstrapValue('authentication');
  const result = isFullAuthModeOf({ authentication });
  debugLog.features('features.isFullAuthMode', { mode: authentication?.mode, result });
  return result;
}

/**
 * Pure predicate: user has a password set in the given state.
 *
 * Accepts an optional `has_password` so the snapshot wrapper can pass through
 * `getBootstrapValue('has_password')` (which is typed as `boolean | undefined`)
 * without a coercion at every call site.
 */
export function hasPasswordOf(state: { has_password?: boolean }): boolean {
  return state.has_password === true;
}

/**
 * Checks if the current authenticated user has a password set.
 * SSO-only accounts (Entra, Google, GitHub) return false.
 * Used to hide password-based security settings for SSO-only users.
 */
export function hasPassword(): boolean {
  if (typeof window === 'undefined') return false;

  return hasPasswordOf({ has_password: getBootstrapValue('has_password') });
}

/**
 * Pure predicate: current user is owner in the given state.
 */
export function isOwnerOf(state: {
  organization?: { current_user_role?: string | null } | null;
}): boolean {
  return state.organization?.current_user_role === 'owner';
}

/**
 * Checks if the current authenticated user is an owner of their org.
 */
export function isOwner(): boolean {
  if (typeof window === 'undefined') return false;

  const org = getBootstrapValue('organization');
  return isOwnerOf({ organization: org });
}

/**
 * Pure predicate: current user is owner or admin in the given state.
 *
 * Reads `organization.current_user_role` directly from the bootstrap shape,
 * matching the `*Of` pattern used by all other feature predicates. Do NOT
 * route through useOrgPermissions here — that reads organizationStore
 * (one reactive hop later) and would cause tab flash on load.
 */
export function isOwnerOrAdminOf(state: {
  organization?: { current_user_role?: string | null } | null;
}): boolean {
  const role = state.organization?.current_user_role;
  return role === 'owner' || role === 'admin';
}

/**
 * Checks if the current authenticated user is an owner or admin in their org.
 * Used to gate account settings sections that are managed by org owners,
 * not individual members.
 */
export function isOwnerOrAdmin(): boolean {
  if (typeof window === 'undefined') return false;

  const org = getBootstrapValue('organization');
  return isOwnerOrAdminOf({ organization: org });
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
