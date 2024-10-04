import Homepage from '@/views/Homepage.vue';
import IncomingSupportSecret from '@/views/secrets/IncomingSupportSecret.vue';
import { useWindowProp } from '@/composables/useWindowProps';
import { RouteRecordRaw } from 'vue-router';
import DefaultLayout from '@/layouts/DefaultLayout.vue';

const authState = useWindowProp('authenticated');

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
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      }
    },
  },

  {
    path: '/incoming',
    name: 'Inbound Secrets',
    component: IncomingSupportSecret,
    meta: {
      layout: DefaultLayout,
    },
  },

  {
    path: '/info/privacy',
    name: 'Privacy Policy',
    component: () => import('@/views/info/PrivacyDoc.vue'),
    meta: {
      layout: DefaultLayout,
    },
  },
  {
    path: '/info/terms',
    name: 'Terms of Use',
    component: () => import('@/views/info/TermsDoc.vue'),
    meta: {
      layout: DefaultLayout,
    },
  },
  {
    path: '/info/security',
    name: 'Security Policy',
    component: () => import('@/views/info/SecurityDoc.vue'),
    meta: {
      layout: DefaultLayout,
    },
  },

  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/views/Feedback.vue'),
    meta: {
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
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      },
    },
  },

]

export default routes;
