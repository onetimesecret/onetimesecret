import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account',
    name: 'Account',
    components: {
      default: () => import('@/views/account/AccountIndex.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      displayPoweredBy: false,
    },
  },
  {
    path: '/colonel',
    name: 'Colonel',
    components: {
      default: () => import('@/views/colonel/ColonelIndex.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      isAdmin: true,
      requiresAuth: true,
      displayPoweredBy: false,
    },
    props: true,
  },
];

export default routes;
