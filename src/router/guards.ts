import { Router, RouteLocationNormalized } from 'vue-router'
import { useAuthStore } from '@/stores/authStore'
import { useLanguageStore } from '@/stores/languageStore'
import { useWindowProp } from '@/composables/useWindowProps'

export function setupRouterGuards(router: Router) {
  router.beforeEach(async (to: RouteLocationNormalized) => {
    const authStore = useAuthStore();
    const languageStore = useLanguageStore();
    const userPreferences = await fetchCustomerPreferences();

    // Language guard
    console.debug("initialized with lang: ", languageStore.currentLocale)
    console.debug('Checking if user preferences contain a locale...')
    if (userPreferences.locale) {
      console.debug('User preferences contain a locale:', userPreferences.locale)
      languageStore.setCurrentLocale(userPreferences.locale)
    } else {
      console.debug('No locale found in user preferences.')
    }


    if (requiresAuthentication(to) && !authStore.isAuthenticated) {
      await refreshAuthStatus(authStore)

      if (!authStore.isAuthenticated) {
        return redirectToSignIn(to)
      }
    }
  })
}

function requiresAuthentication(route: RouteLocationNormalized): boolean {
  return !!route.meta.requiresAuth
}

async function refreshAuthStatus(authStore: ReturnType<typeof useAuthStore>): Promise<void> {
  await authStore.checkAuthStatus()
  console.debug('Updated auth status:', authStore.isAuthenticated)
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
