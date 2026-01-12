// src/apps/secret/routes/index.ts

import type { RouteRecordRaw } from 'vue-router';

import incomingRoutes from './incoming';
import receiptRoutes from './receipt';
import secretRoutes from './secret';

const routes: RouteRecordRaw[] = [
  ...receiptRoutes,
  ...secretRoutes,
  ...incomingRoutes,
];

export default routes;
