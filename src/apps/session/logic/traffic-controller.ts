import { RouteLocationNormalized } from 'vue-router';

export interface TrafficDecision {
  redirect: string | null;
  reason: string;
}

/**
 * Determines where to redirect after authentication events.
 */
export function afterLogin(
  from: RouteLocationNormalized,
  intendedDestination?: string
): TrafficDecision {
  // Priority 1: Explicit return_to parameter
  const returnTo = from.query.return_to as string | undefined;
  if (returnTo && isValidReturnPath(returnTo)) {
    return { redirect: returnTo, reason: 'return_to parameter' };
  }

  // Priority 2: Intended destination (stored before auth redirect)
  if (intendedDestination && isValidReturnPath(intendedDestination)) {
    return { redirect: intendedDestination, reason: 'stored destination' };
  }

  // Priority 3: Default to dashboard
  return { redirect: '/dashboard', reason: 'default' };
}

export function afterLogout(): TrafficDecision {
  return { redirect: '/', reason: 'logout default' };
}

export function afterSignup(): TrafficDecision {
  return { redirect: '/dashboard', reason: 'new account' };
}

function isValidReturnPath(path: string): boolean {
  // Must be relative path, no protocol
  if (path.includes('://')) return false;
  if (!path.startsWith('/')) return false;
  // Block auth pages to prevent loops
  if (path.startsWith('/signin') || path.startsWith('/signup')) return false;
  return true;
}
