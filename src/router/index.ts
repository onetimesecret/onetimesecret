import { ref } from 'vue'
import { createRouter, createWebHistory } from 'vue-router'
import publicRoutes from '@/router/public'
import accountRoutes from '@/router/account'
import productRoutes from '@/router/product'
import secretRoutes from '@/router/secrets'
import authRoutes from '@/router/auth'

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
    ...secretRoutes,
    ...authRoutes,
    ...accountRoutes,
  ]
})

// NOTE: This doesn't override the server pages which redirect
// when not authenticated.
const authState = ref(window.authenticated);
router.beforeEach((to) => {
  // Redirect unless logged in
  if (to.meta.requiresAuth && !authState.value) {
    return {
      path: '/login',
      // Save the location we were at to come back later
      query: { redirect: to.fullPath },
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
 * 2. **Component Lifecycle:**
 *    Lazy-loaded components are only imported when they are needed, which can
 *    help ensure that all necessary dependencies and context are available.
 *    Auto-loading might bypass some of these checks.
 *
 * 3. **Route Parameters and Initialization:**
 *    Components that rely on route parameters (e.g., to determine the active
 *    domain) might encounter issues if they are auto-loaded. This is because
 *    the route parameters might not be available or fully resolved at the time
 *    the component is initialized. Lazy loading ensures that the component is
 *    only initialized after the route has been fully resolved, preventing such
 *    issues.
 *
 * 4. **Code Splitting and Bundle Size:**
 *   Lazy loading helps reduce the initial bundle size by splitting the
 *   application into smaller chunks that are only loaded when needed.
 *
 * When to use `defineAsyncComponent` vs dynamic imports:
 *   Use `defineAsyncComponent` for lazy loading components with additional
 *   features like handling loading and error states, or when using Suspense.
 *   Use dynamic imports (`() => import('./MyPage.vue')`) for simpler lazy
 *   loading when additional features are not needed.
 *
 * @see [Vue3 documentation on dynamic imports](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/import#dynamic_imports)
 * @see [Vue3 documentation on `defineAsyncComponent`](https://v3.vuejs.org/guide/component-dynamic-async.html#async-components)
 */
