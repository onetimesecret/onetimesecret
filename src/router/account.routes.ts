// src/router/account.routes.ts

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
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings',
    name: 'Account Settings',
    components: {
      default: () => import('@/views/account/AccountSettings.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
    children: [
      {
        path: 'password',
        name: 'Change Password',
        component: () => import('@/views/account/ChangePassword.vue'),
        meta: {
          requiresAuth: true,
        },
      },
      {
        path: 'sessions',
        name: 'Active Sessions',
        component: () => import('@/views/account/ActiveSessions.vue'),
        meta: {
          requiresAuth: true,
        },
      },
      {
        path: 'close',
        name: 'Close Account',
        component: () => import('@/views/account/CloseAccount.vue'),
        meta: {
          requiresAuth: true,
        },
      },
    ],
  },
];

export default routes;
