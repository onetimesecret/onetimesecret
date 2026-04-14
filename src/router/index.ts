// src/router/index.ts

import NotFound from '@/shared/components/errors/ErrorNotFound.vue';
import type { Router, RouteRecordRaw } from 'vue-router';
import { createRouter, createWebHistory } from 'vue-router';

// App-specific routes
import colonelRoutes from '@/apps/colonel/routes';
import secretRoutes from '@/apps/secret/routes';
import sessionRoutes from '@/apps/session/routes';
import workspaceRoutes from '@/apps/workspace/routes';

// Cross-cutting routes
import publicRoutes from './public.routes';

/**
 * Verifiable Identifier Format
 *
 * Distinguishes a verifiable identifier segment from a named path segment
 * (e.g., `/abc/:id` vs `/abc/items`).
 *
 * A base-36 verifiable identifier is always exactly 62 characters
 * (320 bits: 256-bit random + 64-bit HMAC tag), encoded with `[0-9a-z]`.
 * Named segments are never this length, so length alone is a reliable discriminant.
 *
 * The frontend cannot verify the HMAC (the secret is server-side only), but can
 * perform the same plausibility check used by `plausible_identifier?` on the backend:
 *
 * ```ts
 * const VERIFIABLE_ID_RE = /^[0-9a-z]{62}$/;
 *
 * function isVerifiableId(segment: string): boolean {
 *   return VERIFIABLE_ID_RE.test(segment);
 * }
 * ```
 *
 * Use this to branch route rendering — e.g. render a resource view when
 * the segment matches, a collection/action view otherwise. Treat it as a
 * format check only; the backend performs HMAC verification before authorizing.
 *
 * Routes containing verifiable identifiers (secrets, receipts) use the default
 * `sentryScrubParams` behavior (scrub all params). Routes with safe params
 * (product names, plan codes) explicitly opt out with `sentryScrubParams: false`.
 *
 * @see RouteMeta.sentryScrubParams in src/types/router.ts
 */
export const VERIFIABLE_ID_RE = /^[0-9a-z]{62}$/;

export function isVerifiableId(segment: string): boolean {
  return VERIFIABLE_ID_RE.test(segment);
}

/**
 * Route loading order - determines precedence for route matching.
 * More specific routes should come before catch-all patterns.
 */
const routeOrder = ['public', 'session', 'secret', 'workspace', 'colonel'] as const;

const routeMap: Record<(typeof routeOrder)[number], RouteRecordRaw[]> = {
  public: publicRoutes,
  session: sessionRoutes,
  secret: secretRoutes,
  workspace: workspaceRoutes,
  colonel: colonelRoutes,
};

const routes: RouteRecordRaw[] = routeOrder.flatMap((key) => routeMap[key]);

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
      // Note: Default scrubbing is enabled (sentryScrubParams omitted) because
      // pathMatch captures the full path which may contain sensitive tokens
      // from expired/mistyped secret links (e.g., /secret/MY_SECRET_KEY).
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
   * Note: Router guards are set up separately via setupRouterGuards()
   * after Pinia is installed. This is necessary because guards use
   * Pinia stores (via usePageTitle, useAuthStore, etc.).
   *
   * router.onError() is intentionally omitted to avoid redundant error handling.
   * Router errors are already handled by:
   * 1. Route guards via setupRouterGuards()
   * 2. Global error boundary (globalErrorBoundary.ts)
   * 3. useAsyncHandler composable when used in navigation guards
   */
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
