// src/apps/workspace/routes/index.ts

import type { RouteRecordRaw } from 'vue-router';

import accountRoutes from './account';
import billingRoutes from './billing';
import dashboardRoutes from './dashboard';

const routes: RouteRecordRaw[] = [
  ...dashboardRoutes,
  ...accountRoutes,
  ...billingRoutes,
];

export default routes;
