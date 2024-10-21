import accountRoutes from '@/router/account'
import authRoutes from '@/router/auth'
import dashboardRoutes from '@/router/dashboard'
import { setupRouterGuards } from '@/router/guards'
import productRoutes from '@/router/product'
import publicRoutes from '@/router/public'
import NotFound from '@/views/NotFound.vue'
import type { RouteRecordRaw } from 'vue-router'
import { createRouter, createWebHistory } from 'vue-router'

declare module 'vue-router' {
  interface RouteMeta {
    isAdmin?: boolean
    requiresAuth?: boolean
  }
}

const routes: RouteRecordRaw[] = [
  ...publicRoutes,
  ...productRoutes,
  ...dashboardRoutes,
  ...authRoutes,
  ...accountRoutes,
]

/**
 * Creates and configures the Vue Router instance.
 *
 * This function sets up the router with the provided routes and a catch-all
 * 404 route. It also sets up router guards for authentication and locale settings.
 *
 * Purpose:
 * The purpose of this function is to encapsulate the router creation and configuration
 * logic in a single place. This makes the router setup modular and reusable, allowing
 * for easier maintenance and testing.
 *
 * Value:
 * - **Modularity**: By separating the router creation into its own function, the code
 *   becomes more modular and easier to manage.
 * - **Reusability**: This function can be reused in different parts of the application
 *   or in different projects, promoting code reuse.
 * - **Maintainability**: Encapsulating the router setup logic in a single function
 *   makes it easier to update and maintain the router configuration.
 * - **Testing**: This approach makes it easier to test the router setup in isolation.
 *
 * Performance:
 * Encapsulating the router creation in this function does not significantly slow down
 * the startup time for the frontend Vue app. The overhead introduced by this encapsulation
 * is minimal and generally outweighed by the benefits of modularity, maintainability,
 * and reusability.
 *
 * Where to Call:
 * This function is meant to be called during the setup phase of the Vue application,
 * typically in the main entry file (e.g., `main.ts`). It should be called before the
 * app is mounted to ensure that the router is properly configured and the guards are
 * in place before any navigation occurs.
 *
 * @returns {Router} The configured Vue Router instance.
 */
export function createAppRouter() {
  const router = createRouter({
    history: createWebHistory(),
    routes: [
      ...routes,
      // This catch-all 404 route is meant to be added last.
      {
        path: '/:pathMatch(.*)*',
        name: 'NotFound',
        component: NotFound
      }
    ]
  })

  // Set up router guards for authentication and locale settings
  setupRouterGuards(router);

  return router;
}
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
