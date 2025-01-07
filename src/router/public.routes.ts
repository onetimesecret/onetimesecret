import DefaultLayout from '@/layouts/DefaultLayout.vue';
import Homepage from '@/views/Homepage.vue';
import IncomingSupportSecret from '@/views/secrets/IncomingSupportSecret.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/',
    name: 'Home',
    component: Homepage,
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      },
    },
  },

  {
    path: '/incoming',
    name: 'Inbound Secrets',
    component: IncomingSupportSecret,
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },

  {
    path: '/info/privacy',
    name: 'Privacy Policy',
    component: () => import('@/views/info/PrivacyDoc.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },
  {
    path: '/info/terms',
    name: 'Terms of Use',
    component: () => import('@/views/info/TermsDoc.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },
  {
    path: '/info/security',
    name: 'Security Policy',
    component: () => import('@/views/info/SecurityDoc.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },

  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/views/Feedback.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: false,
      },
    },
  },

  {
    path: '/about',
    name: 'About',
    component: () => import('@/views/About.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      },
    },
  },

  {
    path: '/translations',
    name: 'Translations',
    component: () => import('@/views/Translations.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      },
    },
  },
];

export default routes;
