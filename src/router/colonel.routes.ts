// src/router/colonel.routes.ts

import ColonelLayout from '@/shared/layouts/AdminLayout.vue';
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
    component: () => import('@/apps/kernel/views/ColonelIndex.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel',
    },
    props: true,
  },
  {
    path: '/colonel/users',
    name: 'ColonelUsers',
    component: () => import('@/apps/kernel/views/ColonelUsers.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_users',
    },
    props: true,
  },
  {
    path: '/colonel/system',
    name: 'ColonelSystem',
    component: () => import('@/apps/kernel/views/ColonelSystem.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_system',
    },
    props: true,
  },
  {
    path: '/colonel/settings',
    name: 'SystemSettings',
    component: () => import('@/apps/kernel/views/SystemSettings.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.system_settings',
    },
    props: true,
  },
  {
    path: '/colonel/secrets',
    name: 'ColonelSecrets',
    component: () => import('@/apps/kernel/views/ColonelSecrets.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_secrets',
    },
    props: true,
  },
  {
    path: '/colonel/domains',
    name: 'ColonelDomains',
    component: () => import('@/apps/kernel/views/ColonelDomains.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_domains',
    },
    props: true,
  },
  {
    path: '/colonel/database/maindb',
    name: 'ColonelSystemMainDB',
    component: () => import('@/apps/kernel/views/ColonelSystemMainDB.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_maindb',
    },
    props: true,
  },
  {
    path: '/colonel/database/authdb',
    name: 'ColonelSystemAuthDB',
    component: () => import('@/apps/kernel/views/ColonelSystemAuthDB.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_authdb',
    },
    props: true,
  },
  {
    path: '/colonel/system/redis',
    name: 'ColonelSystemRedis',
    component: () => import('@/apps/kernel/views/ColonelSystemRedis.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_redis',
    },
    props: true,
  },
  {
    path: '/colonel/banned-ips',
    name: 'ColonelBannedIPs',
    component: () => import('@/apps/kernel/views/ColonelBannedIPs.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_banned_ips',
    },
    props: true,
  },
  {
    path: '/colonel/usage',
    name: 'ColonelUsageExport',
    component: () => import('@/apps/kernel/views/ColonelUsageExport.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.TITLES.colonel_usage',
    },
    props: true,
  },
];

export default routes;
