import DefaultLayout from '@/layouts/DefaultLayout.vue'
import QuietLayout from '@/layouts/QuietLayout.vue'
import WideLayout from '@/layouts/WideLayout.vue'
import { useCsrfStore } from '@/stores/csrfStore'
import { useLanguageStore } from '@/stores/languageStore'
import { SecretDataApiResponse } from '@/types/onetime'
import Homepage from '@/views/Homepage.vue'
import { createRouter, createWebHistory, RouteRecordRaw } from 'vue-router'

import DashboardIndex from '@/views/dashboard/DashboardIndex.vue'
import DashboardRecent from '@/views/dashboard/DashboardRecent.vue'
import BurnSecret from '@/views/secrets/BurnSecret.vue'
import IncomingSupportSecret from '@/views/secrets/IncomingSupportSecret.vue'
import ShowMetadata from '@/views/secrets/ShowMetadata.vue'
import ShowSecret from '@/views/secrets/ShowSecret.vue'
import { ref } from 'vue'

const authState = ref(window.authenticated) // Assuming this is the variable name

declare module 'vue-router' {
  interface RouteMeta {
    // is optional
    isAdmin?: boolean
    // must be declared by every route
    requiresAuth?: boolean
  }
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
import { AsyncDataResult, fetchInitialSecret } from '@/api/secrets'

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
    },
    meta: {
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      }
    },

  },
  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    component: ShowSecret,
    //component: () => import('@/views/secrets/ShowSecret.vue'),
    props: true,
    meta: {
      layout: QuietLayout,
      layoutProps: {
        displayMasthead: false,
        displayLinks: false,
        displayFeedback: false,
        displaySitenav: false,
        displayVersion: false,
        displayPoweredBy: true,
        noCache: true,
      },
    },
    beforeEnter: async (to, from, next) => {
      try {
        const secretKey = to.params.secretKey as string;
        const initialData: AsyncDataResult<SecretDataApiResponse> = await fetchInitialSecret(secretKey);
        to.meta.initialData = initialData;
        next();
      } catch (error) {
        console.error('Error fetching initial page data:', error);
        next(new Error('Failed to fetch initial page data'));
      }
    },
  },
  {
    path: '/private/:metadataKey',
    name: 'Metadata link',
    component: ShowMetadata,
    props: true,
    meta: {
      layoutProps: {
        displayFeedback: false,
        noCache: true,
      }
    },
  },
  {
    path: '/private/:metadataKey/burn',
    name: 'Burn secret',
    component: BurnSecret,
    props: true,
    meta: {
      layoutProps: {
        displayFeedback: false,
      }
    }
  },
  {
    path: '/dashboard',
    name: 'Dashboard',
    component: DashboardIndex,
    meta: { requiresAuth: true }
  },
  {
    path: '/recent',
    name: 'Recents',
    component: DashboardRecent,
    meta: { requiresAuth: true }
  },
  {
    path: '/incoming',
    name: 'Inbound Secrets',
    component: IncomingSupportSecret,
    meta: { requiresAuth: false }
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
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayFeedback: false,
      }
    },
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
    meta: {
      requiresAuth: true
    },
  },
  {
    path: '/colonel',
    name: 'Colonel',
    component: () => import('@/views/colonel/ColonelIndex.vue'),
    meta: {
      isAdmin: true,
      requiresAuth: true,
      layout: DefaultLayout,
    },
    props: true,
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
    path: '/pricing',
    name: 'Pricing',
    component: () => import('@/views/pricing/PricingDual.vue'),
    meta: {
      layout: WideLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
        displaySitenav: true,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
    props: true,
  },
  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/views/Feedback.vue'),
    meta: {
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: false,
      }
    }
  },
  {
    path: '/forgot',
    name: 'Forgot',
    component: () => import('@/views/auth/PasswordReset.vue'),
  },
  {
    path: '/signin',
    name: 'Sign In',
    component: () => import('@/views/auth/Signin.vue'),
  },
  {
    path: '/signup',
    children: [
      {
        path: '',
        name: 'Sign Up',
        component: () => import('@/views/auth/Signup.vue'),
      },
      {
        path: ':planCode',
        name: 'Sign Up with Plan',
        component: () => import('@/views/auth/Signup.vue'),
        props: true,
      },
    ],
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
      // Clear all local storage
      localStorage.clear();

      // Reset stores
      const languageStore = useLanguageStore();
      const csrfStore = useCsrfStore();

      languageStore.$reset();
      csrfStore.$reset();

      // Set auth state to false
      authState.value = false;

      // Redirect to logout URL
      window.location.href = '/logout';
    }
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes
})
// NOTE: This doesn't override the server pages which redirect
// when not authenticated.
// https://router.vuejs.org/guide/advanced/meta.html
router.beforeEach((to) => {
  // instead of having to check every route record with
  // to.matched.some(record => record.meta.requiresAuth)
  if (to.meta.requiresAuth && !authState.value) {
    // this route requires auth, check if logged in
    // if not, redirect to login page.
    return {
      path: '/login',
      // save the location we were at to come back later
      query: { redirect: to.fullPath },
    }
  }
})

export default router
