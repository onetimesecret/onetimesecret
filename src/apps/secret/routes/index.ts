// src/apps/secret/routes/index.ts

import type { RouteRecordRaw } from 'vue-router';

import incomingRoutes from './incoming';
import metadataRoutes from './metadata';
import secretRoutes from './secret';

const routes: RouteRecordRaw[] = [
  ...metadataRoutes,
  ...secretRoutes,
  ...incomingRoutes,
];

export default routes;
