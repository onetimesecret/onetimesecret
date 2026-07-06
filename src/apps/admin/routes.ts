// src/apps/admin/routes.ts

import AdminLayout from '@/apps/admin/layouts/AdminLayout.vue';
import { RouteRecordRaw } from 'vue-router';

// Shared meta for every admin route (including the router's catch-all). The
// console lives at the SAME /colonel URL as the legacy app (decision D1); which
// shell renders is chosen server-side by the `experimental.admin_v2` flag.
// Access control is the backend's role=colonel gate on /colonel plus the API
// 403s — requiresAuth here is defence-in-depth.
export const adminDefaultMeta = {
  requiresAuth: true,
  layout: AdminLayout,
  layoutProps: {
    // AdminLayout owns its own chrome (persistent sidebar); suppress the
    // customer masthead/nav that App.vue defaults on.
    displayMasthead: false,
    displayNavigation: false,
    displayHeader: false,
  },
};

const routes: Array<RouteRecordRaw> = [
  {
    path: '/colonel',
    name: 'AdminOverview',
    component: () => import('@/apps/admin/views/AdminOverview.vue'),
    meta: {
      ...adminDefaultMeta,
      // Reuse the existing colonel title key (no new i18n needed for the
      // Phase-0 skeleton). Real screens add web.admin.* keys in later phases.
      title: 'web.colonel.titles.index',
      sentryScrubParams: false,
    },
    props: true,
  },
];

export default routes;
