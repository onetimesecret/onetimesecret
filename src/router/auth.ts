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
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: false,
        displayFeedback: true,
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
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: false,
        displayFeedback: true,
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
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayLinks: false,
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
      layoutProps: {}
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
    }
  },
]

export default routes;
