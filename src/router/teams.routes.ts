// src/router/teams.routes.ts

import ExpandedFooter from '@/components/layout/ExpandedFooter.vue';
import ExpandedHeader from '@/components/layout/ExpandedHeader.vue';
import AccountLayout from '@/layouts/AccountLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/teams',
    name: 'Teams',
    components: {
      default: () => import('@/views/teams/TeamsHub.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.teams',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/teams/:teamid',
    name: 'Team Dashboard',
    components: {
      default: () => import('@/views/teams/TeamDashboard.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.team_dashboard',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/teams/:teamid/members',
    name: 'Team Members',
    components: {
      default: () => import('@/views/teams/TeamMembers.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.team_members',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/teams/:teamid/settings',
    name: 'Team Settings',
    components: {
      default: () => import('@/views/teams/TeamSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.team_settings',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
];

export default routes;
