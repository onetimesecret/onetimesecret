// src/router/guards.routes.ts

import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { usePageTitle } from '@/shared/composables/usePageTitle';
import { useAuthStore } from '@/shared/stores/authStore';
import { useLanguageStore } from '@/shared/stores/languageStore';
import { RouteLocationNormalized, Router } from 'vue-router';

import { processQueryParams } from './queryParams.handler';

export async function setupRouterGuards(router: Router): Promise<void> {
  const { setTitle } = usePageTitle();
  let currentTitle: string | null = null;

  router.beforeEach(async (to: RouteLocationNormalized) => {
    const authStore = useAuthStore();
    const languageStore = useLanguageStore();

    logNavigation(to, authStore);
    processQueryParams(to.query as Record<string, string>);

    if (to.name === 'NotFound') return true;

    // Handle MFA requirement checks
    const mfaRedirect = handleMfaAccess(to, authStore);
    if (mfaRedirect) return mfaRedirect;

    // Handle root path redirect
    if (to.path === '/') return authStore.isFullyAuthenticated ? { name: 'Dashboard' } : true;

    // Redirect fully authenticated users away from auth routes (respect redirect param)
    // MFA pending users should still access auth routes like /mfa-verify
    if (isAuthRoute(to) && authStore.isFullyAuthenticated) {
      const redirectParam = to.query.redirect as string | undefined;
      const isValidRedirect = redirectParam?.startsWith('/') && !redirectParam.startsWith('//');
      return isValidRedirect ? { path: redirectParam } : { name: 'Dashboard' };
    }

    // Validate authentication for protected routes
    if (requiresAuthentication(to)) {
      const isAuthenticated = await validateAuthentication(authStore, to);
      if (!isAuthenticated) return redirectToSignIn(to);

      const userPreferences = await fetchCustomerPreferences();
      if (userPreferences.locale) {
        languageStore.setCurrentLocale(userPreferences.locale);
      }
    }

    return true; // Always return true for non-auth routes
  });

  // Update page title after navigation completes
  router.afterEach((to: RouteLocationNormalized) => {
    // Find the title from the matched routes, starting from the most specific
    // This handles nested routes properly by inheriting from parent routes
    const nearestWithTitle = to.matched
      .slice()
      .reverse()
      .find((r) => r.meta && r.meta.title);

    let newTitle: string | null = null;

    if (nearestWithTitle) {
      newTitle = nearestWithTitle.meta.title as string;
    } else if (to.name && typeof to.name === 'string') {
      // Fallback to route name if no title is specified in the route hierarchy
      newTitle = to.name;
    }

    // Only update title if it has changed
    if (newTitle !== currentTitle) {
      currentTitle = newTitle;
      setTitle(newTitle);
    }
  });
}

function requiresAuthentication(route: RouteLocationNormalized): boolean {
  return !!route.meta?.requiresAuth;
}

function isAuthRoute(route: RouteLocationNormalized): boolean {
  return !!route.meta?.isAuthRoute;
}

/**
 * Handle MFA verification access control
 * @param to - Target route
 * @param authStore - Auth store with awaitingMfa and isFullyAuthenticated getters
 * @returns Redirect object or null if no redirect needed
 */
function handleMfaAccess(
  to: RouteLocationNormalized,
  authStore: {
    awaitingMfa: boolean;
    isFullyAuthenticated: boolean;
    isAuthenticated: boolean | null;
  }
) {
  const { awaitingMfa, isFullyAuthenticated, isAuthenticated } = authStore;

  // DEBUG: Log MFA state on every navigation
  loggingService.debug('[MFA Guard] State check:', {
    targetPath: to.path,
    targetName: to.name,
    awaitingMfa,
    isAuthenticated,
    isFullyAuthenticated,
    windowState: window.__ONETIME_STATE__,
  });

  // Redirect to MFA verification if awaiting second factor
  if (awaitingMfa && to.path !== '/mfa-verify') {
    loggingService.debug('[MFA Guard] Redirecting to /mfa-verify (awaiting MFA)');
    return { path: '/mfa-verify' };
  }

  // Prevent access to MFA verify page when not awaiting MFA
  if (to.path === '/mfa-verify' && !awaitingMfa) {
    // Use isFullyAuthenticated to determine redirect target
    const redirect = isFullyAuthenticated ? { name: 'Dashboard' } : { path: '/signin' };
    loggingService.debug('[MFA Guard] Redirecting from /mfa-verify:', {
      redirect,
      reason: 'not awaiting MFA',
    });
    return redirect;
  }

  return null;
}

function redirectToSignIn(from: RouteLocationNormalized) {
  return {
    path: '/signin',
    query: { redirect: from.fullPath },
  };
}

/** Debug logging helper for navigation guard */
function logNavigation(to: RouteLocationNormalized, authStore: AuthValidator) {
  loggingService.debug('[RouterGuard] Navigation to:', {
    path: to.path,
    name: to.name,
    requiresAuth: to.meta?.requiresAuth,
    isAuthRoute: to.meta?.isAuthRoute,
    authStoreState: {
      isAuthenticated: authStore.isAuthenticated,
      needsCheck: authStore.needsCheck,
    },
  });
}

/**
 * Interface Segregation Pattern for Auth Validation
 *
 * Instead of using the full store type (which includes many Pinia internals),
 * we define a minimal interface containing only the properties needed for
 * authentication validation. This follows the Interface Segregation Principle:
 * clients should not depend on methods they don't use.
 *
 * Evolution of this solution:
 * 1. Initially tried defining full AuthStore type with Pinia generics - too complex
 * 2. Attempted using StoreGeneric & partial types - worked but was hard to maintain
 * 3. Settled on this interface approach because:
 *    - Avoids Pinia's complex typing system altogether
 *    - Makes no assumptions about store implementation
 *    - Clearly documents what validation actually needs
 *
 * Benefits:
 * 1. Cleaner type definitions
 * 2. Better testability (can mock just these properties)
 * 3. Decoupled from Pinia implementation details
 * 4. Clearer contract for what validation requires
 *
 * The store automatically satisfies this interface through TypeScript's
 * structural typing, without explicit type casting or declarations.
 */
interface AuthValidator {
  needsCheck: boolean;
  isAuthenticated: boolean | null;
  checkWindowStatus: () => Promise<boolean | null>;
}

/**
 * Validates authentication state for protected route access
 * @param store - Auth store interface containing authentication state/methods
 * @param route - Vue Router normalized route object
 * @returns Promise<boolean> indicating if authentication is valid
 *
 * Code paths:
 * 1. Public route - Returns true without auth check
 * 2. Initial/stale auth - Performs async verification if needsCheck=true
 * 3. Cached auth - Returns existing isAuthenticated state (false if undefined)
 */
async function validateAuthentication(
  store: AuthValidator, // tried AuthStore, etc
  route: RouteLocationNormalized
): Promise<boolean> {
  if (!requiresAuthentication(route)) {
    loggingService.debug('[validateAuthentication] Public route, skipping auth check');
    return true;
  }

  loggingService.debug('[validateAuthentication] Checking auth for protected route:', {
    path: route.path,
    needsCheck: store.needsCheck,
    isAuthenticated: store.isAuthenticated,
  });

  if (store.needsCheck) {
    loggingService.debug('[validateAuthentication] needsCheck=true, calling checkWindowStatus');
    const authStatus = await store.checkWindowStatus();
    loggingService.debug('[validateAuthentication] checkWindowStatus returned:', { authStatus });
    return authStatus ?? false;
  }

  loggingService.debug('[validateAuthentication] Using cached auth state:', {
    isAuthenticated: store.isAuthenticated,
  });
  return store.isAuthenticated ?? false;
}

/**
 * Returns a dictionary of the customer's preferences.
 *
 * Currently the customer object is passed from backend on the initial
 * page load so there is no fetch happening. This implementation should
 * allow us to drop-in a request to the server when we need to.
 */
async function fetchCustomerPreferences(): Promise<{ locale?: string }> {
  const bootstrapStore = useBootstrapStore();
  // Explicitly handle null case and type narrow
  const locale = bootstrapStore.cust?.locale ?? undefined;
  return { locale };
}

export type { AuthValidator };

export {
  fetchCustomerPreferences,
  isAuthRoute,
  redirectToSignIn,
  requiresAuthentication,
  validateAuthentication,
};
