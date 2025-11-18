// src/router/mockup.routes.ts

import type { RouteRecordRaw } from 'vue-router';

const mockupRoutes: RouteRecordRaw[] = [
  {
    path: '/mockups/redesign',
    name: 'RedesignMockups',
    component: () => import('@/views/mockups/RedesignMockupIndex.vue'),
    meta: {
      requiresAuth: false,
      title: 'Design Mockups - Create Secret Redesign',
    },
  },
];

export default mockupRoutes;
