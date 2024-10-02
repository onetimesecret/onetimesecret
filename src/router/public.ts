
import Homepage from '@/views/Homepage.vue'
import { RouteRecordRaw } from 'vue-router'
import { ref } from 'vue'

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
