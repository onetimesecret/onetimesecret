// src/utils/redirect.ts

import type {
  RouteLocationNamedRaw,
  RouteLocationPathRaw,
  RouteLocationRaw,
} from 'vue-router';

// Define allowed route names
type AllowedRouteNames = 'Home' | 'Dashboard' | 'Profile';

// Type guards
function isNamedRoute(route: RouteLocationRaw): route is RouteLocationNamedRaw {
  return typeof route === 'object' && route !== null && 'name' in route;
}

function isPathRoute(route: RouteLocationRaw): route is RouteLocationPathRaw {
  return typeof route === 'object' && route !== null && 'path' in route;
}

export const validateRedirect = (path: string | RouteLocationRaw): boolean => {
  if (!path) return false;

  try {
    // Handle route objects
    if (typeof path === 'object' && path !== null) {
      // Validate named routes
      if (isNamedRoute(path)) {
        const allowedRoutes: AllowedRouteNames[] = ['Home', 'Dashboard', 'Profile'];
        return allowedRoutes.includes(path.name as AllowedRouteNames);
      }

      // Validate path-based routes
      if (isPathRoute(path)) {
        return typeof path.path === 'string' && validatePathString(path.path);
      }

      return false;
    }

    // Handle string paths
    if (typeof path === 'string') {
      // Handle absolute URLs and protocol-relative URLs
      if (path.startsWith('//') || /^https?:\/\//i.test(path)) {
        return validateUrl(path);
      }
      return validatePathString(path);
    }

    return false;
  } catch {
    return false;
  }
};

/**
 * Validates that a path is a safe internal redirect.
 * Security: Prevents open redirect attacks by ensuring path is internal only.
 *
 * @param path - The path to validate
 * @returns true if path is a valid internal redirect
 */
export function isValidInternalPath(path: string | undefined | null): path is string {
  if (!path || typeof path !== 'string') return false;
  // Max length to prevent DoS
  if (path.length > 2048) return false;
  // Must start with single slash, not double (protocol-relative)
  if (!path.startsWith('/') || path.startsWith('//')) return false;
  // Must not contain protocol
  if (path.includes('://')) return false;
  return true;
}

function validatePathString(path: string): boolean {
  try {
    // Handle absolute URLs and protocol-relative URLs
    if (path.startsWith('//') || /^https?:\/\//i.test(path)) {
      return validateUrl(path);
    }

    // Decode the path to catch encoded traversal attempts
    const decodedPath = decodeURIComponent(path);

    // Check for path traversal attempts
    if (decodedPath.includes('..') || decodedPath.includes('./')) {
      return false;
    }

    // Check for suspicious protocols
    const suspiciousProtocols = [/javascript:/i, /data:/i, /vbscript:/i, /file:/i];

    if (suspiciousProtocols.some((pattern) => pattern.test(decodedPath))) {
      return false;
    }

    // Must start with single forward slash
    return decodedPath.startsWith('/');
  } catch {
    return false;
  }
}

/**
 * Validates that a checkout URL is safe to navigate to via `window.location`.
 *
 * Security (M-9): `checkout_url` is API-derived and assigned directly to
 * `window.location.href` in the billing plan flow. Restrict navigation to the
 * Stripe Checkout host or the app's own origin so a tampered/unexpected value
 * cannot drive an open redirect. The internal validators in this module
 * (isValidInternalPath, validateRedirect, validateUrl) only permit same-origin
 * internal targets, so an external-host allowlist requires this dedicated helper.
 *
 * The host allowlist is intentionally exact — Stripe Checkout is served only
 * from `checkout.stripe.com`; do not loosen to a wildcard `*.stripe.com`.
 *
 * @param url - The checkout URL to validate
 * @returns true only when the URL parses and its origin is the Stripe Checkout
 *          host or the current origin
 */
export function isAllowedCheckoutUrl(url: string | undefined | null): url is string {
  if (!url || typeof url !== 'string') return false;
  try {
    const { origin } = new URL(url);
    return origin === 'https://checkout.stripe.com' || origin === window.location.origin;
  } catch {
    return false;
  }
}

function validateUrl(url: string): boolean {
  try {
    // For protocol-relative URLs, use current protocol
    let urlToValidate = url;
    if (url.startsWith('//')) {
      // Change from window.location.protocol to explicitly using https:
      urlToValidate = `https:${url}`;
    }

    // For relative URLs, use current origin as base
    const fullUrl = new URL(urlToValidate, window.location.origin);

    // Compare hostnames, ignoring port numbers
    const currentHostname = window.location.hostname;
    return fullUrl.hostname === currentHostname;
  } catch {
    return false;
  }
}
