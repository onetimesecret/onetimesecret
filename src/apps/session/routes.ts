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
      sentryScrubParams: false,
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
          sentryScrubParams: false,
        },
      },
      {
        path: ':planCode',
        name: 'Sign Up with Plan',
        component: () => import('@/apps/session/views/Register.vue'),
        props: true,
        meta: {
          title: 'web.TITLES.signup',
          sentryScrubParams: false,
        },
      },
    ],
    meta: {
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signup',
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
      },
      sentryScrubParams: false,
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
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
      sentryScrubParams: false,
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
      sentryScrubParams: false,
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
  // Post-signup confirmation page ("Check your email"). Intentionally ungated:
  // it is reached immediately after account creation and is purely informational
  // (echoes the address, offers resend), so it must render regardless of the
  // signin/signup feature toggles.
  {
    path: '/check-email',
    name: 'Check Email',
    component: () => import('@/apps/session/views/CheckEmail.vue'),
    meta: {
      title: 'web.TITLES.check_email',
      requiresAuth: false,
      isAuthRoute: true,
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
      sentryScrubParams: false,
    },
  },
  // Intentionally ungated: account verification must work regardless of
  // signin/signup feature toggles since the flow starts from an email link.
  {
    path: '/verify-account',
    name: 'Verify Account',
    component: () => import('@/apps/session/views/VerifyAccount.vue'),
    meta: {
      title: 'web.TITLES.verify_account',
      requiresAuth: false,
      isAuthRoute: true,
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: false,
      },
      sentryScrubParams: false,
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
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
      sentryScrubParams: false,
    },
  },
  // Sign-in interstitial (SSO password-challenge linking — #3840 Phase 3).
  // Reached UNAUTHENTICATED via a backend redirect after an SSO sign-in whose
  // IdP email matched an existing password-holding account. The single-use
  // challenge token rides in the path (`:token`). Meta mirrors /mfa-verify
  // (another post-credential, pre-fully-authenticated interstitial), EXCEPT the
  // token is sensitive: sentryScrubParams: ['token'] redacts it from diagnostics
  // (mfa-verify has no path param, so it opts out with `false`).
  {
    path: '/link-sso/:token',
    name: 'Link SSO',
    component: () => import('@/apps/session/views/LinkSso.vue'),
    meta: {
      title: 'web.link_sso.title',
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signin',
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
      sentryScrubParams: ['token'],
    },
  },
  // Mailbox-proof SSO linking consent page (#3840 Phase 4). Reached
  // UNAUTHENTICATED via an emailed link after an SSO sign-in whose IdP email
  // matched an existing PASSWORDLESS account: the backend emails a single-use
  // token to the on-file address, so opening this link proves mailbox control.
  // The token rides the path (`:token`) and is EMAIL-DELIVERED — sentryScrubParams:
  // ['token'] redacts it from diagnostics. Meta mirrors /link-sso (another
  // post-issuance, pre-fully-authenticated interstitial); the GET is display-only
  // and the mutating confirm is an explicit user action (never auto-POST on load).
  {
    path: '/sso-link-confirm/:token',
    name: 'SSO Link Confirm',
    component: () => import('@/apps/session/views/SsoLinkConfirm.vue'),
    meta: {
      title: 'web.sso_link_confirm.title',
      requiresAuth: false,
      isAuthRoute: true,
      requiresFeature: 'signin',
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
      sentryScrubParams: ['token'],
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
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
      sentryScrubParams: false,
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
      excludeSsoOnly: true,
      layout: AuthLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      },
      sentryScrubParams: false,
    },
  },
  // Intentionally ungated: invitation acceptance must work regardless of
  // signin/signup feature toggles since invitees follow a unique token link.
  // NOTE: /invite/:token uses default sentryScrubParams (scrub all) - token is sensitive
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
