import { createRouter, createWebHistory, RouteRecordRaw } from 'vue-router'
import Homepage from '@/views/Homepage.vue'

import { ref } from 'vue'

const authState = ref(window.authenticated) // Assuming this is the variable name

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
    path: '/',
    component: Homepage,
    beforeEnter: (to, from, next) => {
      if (authState.value) {
        next({ name: 'Dashboard' })
      } else {
        next()
      }
    }
  },
  {
    path: '/incoming',
    name: 'Inbound Secrets',
    component: () => import('@/views/secrets/InboundSecret.vue'),
    meta: { requiresAuth: true }
  },
  {
    path: '/dashboard',
    name: 'Dashboard',
    component: () => import('@/views/dashboard/DashboardIndex.vue'),
    meta: { requiresAuth: true }
  },
  {
    path: '/recent',
    name: 'Recents',
    component: () => import('@/views/dashboard/DashboardRecent.vue'),
    meta: { requiresAuth: true }
  },
  {
    path: '/account/domains/:domain/verify',
    name: 'AccountDomainVerify',
    component: () => import('@/views/account/AccountDomainVerify.vue'),
    meta: { requiresAuth: true },
    props: true,
  },
  {
    path: '/account/domains/add',
    name: 'AccountDomainAdd',
    component: () => import('@/views/account/AccountDomainAdd.vue'),
    meta: { requiresAuth: true },
    props: true,
  },
  {
    path: '/account/domains',
    name: 'AccountDomains',
    component: () => import('@/views/account/AccountDomains.vue'),
    meta: { requiresAuth: true },
    props: true,
  },
  {
    path: '/account',
    name: 'Account',
    component: () => import('@/views/account/AccountIndex.vue'),
    meta: { requiresAuth: true },
  },
  {
    path: '/info/privacy',
    name: 'Privacy Policy',
    component: () => import('@/views/info/PrivacyDoc.vue'),
    props: true,
  },
  {
    path: '/info/terms',
    name: 'Terms of Use',
    component: () => import('@/views/info/TermsDoc.vue'),
    props: true,
  },
  {
    path: '/info/security',
    name: 'Security Policy',
    component: () => import('@/views/info/SecurityDoc.vue'),
    props: true,
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
    path: '/pricing',
    name: 'Pricing',
    component: () => import('@/views/PricingDual.vue'),
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
  {
    path: '/signin',
    name: 'Sign In',
    component: () => import('@/views/Signin.vue'),
  },
  {
    path: '/signup/:planCode',
    name: 'Sign Up',
    component: () => import('@/views/Signup.vue'),
    props: true,
  },
  {
    path: '/signup',
    name: 'Sign Up',
    component: () => import('@/views/Signup.vue'),
  },
  {
    path: '/about',
    name: 'About',
    component: () => import('@/views/About.vue'),
  },
  {
    path: '/translations',
    name: 'Translations',
    component: () => import('@/views/Translations.vue'),
  },
  {
    path: '/logout',
    name: 'Logout',
    component: { render: () => null }, // Dummy component
    beforeEnter: () => {
      window.location.href = '/logout'
    }
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

router.beforeEach((to, from, next) => {
  if (to.meta.requiresAuth && !authState.value) {
    next('/')
  } else {
    next()
  }
})

export default router
