// src/router/colonel.routes.ts

import ColonelLayout from '@/layouts/ColonelLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const defaultMeta = {
  requiresAuth: true,
  layout: ColonelLayout,
  layoutProps: {
    displayPoweredBy: true,
    displayToggles: true,
    displayFeedback: false,
    colonel: true,
  },
};

const routes: Array<RouteRecordRaw> = [
  {
    path: '/colonel',
    name: 'Colonel',
    component: () => import('@/views/colonel/ColonelIndex.vue'),
    meta: defaultMeta,
    props: true,
  },
  {
    path: '/colonel/users',
    name: 'ColonelUsers',
    component: () => import('@/views/colonel/ColonelUsers.vue'),
    meta: defaultMeta,
    props: true,
  },
  {
    path: '/colonel/settings',
    name: 'SystemSettings',
    component: () => import('@/views/colonel/SystemSettings.vue'),
    meta: defaultMeta,
    props: true,
  },
  {
    path: '/colonel/info',
    name: 'ColonelInfo',
    component: () => import('@/views/colonel/ColonelInfo.vue'),
    meta: defaultMeta,
    props: true,
  },
];

export default routes;
