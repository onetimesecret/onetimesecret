import type { RouteLocationRaw, RouteLocationNamedRaw, RouteLocationPathRaw } from 'vue-router';

// Define allowed route names
type AllowedRouteNames = 'Home' | 'Dashboard' | 'Profile';

// Type guards
function isNamedRoute(route: RouteLocationRaw): route is RouteLocationNamedRaw {
  return typeof route === 'object' && route !== null && 'name' in route;
}

function isPathRoute(route: RouteLocationRaw): route is RouteLocationPathRaw {
  return typeof route === 'object' && route !== null && 'path' in route;
}

export const validateRedirectPath = (
  path: string | RouteLocationRaw
): boolean => {

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
        return typeof path.path === 'string' &&
               path.path.startsWith('/') &&
               !path.path.includes('..');
      }

      return false;
    }

    // Handle string paths
    if (typeof path === 'string') {
      if (/^https?:\/\//i.test(path)) {
        const url = new URL(path);
        return url.hostname === window.location.hostname;
      }
      return path.startsWith('/') && !path.includes('..');
    }

    return false;
  } catch {
    return false;
  }
};
