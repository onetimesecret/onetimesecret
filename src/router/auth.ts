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
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: false,
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
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: false,
      },
    },
  },
  {
    path: '/forgot',
    name: 'Forgot',
    component: () => import('@/views/auth/PasswordReset.vue'),
    meta: {
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: true,
        displayVersion: false,
      }
    },
  },
  {
    path: '/logout',
    name: 'Logout',
    component: { render: () => null }, // Dummy component
    meta: {
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
