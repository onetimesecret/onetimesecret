import { Router, RouteLocationNormalized } from 'vue-router'
import { useAuthStore } from '@/stores/authStore'
import { useLanguageStore } from '@/stores/languageStore'
import { useWindowProp } from '@/composables/useWindowProps'

// src/router/guards.ts
export function setupRouterGuards(router: Router) {
  router.beforeEach(async (to: RouteLocationNormalized) => {
    const authStore = useAuthStore();
    const languageStore = useLanguageStore();

    // Don't check auth for sign-in page to avoid redirect loops
    if (to.path === '/signin') {
      return true;
    }

    if (requiresAuthentication(to)) {
      try {
        const isAuthenticated = await authStore.checkAuthStatus();

        if (!isAuthenticated) {
          // Handle logout cleanup here instead of in the auth store
          authStore.$logout(); // This will clear cookies
          return redirectToSignIn(to);
        }

        // Proceed with navigation
        const userPreferences = await fetchCustomerPreferences();
        if (userPreferences.locale) {
          languageStore.setCurrentLocale(userPreferences.locale);
        }
      } catch (error) {
        console.error('Navigation guard error:', error);
        authStore.$logout(); // Clear cookies
        return redirectToSignIn(to);
      }
    }
  });
}

function requiresAuthentication(route: RouteLocationNormalized): boolean {
  return !!route.meta.requiresAuth
}

function redirectToSignIn(from: RouteLocationNormalized) {
  return {
    path: '/signin',
    query: { redirect: from.fullPath },
  }
}

/**
 * Returns a dictionary of the customer's preferences.
 *
 * Currently the customer object is passed from backend on the initial
 * page load so there is no fetch happening. This implementation should
 * allow us to drop-in a request to the server when we need to.
 */
async function fetchCustomerPreferences(): Promise<{ locale?: string }> {
  const cust = useWindowProp('cust');
  return { locale: cust.value?.locale }
}
