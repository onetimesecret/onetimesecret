import Homepage from '@/views/Homepage.vue';
import IncomingSupportSecret from '@/views/secrets/IncomingSupportSecret.vue';
import { ref } from 'vue';
import { RouteRecordRaw } from 'vue-router';

const authState = ref(window.authenticated);

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
    path: '/incoming',
    name: 'Inbound Secrets',
    component: IncomingSupportSecret,
    meta: {
      requiresAuth: false
    },
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
    path: '/about',
    name: 'About',
    component: () => import('@/views/About.vue'),
  },

  {
    path: '/translations',
    name: 'Translations',
    component: () => import('@/views/Translations.vue'),
  },

]

export default routes;
