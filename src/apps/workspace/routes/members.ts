// src/apps/workspace/routes/members.ts

/**
 * Routes for organization member management
 */

import ImprovedFooter from '@/shared/components/layout/ImprovedFooter.vue';
import ImprovedHeader from '@/shared/components/layout/ImprovedHeader.vue';
import ImprovedLayout from '@/shared/layouts/ManagementLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/org/:extid/members',
    name: 'OrganizationMembers',
    components: {
      default: () => import('@/apps/workspace/members/MembersList.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.organizations.members.title',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
      },
    },
    props: true,
  },
];

export default routes;
