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
  {
    // Customers list (ticket #22). No params, so scrubbing is irrelevant.
    path: '/colonel/customers',
    name: 'AdminCustomers',
    component: () => import('@/apps/admin/views/AdminCustomers.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.customers.title',
      sentryScrubParams: false,
    },
  },
  {
    // Customer detail (ticket #22). `:id` is the customer's PUBLIC id (extid).
    // `sentryScrubParams` is OMITTED so the default (scrub all params) redacts
    // the id from breadcrumbs.
    path: '/colonel/customers/:id',
    name: 'AdminCustomerDetail',
    component: () => import('@/apps/admin/views/AdminCustomerDetail.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.customers.title',
    },
    props: true,
  },
  {
    // Secrets: paginated list + receipt drawer + guarded delete (ticket #30).
    // No route params (the receipt opens in a DetailDrawer, not a sub-route).
    path: '/colonel/secrets',
    name: 'AdminSecrets',
    component: () => import('@/apps/admin/views/AdminSecrets.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.secrets.title',
      sentryScrubParams: false,
    },
  },
  {
    // Domains list (ticket #31): card grid + per-domain verify. No params.
    path: '/colonel/domains',
    name: 'AdminDomains',
    component: () => import('@/apps/admin/views/AdminDomains.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.colonel.titles.domains',
      sentryScrubParams: false,
    },
  },
  {
    // Organizations list + billing-investigate + entitlement overrides (ticket #32).
    path: '/colonel/organizations',
    name: 'AdminOrganizations',
    component: () => import('@/apps/admin/views/AdminOrganizations.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.colonel.titles.organizations',
      sentryScrubParams: false,
    },
  },
  {
    // System monitoring read-out: db / redis / queue metrics (ticket #33).
    path: '/colonel/system',
    name: 'AdminSystem',
    component: () => import('@/apps/admin/views/AdminSystem.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.system.title',
      sentryScrubParams: false,
    },
  },
  {
    // Banned IPs: bounded list + guarded ban / unban (ticket #33).
    path: '/colonel/banned-ips',
    name: 'AdminBannedIps',
    component: () => import('@/apps/admin/views/AdminBannedIps.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.bannedIps.title',
      sentryScrubParams: false,
    },
  },
  {
    // Usage export read-out (ticket #33).
    path: '/colonel/usage',
    name: 'AdminUsage',
    component: () => import('@/apps/admin/views/AdminUsage.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.usage.title',
      sentryScrubParams: false,
    },
  },
];

export default routes;
