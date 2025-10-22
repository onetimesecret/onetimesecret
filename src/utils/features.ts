// src/utils/features.ts

/**
 * Feature detection utilities for checking enabled authentication methods
 * Features are configured on the backend via environment variables and
 * exposed through window.__ONETIME_STATE__
 */

export interface AuthFeatures {
  magicLinksEnabled: boolean;
  webauthnEnabled: boolean;
}

/**
 * Checks if magic link authentication is enabled
 */
export function isMagicLinksEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const state = (window as any).__ONETIME_STATE__;
  return state?.features?.magic_links === true || state?.features?.email_auth === true;
}

/**
 * Checks if WebAuthn authentication is enabled
 */
export function isWebAuthnEnabled(): boolean {
  if (typeof window === 'undefined') return false;

  const state = (window as any).__ONETIME_STATE__;
  return state?.features?.webauthn === true;
}

/**
 * Gets all enabled authentication features
 */
export function getAuthFeatures(): AuthFeatures {
  return {
    magicLinksEnabled: isMagicLinksEnabled(),
    webauthnEnabled: isWebAuthnEnabled(),
  };
}

/**
 * Checks if any passwordless methods are enabled
 */
export function hasPasswordlessMethods(): boolean {
  return isMagicLinksEnabled() || isWebAuthnEnabled();
}
