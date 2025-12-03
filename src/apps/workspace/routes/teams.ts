// src/apps/workspace/routes/teams.ts

import {
  ImprovedFooter,
  ImprovedHeader,
  ImprovedLayout,
  standardLayoutProps,
} from '@/router/layout.config';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/teams',
    name: 'Teams',
    components: {
      default: () => import('@/apps/workspace/teams/TeamsHub.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.teams',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/teams/:extid',
    name: 'Team View',
    components: {
      default: () => import('@/apps/workspace/teams/TeamView.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.team_dashboard',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/teams/:extid/members',
    name: 'Team Members',
    components: {
      default: () => import('@/apps/workspace/teams/TeamMembers.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.team_members',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/teams/:extid/settings',
    name: 'Team Settings',
    components: {
      default: () => import('@/apps/workspace/teams/TeamSettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.team_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
];

export default routes;
