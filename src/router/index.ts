// src/router/index.ts

import { setupRouterGuards } from '@/router/guards.routes';
import NotFound from '@/views/NotFound.vue';
import type { Router, RouteRecordRaw } from 'vue-router';
import { createRouter, createWebHistory } from 'vue-router';

import accountRoutes from './account.routes';
import authRoutes from './auth.routes';
import colonelRoutes from './colonel.routes';
import dashboardRoutes from './dashboard.routes';
import metadataRoutes from './metadata.routes';
import publicRoutes from './public.routes';
import secretRoutes from './secret.routes';
import teamsRoutes from './teams.routes';

const routes: RouteRecordRaw[] = [
  ...publicRoutes,
  ...metadataRoutes,
  ...secretRoutes,
  ...authRoutes,
  ...dashboardRoutes,
  ...accountRoutes,
  ...teamsRoutes,
  ...colonelRoutes,
];

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
export function createAppRouter(): Router {
  const router = createRouter({
    history: createWebHistory(),
    routes: [
      ...routes,
      // This catch-all 404 route is meant to be added last.
      {
        path: '/:pathMatch(.*)*',
        name: 'NotFound',
        component: NotFound,
        meta: {
          title: 'web.TITLES.not_found',
          requiresAuth: false,
        },
      },
    ],
    scrollBehavior(to, from, savedPosition) {
      // always scroll to top
      if (savedPosition) {
        return savedPosition;
      } else {
        return { top: 0 };
      }
    },
  });

  /**
   * router.onError() is intentionally omitted to avoid redundant error handling.
   *
   * Router errors are already handled by:
   * 1. Route guards via setupRouterGuards()
   * 2. Global error boundary (globalErrorBoundary.ts)
   * 3. useAsyncHandler composable when used in navigation guards or composables.
   *
   * Router errors fall into two main categories:
   * - Navigation failures: Handled by guards and classifyError()
   * - Chunk loading failures: Caught by global error handler
   *
   * Adding router.onError would:
   * - Create duplicate error handling paths
   * - Interfere with our centralized error classification flow
   * - Add unnecessary complexity to the error architecture
   *
   * For new router-related error cases, extend the existing guard or
   * classification system rather than adding a new error handler here.
   *
   * Set up router guards for authentication and locale settings
   */
  setupRouterGuards(router);

  return router;
}

/**
 * About Auto vs Lazy loading
 *
 * **Dependencies and Timing:**
 *    Auto-loaded components are imported and initialized immediately when the
 *    application starts. If these components have dependencies that are not
 *    yet available or initialized, they might not function correctly.
 */
