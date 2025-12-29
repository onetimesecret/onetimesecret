// src/apps/workspace/routes/members.ts

/**
 * Routes for organization member management
 */

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/org/:extid/members',
    name: 'OrganizationMembers',
    component: () => import('@/apps/workspace/members/MembersList.vue'),
    meta: {
      title: 'web.organizations.members.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: false,
        displayPoweredBy: false,
        displayVersion: true,
      },
    },
    props: true,
  },
];

export default routes;
