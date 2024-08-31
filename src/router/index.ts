import { createRouter, createWebHistory, RouteRecordRaw } from 'vue-router'
import AccountDomainAdd from '@/views/account/AccountDomainAdd.vue'
import AccountDomains from  '@/views/account/AccountDomains.vue'
import Homepage from '@/views/Homepage.vue'

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
const routes: Array<RouteRecordRaw> = [
  {
    path: '/account/domains/add',
    name: 'AccountDomainAdd',
    component: AccountDomainAdd,
  },
  {
    path: '/account/domains',
    name: 'AccountDomains',
    component: AccountDomains,
  },
  {
    path: '/',
    name: 'Homepage',
    component: Homepage,
  },
  {
    path: '/account/domains/:domain/verify',
    name: 'AccountDomainVerify',
    component: () => import('@/views/account/AccountDomainVerify.vue'),
    props: true,
  },
  {
    path: '/pricing',
    name: 'Pricing',
    component: () => import('@/views/PricingDual.vue'),
  },
  {
    path: '/',
    name: 'Dashboard',
    component: () => import('@/views/Dashboard.vue'),
  },

  {
    path: '/account',
    name: 'Account',
    component: () => import('@/views/account/AccountIndex.vue'),
  },
  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    component: () => import('@/views/Secret.vue'),
    props: true,
  },
  {
    path: '/private/:metadataKey',
    name: 'Metadata link',
    component: () => import('@/views/Metadata.vue'),
    props: true,
  },
  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/views/Feedback.vue'),
  },
  {
    path: '/forgot',
    name: 'Forgot',
    component: () => import('@/components/PasswordStrengthChecker.vue'),
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
