// src/router/incoming.routes.ts

import type { RouteRecordRaw } from 'vue-router';

const incomingRoutes: RouteRecordRaw[] = [
  {
    path: '/incoming',
    name: 'IncomingSecretForm',
    component: () => import('@/views/incoming/IncomingSecretForm.vue'),
    meta: {
      requiresAuth: false,
      title: 'Send a Secret',
    },
  },
  {
    path: '/incoming/success/:metadataKey',
    name: 'IncomingSuccess',
    component: () => import('@/views/incoming/IncomingSuccessView.vue'),
    meta: {
      requiresAuth: false,
      title: 'Secret Sent Successfully',
    },
  },
];

export default incomingRoutes;
