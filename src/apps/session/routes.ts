// src/apps/session/routes.ts

/* src/router/auth.routes.ts */
import AuthLayout from '@/apps/session/layouts/AuthLayout.vue';
import MinimalLayout from '@/shared/layouts/MinimalLayout.vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/signin',
    name: 'Sign In',
    component: () => import('@/apps/session/views/Login.vue'),
    meta: {
      title: 'web.TITLES.signin',
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signin',
      layout: AuthLayout,
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
        component: () => import('@/apps/session/views/Register.vue'),
        meta: {
          title: 'web.TITLES.signup',
        },
      },
      {
        path: ':planCode',
        name: 'Sign Up with Plan',
        component: () => import('@/apps/session/views/Register.vue'),
        props: true,
        meta: {
          title: 'web.TITLES.signup',
        },
      },
    ],
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signup',
      layout: AuthLayout,
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
    name: 'Forgot Password',
    component: () => import('@/apps/session/views/PasswordResetRequest.vue'),
    meta: {
      title: 'web.TITLES.forgot_password',
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signin',
      layout: AuthLayout,
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
    path: '/logout',
    name: 'Logout',
    component: { render: () => null }, // Dummy component
    meta: {
      title: 'web.TITLES.logout',
      requiresAuth: true,
      layout: MinimalLayout,
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
    component: () => import('@/apps/session/views/VerifyAccount.vue'),
    meta: {
      title: 'web.TITLES.verify_account',
      requiresAuth: false,
      isAuthRoute: true,
      layout: AuthLayout,
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
    component: () => import('@/apps/session/views/MfaChallenge.vue'),
    meta: {
      title: 'web.TITLES.mfa_verify',
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signin',
      layout: AuthLayout,
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
    component: () => import('@/apps/session/views/EmailLogin.vue'),
    meta: {
      title: 'web.TITLES.email_login',
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signin',
      layout: AuthLayout,
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
    path: '/reset-password',
    name: 'Reset Password (Rodauth)',
    component: () => import('@/apps/session/views/PasswordReset.vue'),
    props: (route) => ({ resetKey: route.query.key }),
    meta: {
      title: 'web.TITLES.reset_password',
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signin',
      layout: AuthLayout,
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
    path: '/invite/:token',
    name: 'Accept Invitation',
    component: () => import('@/apps/session/views/AcceptInvite.vue'),
    meta: {
      title: 'web.TITLES.accept_invitation',
      requiresAuth: false,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: true,
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
