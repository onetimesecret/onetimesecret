// src/router/incoming.routes.ts

import type { RouteRecordRaw } from 'vue-router';

const incomingRoutes: RouteRecordRaw[] = [
  {
    path: '/incoming',
    name: 'IncomingSecretForm',
    component: () => import('@/views/incoming/IncomingSecretForm.vue'),
    meta: {
      requiresAuth: false,
      title: 'Create Incoming Secret',
    },
  },
  {
    path: '/incoming/success/:metadataKey',
    name: 'IncomingSuccess',
    component: () => import('@/views/incoming/IncomingSuccessView.vue'),
    meta: {
      requiresAuth: false,
      title: 'Secret Created Successfully',
    },
  },
];

export default incomingRoutes;
