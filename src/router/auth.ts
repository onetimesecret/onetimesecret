import DefaultLayout from '@/layouts/DefaultLayout.vue';
import QuietLayout from '@/layouts/QuietLayout.vue';
import { useAuthStore } from '@/stores/authStore';
import { useCsrfStore } from '@/stores/csrfStore';
import { useLanguageStore } from '@/stores/languageStore';
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
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: true,
        displayVersion: true,
        displayToggles: true,
      },
    },
    beforeEnter: (to, from, next) => {
      const authStore = useAuthStore();
      if (authStore.isAuthenticated) {
        // Redirect to home page or dashboard if already signed in
        next({ name: 'Home' }); // Replace 'Home' with your desired route name
      } else {
        next();
      }
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
        displayNavigation: false,
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
    beforeEnter: () => {
      const authStore = useAuthStore()
      authStore.logout()

      // Clear all local storage
      localStorage.clear()

      // Reset stores
      const languageStore = useLanguageStore()
      const csrfStore = useCsrfStore()

      languageStore.$reset()
      csrfStore.$reset()

      // Redirect to logout URL
      window.location.href = '/logout'
    }
  },
]

export default routes;
