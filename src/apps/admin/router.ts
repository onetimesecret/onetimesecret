// src/apps/admin/router.ts

import type { Router, RouteRecordRaw } from 'vue-router';
import { createRouter, createWebHistory } from 'vue-router';

import NotFound from '@/shared/components/errors/ErrorNotFound.vue';

import adminRoutes from './routes';

/**
 * Router for the isolated admin (Colonel) console bundle (`src/admin.ts`).
 *
 * Deliberately does NOT import `@/router`: the admin bundle must not pull the
 * customer route graph (public/session/secret/workspace/colonel) into its
 * single chunk. Only admin routes live here. Guards (auth, page title) are
 * still applied by the shared `AppInitializer` via `setupRouterGuards`.
 */
export function createAdminRouter(): Router {
  const routes: RouteRecordRaw[] = [
    ...adminRoutes,
    // Catch-all: the admin shell is served for /colonel and /colonel/*, so an
    // unknown sub-path renders the shared not-found view rather than a blank
    // page. requiresAuth is kept true — the whole console is behind role=colonel.
    {
      path: '/:pathMatch(.*)*',
      name: 'AdminNotFound',
      component: NotFound,
      meta: {
        title: 'web.TITLES.not_found',
        requiresAuth: true,
      },
    },
  ];

  return createRouter({
    history: createWebHistory(),
    routes,
    scrollBehavior(_to, _from, savedPosition) {
      return savedPosition ?? { top: 0 };
    },
  });
}
