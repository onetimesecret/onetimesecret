// src/router/colonel.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import { RouteRecordRaw } from 'vue-router';

const defaultMeta = {
  requiresAuth: true,
  layoutProps: {
    displayPoweredBy: false,
    colonel: true,
  },
};

const routes: Array<RouteRecordRaw> = [
  {
    path: '/colonel',
    name: 'Colonel',
    components: {
      default: () => import('@/views/colonel/ColonelIndex.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: defaultMeta,
    props: true,
  },
  {
    path: '/colonel/settings',
    name: 'ColonelSettings',
    components: {
      default: () => import('@/views/colonel/ColonelSettings.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: defaultMeta,
    props: true,
  },
  {
    path: '/colonel/info',
    name: 'ColonelInfo',
    components: {
      default: () => import('@/views/colonel/ColonelInfo.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: defaultMeta,
    props: true,
  },
];

export default routes;
