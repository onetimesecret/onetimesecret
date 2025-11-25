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
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel',
    },
    props: true,
  },
  {
    path: '/colonel/users',
    name: 'ColonelUsers',
    component: () => import('@/views/colonel/ColonelUsers.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_users',
    },
    props: true,
  },
  {
    path: '/colonel/settings',
    name: 'SystemSettings',
    component: () => import('@/views/colonel/SystemSettings.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.system_settings',
    },
    props: true,
  },
  {
    path: '/colonel/secrets',
    name: 'ColonelSecrets',
    component: () => import('@/views/colonel/ColonelSecrets.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_secrets',
    },
    props: true,
  },
  {
    path: '/colonel/domains',
    name: 'ColonelDomains',
    component: () => import('@/views/colonel/ColonelDomains.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_domains',
    },
    props: true,
  },
  {
    path: '/colonel/database/maindb',
    name: 'ColonelSystemMainDB',
    component: () => import('@/views/colonel/ColonelSystemMainDB.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_maindb',
    },
    props: true,
  },
  {
    path: '/colonel/database/authdb',
    name: 'ColonelSystemAuthDB',
    component: () => import('@/views/colonel/ColonelSystemAuthDB.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_authdb',
    },
    props: true,
  },
  {
    path: '/colonel/system/redis',
    name: 'ColonelSystemRedis',
    component: () => import('@/views/colonel/ColonelSystemRedis.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_redis',
    },
    props: true,
  },
  {
    path: '/colonel/banned-ips',
    name: 'ColonelBannedIPs',
    component: () => import('@/views/colonel/ColonelBannedIPs.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_banned_ips',
    },
    props: true,
  },
  {
    path: '/colonel/usage',
    name: 'ColonelUsageExport',
    component: () => import('@/views/colonel/ColonelUsageExport.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_usage',
    },
    props: true,
  },
];

export default routes;
