// src/apps/admin/routes.ts

import AdminLayout from '@/apps/admin/layouts/AdminLayout.vue';
import { RouteRecordRaw } from 'vue-router';

// Shared meta for every admin route (including the router's catch-all). The
// console lives at the /colonel URL (decision D1) and, since the cutover, is the
// sole admin frontend served there — the backend serves this isolated admin
// bundle unconditionally (docs/specs/colonel-ui/50-cutover-hardening.md).
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
    // Secrets: lookup-by-key inspect + guarded delete (ticket #30; browse-all
    // table removed by design review — no browsing secrets on a zero-knowledge
    // platform). No route params (the key is an in-page input).
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
  {
    // Sessions console: paginated list + search + inspect drawer + guarded revoke (ticket #40).
    path: '/colonel/sessions',
    name: 'AdminSessions',
    component: () => import('@/apps/admin/views/AdminSessions.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.sessions.title',
      sentryScrubParams: false,
    },
  },
  {
    // Audit log reader (observability): newest-first playback of the
    // AdminAuditEvent trail every mutating admin op writes. Read-only; no
    // route params (filters are in-page).
    path: '/colonel/audit',
    name: 'AdminAuditLog',
    component: () => import('@/apps/admin/views/AdminAuditLog.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.audit.title',
      sentryScrubParams: false,
    },
  },
  {
    // Broadcast banner: settings-style get/set/clear (ticket #41).
    path: '/colonel/banner',
    name: 'AdminBanner',
    component: () => import('@/apps/admin/views/AdminBanner.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.banner.title',
      sentryScrubParams: false,
    },
  },
  {
    // Domain toolbox: orphaned scan + probe + guarded repair/transfer (ticket #43).
    path: '/colonel/domain-toolbox',
    name: 'AdminDomainToolbox',
    component: () => import('@/apps/admin/views/AdminDomainToolbox.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.domaintoolbox.title',
      sentryScrubParams: false,
    },
  },
  {
    // Email tools (ticket #44): template preview / test send. No route params
    // (all inputs are in-page).
    path: '/colonel/email-tools',
    name: 'AdminEmailTools',
    component: () => import('@/apps/admin/views/AdminEmailTools.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.emailtools.title',
      sentryScrubParams: false,
    },
  },
  {
    // Billing catalog / plan-drift read-out (ticket #45). No params.
    path: '/colonel/billing',
    name: 'AdminBilling',
    component: () => import('@/apps/admin/views/AdminBilling.vue'),
    meta: {
      ...adminDefaultMeta,
      title: 'web.admin.billing.title',
      sentryScrubParams: false,
    },
  },
];

export default routes;
