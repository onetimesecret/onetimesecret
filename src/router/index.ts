import accountRoutes from '@/router/account'
import authRoutes from '@/router/auth'
import dashboardRoutes from '@/router/dashboard'
import productRoutes from '@/router/product'
import publicRoutes from '@/router/public'
import { useAuthStore } from '@/stores/authStore'
import { createRouter, createWebHistory } from 'vue-router'
import NotFound from '@/views/NotFound.vue'

declare module 'vue-router' {
  interface RouteMeta {
    isAdmin?: boolean
    requiresAuth?: boolean
  }
}

const router = createRouter({
  history: createWebHistory(),
  routes: [
    ...publicRoutes,
    ...productRoutes,
    ...dashboardRoutes,
    ...authRoutes,
    ...accountRoutes,

    // Add this catch-all 404 route at the end
    {
      path: '/:pathMatch(.*)*',
      name: 'NotFound',
      component: NotFound
    }
  ]
})

// NOTE: This doesn't override the server pages which redirect
// when not authenticated.
router.beforeEach(async (to) => {
  const authStore = useAuthStore()

  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    // Perform a fresh check before redirecting
    await authStore.checkAuthStatus()

    if (!authStore.isAuthenticated) {
      return {
        path: '/signin',
        query: { redirect: to.fullPath },
      }
    }
  }
})

export default router

/**
 * About Auto vs Lazy loading
 *
 * When components are auto-loaded instead of lazy-loaded, there are a few
 * potential reasons why they might not display correctly:
 *
 * 1. **Dependencies and Timing:**
 *    Auto-loaded components are imported and initialized immediately when the
 *    application starts. If these components have dependencies that are not
 *    yet available or initialized, they might not function correctly.
 *
 */
