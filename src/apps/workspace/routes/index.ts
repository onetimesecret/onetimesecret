// src/apps/workspace/routes/index.ts

import type { RouteRecordRaw } from 'vue-router';

import accountRoutes from './account';
import billingRoutes from './billing';
import dashboardRoutes from './dashboard';
import organizationsRoutes from './organizations';

const routes: RouteRecordRaw[] = [
  ...dashboardRoutes,
  ...accountRoutes,
  ...billingRoutes,
  ...organizationsRoutes,
];

export default routes;
