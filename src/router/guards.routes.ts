// src/router/guards.ts

import { WindowService } from '@/services/window.service';
import { useAuthStore } from '@/stores/authStore';
import { useLanguageStore } from '@/stores/languageStore';
import { RouteLocationNormalized, Router } from 'vue-router';
import { processQueryParams } from './queryParams.handler';

export async function setupRouterGuards(router: Router): Promise<void> {
  router.beforeEach(async (to: RouteLocationNormalized) => {
    const authStore = useAuthStore();
    const languageStore = useLanguageStore();

    processQueryParams(to.query as Record<string, string>);

    if (to.name === 'NotFound') {
      return true;
    }

    // Handle root path redirect
    if (to.path === '/') {
      return authStore.isAuthenticated ? { name: 'Dashboard' } : true;
    }

    // Redirect authenticated users away from auth routes
    if (isAuthRoute(to) && authStore.isAuthenticated) {
      return { name: 'Dashboard' };
    }

    // Validate authentication for protected routes
    if (requiresAuthentication(to)) {
      const isAuthenticated = await validateAuthentication(authStore, to);
      if (!isAuthenticated) {
        return redirectToSignIn(to);
      }

      const userPreferences = await fetchCustomerPreferences();
      if (userPreferences.locale) {
        languageStore.setCurrentLocale(userPreferences.locale);
      }
    }

    return true; // Always return true for non-auth routes
  });
}

function requiresAuthentication(route: RouteLocationNormalized): boolean {
  return !!route.meta?.requiresAuth;
}

function isAuthRoute(route: RouteLocationNormalized): boolean {
  return !!route.meta?.isAuthRoute;
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
  checkAuthStatus: () => Promise<boolean | null>;
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
  if (!requiresAuthentication(route)) return true;

  if (store.needsCheck) {
    const authStatus = await store.checkAuthStatus();
    return authStatus ?? false; // Coalesce null to false
  }
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
  const cust = WindowService.get('cust');
  // Explicitly handle null case and type narrow
  const locale = cust?.locale ?? undefined;
  return { locale };
}

export {
  AuthValidator,
  fetchCustomerPreferences,
  isAuthRoute,
  redirectToSignIn,
  requiresAuthentication,
  validateAuthentication,
};
