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

export const validateRedirectPath = (path: string | RouteLocationRaw): boolean => {
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
      if (/^https?:\/\//i.test(path)) {
        const url = new URL(path);
        return url.hostname === window.location.hostname;
      }
      return validatePathString(path);
    }

    return false;
  } catch {
    return false;
  }
};

export function validatePathString(path: string): boolean {
  try {
    // Decode the path to catch encoded traversal attempts
    const decodedPath = decodeURIComponent(path);

    // Check for path traversal attempts
    if (decodedPath.includes('..') || decodedPath.includes('./')) {
      return false;
    }

    // Check for suspicious patterns
    const suspiciousPatterns = [
      /\/\/+/, // Multiple forward slashes
      /javascript:/i, // JavaScript protocol
      /data:/i, // Data protocol
      /vbscript:/i, // VBScript protocol
      /file:/i, // File protocol
      /%2e/i, // Encoded dot
      /\\+/, // Backslashes
    ];

    if (suspiciousPatterns.some((pattern) => pattern.test(decodedPath))) {
      return false;
    }

    // Must start with single forward slash and contain no traversal
    return (
      decodedPath.startsWith('/') &&
      !decodedPath.includes('\\') &&
      !decodedPath.includes('\0')
    );
  } catch {
    return false;
  }
}
