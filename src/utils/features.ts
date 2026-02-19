// src/utils/features.ts

import { getBootstrapValue } from '@/services/bootstrap.service';

/**
 * Feature detection utilities for checking enabled authentication methods
 * Features are configured on the backend via environment variables and
 * exposed through window.__BOOTSTRAP_STATE__, accessed via bootstrap.service.ts
 */

export interface AuthFeatures {
  magicLinksEnabled: boolean;
  webauthnEnabled: boolean;
  omniAuthEnabled: boolean;
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
 * Checks if OmniAuth/SSO authentication is enabled
 */
export function isOmniAuthEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const features = getBootstrapValue('features');
  // omniauth can be boolean (false) or object with enabled property
  const omniauth = features?.omniauth;
  if (typeof omniauth === 'boolean') return omniauth;
  return omniauth?.enabled === true;
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
 * Gets all enabled authentication features
 */
export function getAuthFeatures(): AuthFeatures {
  return {
    magicLinksEnabled: isMagicLinksEnabled(),
    webauthnEnabled: isWebAuthnEnabled(),
    omniAuthEnabled: isOmniAuthEnabled(),
  };
}

/**
 * Checks if any passwordless methods are enabled
 */
export function hasPasswordlessMethods(): boolean {
  return isMagicLinksEnabled() || isWebAuthnEnabled();
}
