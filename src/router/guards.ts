import { Router, RouteLocationNormalized } from 'vue-router'
import { useAuthStore } from '@/stores/authStore'

export function setupRouterGuards(router: Router) {
  router.beforeEach(async (to: RouteLocationNormalized) => {
    const authStore = useAuthStore()

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
