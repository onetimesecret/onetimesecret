// src/apps/admin/router.ts

import type { Router, RouteRecordRaw } from 'vue-router';
import { createRouter, createWebHistory } from 'vue-router';

import NotFound from '@/shared/components/errors/ErrorNotFound.vue';

import adminRoutes, { adminDefaultMeta } from './routes';

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
    // unknown sub-path renders the shared not-found view INSIDE the console
    // shell (spreads adminDefaultMeta → AdminLayout, not the customer layout).
    // Named 'NotFound' so the auth guard's not-found bypass exempts it
    // (guards.routes.ts): the admin router defines no /signin route, so a
    // requiresAuth catch-all would otherwise trap auth-recovery redirects in a
    // loop. The console itself stays behind the backend role=colonel gate.
    {
      path: '/:pathMatch(.*)*',
      name: 'NotFound',
      component: NotFound,
      meta: {
        ...adminDefaultMeta,
        title: 'web.TITLES.not_found',
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
