/* src/router/auth.routes.ts */
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import QuietLayout from '@/layouts/QuietLayout.vue';
import { useAuthStore } from '@/stores/authStore';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/signin',
    name: 'Sign In',
    component: () => import('@/views/auth/Signin.vue'),
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
    },
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
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
      },
    },
  },
  {
    path: '/forgot',
    children: [
      {
        path: '',
        name: 'Forgot Password',
        component: () => import('@/views/auth/PasswordResetRequest.vue'),
      },
      {
        path: ':resetKey',
        name: 'Reset Password',
        component: () => import('@/views/auth/PasswordReset.vue'),
        props: true,
      },
    ],
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: true,
        displayVersion: false,
      },
    },
  },
  {
    path: '/logout',
    name: 'Logout',
    component: { render: () => null }, // Dummy component
    meta: {
      requiresAuth: true,
      layout: QuietLayout,
      layoutProps: {},
    },
    beforeEnter: async () => {
      const authStore = useAuthStore();

      try {
        // Call centralized logout logic
        await authStore.logout(); // this returns a promise
      } catch (error) {
        console.error('Logout failed:', error);
      }

      // Force a full page load from the server
      window.location.href = '/logout';
    },
  },
  {
    path: '/verify-account',
    name: 'Verify Account',
    component: () => import('@/views/auth/VerifyAccount.vue'),
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: false,
      },
    },
  },
  {
    path: '/mfa-verify',
    name: 'MFA Verify',
    component: () => import('@/views/auth/MfaVerify.vue'),
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
    },
  },
  {
    path: '/email-login',
    name: 'Email Login',
    component: () => import('@/views/auth/EmailLogin.vue'),
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
    },
  },
];

export default routes;
