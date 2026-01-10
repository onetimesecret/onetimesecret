// src/apps/colonel/routes.ts

import ColonelLayout from '@/apps/colonel/layouts/ColonelLayout.vue';
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
    component: () => import('@/apps/colonel/views/ColonelIndex.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.index',
    },
    props: true,
  },
  {
    path: '/colonel/users',
    name: 'ColonelUsers',
    component: () => import('@/apps/colonel/views/ColonelUsers.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.users',
    },
    props: true,
  },
  {
    path: '/colonel/system',
    name: 'ColonelSystem',
    component: () => import('@/apps/colonel/views/ColonelSystem.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.system',
    },
    props: true,
  },
  {
    path: '/colonel/settings',
    name: 'SystemSettings',
    component: () => import('@/apps/colonel/views/SystemSettings.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.system_settings',
    },
    props: true,
  },
  {
    path: '/colonel/secrets',
    name: 'ColonelSecrets',
    component: () => import('@/apps/colonel/views/ColonelSecrets.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.secrets',
    },
    props: true,
  },
  {
    path: '/colonel/domains',
    name: 'ColonelDomains',
    component: () => import('@/apps/colonel/views/ColonelDomains.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.domains',
    },
    props: true,
  },
  {
    path: '/colonel/organizations',
    name: 'ColonelOrganizations',
    component: () => import('@/apps/colonel/views/ColonelOrganizations.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.organizations',
    },
    props: true,
  },
  {
    path: '/colonel/database/maindb',
    name: 'ColonelSystemMainDB',
    component: () => import('@/apps/colonel/views/ColonelSystemMainDB.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.maindb',
    },
    props: true,
  },
  {
    path: '/colonel/database/authdb',
    name: 'ColonelSystemAuthDB',
    component: () => import('@/apps/colonel/views/ColonelSystemAuthDB.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.authdb',
    },
    props: true,
  },
  {
    path: '/colonel/system/redis',
    name: 'ColonelSystemRedis',
    component: () => import('@/apps/colonel/views/ColonelSystemRedis.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.redis',
    },
    props: true,
  },
  {
    path: '/colonel/banned-ips',
    name: 'ColonelBannedIPs',
    component: () => import('@/apps/colonel/views/ColonelBannedIPs.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.bannedIps',
    },
    props: true,
  },
  {
    path: '/colonel/usage',
    name: 'ColonelUsageExport',
    component: () => import('@/apps/colonel/views/ColonelUsageExport.vue'),
    meta: {
      ...defaultMeta,
      title: 'web.colonel.titles.usage',
    },
    props: true,
  },
];

export default routes;
