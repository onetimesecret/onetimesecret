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

const router = createRouter({
  history: createWebHistory(),
  routes: [
    ...routes,
    // Add this catch-all 404 route at the end
    {
      path: '/:pathMatch(.*)*',
      name: 'NotFound',
      component: NotFound
    }
  ]
})

setupRouterGuards(router)

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
