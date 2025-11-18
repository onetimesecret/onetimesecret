// src/router/guards.routes.ts

import { usePageTitle } from '@/composables/usePageTitle';
import { WindowService } from '@/services/window.service';
import { useAuthStore } from '@/stores/authStore';
import { useLanguageStore } from '@/stores/languageStore';
import { RouteLocationNormalized, Router } from 'vue-router';

import { processQueryParams } from './queryParams.handler';

export async function setupRouterGuards(router: Router): Promise<void> {
  const { setTitle } = usePageTitle();
  let currentTitle: string | null = null;

  router.beforeEach(async (to: RouteLocationNormalized) => {
    console.group('🛣️ Router Guard: beforeEach');
    console.log('Navigating to:', to.path);
    console.log('Route name:', to.name);
    console.log('Timestamp:', new Date().toISOString());

    const authStore = useAuthStore();
    const languageStore = useLanguageStore();

    console.log('Auth store state:', {
      isAuthenticated: authStore.isAuthenticated,
      isInitialized: authStore.isInitialized,
      needsCheck: authStore.needsCheck,
    });

    processQueryParams(to.query as Record<string, string>);

    if (to.name === 'NotFound') {
      console.log('Route is NotFound, allowing');
      console.groupEnd();
      return true;
    }

    // Handle MFA requirement checks
    const mfaRedirect = handleMfaAccess(to, authStore.isAuthenticated);
    if (mfaRedirect) {
      console.log('MFA redirect required:', mfaRedirect);
      console.groupEnd();
      return mfaRedirect;
    }

    // Handle root path redirect
    if (to.path === '/') {
      const redirect = authStore.isAuthenticated ? { name: 'Dashboard' } : true;
      console.log('Root path redirect:', redirect);
      console.groupEnd();
      return redirect;
    }

    // Redirect authenticated users away from auth routes
    if (isAuthRoute(to) && authStore.isAuthenticated) {
      console.log('Auth route with authenticated user, redirecting to Dashboard');
      console.groupEnd();
      return { name: 'Dashboard' };
    }

    // Validate authentication for protected routes
    if (requiresAuthentication(to)) {
      console.log('Route requires authentication, validating...');
      const isAuthenticated = await validateAuthentication(authStore, to);
      console.log('Validation result:', isAuthenticated);

      if (!isAuthenticated) {
        console.warn('❌ Authentication failed, redirecting to signin');
        console.groupEnd();
        return redirectToSignIn(to);
      }

      const userPreferences = await fetchCustomerPreferences();
      if (userPreferences.locale) {
        languageStore.setCurrentLocale(userPreferences.locale);
      }
    }

    console.log('✅ Navigation allowed');
    console.groupEnd();
    return true; // Always return true for non-auth routes
  });

  // Update page title after navigation completes
  router.afterEach((to: RouteLocationNormalized) => {
    // Find the title from the matched routes, starting from the most specific
    // This handles nested routes properly by inheriting from parent routes
    const nearestWithTitle = to.matched.slice().reverse().find(r => r.meta && r.meta.title);

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
 * @param isAuthenticated - Current authentication status
 * @returns Redirect object or null if no redirect needed
 */
function handleMfaAccess(to: RouteLocationNormalized, isAuthenticated: boolean | null) {
  const awaitingMfa = WindowService.get('awaiting_mfa');

  // Redirect to MFA verification if awaiting second factor
  if (awaitingMfa && to.path !== '/mfa-verify') {
    return { path: '/mfa-verify' };
  }

  // Prevent access to MFA verify page when not awaiting MFA
  if (to.path === '/mfa-verify' && !awaitingMfa) {
    return isAuthenticated ? { name: 'Dashboard' } : { path: '/signin' };
  }

  return null;
}

function redirectToSignIn(from: RouteLocationNormalized) {
  return {
    path: '/signin',
    query: { redirect: from.fullPath },
  };
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
  if (import.meta.env.DEV) {
    console.group('🔍 validateAuthentication');
    console.log('Route requires auth:', requiresAuthentication(route));
    console.log('Store needsCheck:', store.needsCheck);
    console.log('Store isAuthenticated:', store.isAuthenticated);
  }

  if (!requiresAuthentication(route)) {
    if (import.meta.env.DEV) {
      console.log('Route does not require auth, returning true');
      console.groupEnd();
    }
    return true;
  }

  if (store.needsCheck) {
    if (import.meta.env.DEV) {
      console.log('Needs check, calling checkWindowStatus...');
    }
    const authStatus = await store.checkWindowStatus();
    if (import.meta.env.DEV) {
      console.log('checkWindowStatus returned:', authStatus);
    }
    const result = authStatus ?? false;
    if (import.meta.env.DEV) {
      console.log('Final result (after coalescing):', result);
      console.groupEnd();
    }
    return result;
  }

  const result = store.isAuthenticated ?? false;
  if (import.meta.env.DEV) {
    console.log('Using cached auth state:', result);
    console.groupEnd();
  }
  return result;
}

/**
 * Returns a dictionary of the customer's preferences.
 *
 * Currently the customer object is passed from backend on the initial
 * page load so there is no fetch happening. This implementation should
 * allow us to drop-in a request to the server when we need to.
 */
async function fetchCustomerPreferences(): Promise<{ locale?: string }> {
  const cust = WindowService.get('cust');
  // Explicitly handle null case and type narrow
  const locale = cust?.locale ?? undefined;
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
