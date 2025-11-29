// src/router/teams.routes.ts

import {
  ImprovedFooter,
  ImprovedHeader,
  ImprovedLayout,
  standardLayoutProps,
} from './layout.config';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/teams',
    name: 'Teams',
    components: {
      default: () => import('@/views/teams/TeamsHub.vue'),
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
    name: 'Team Dashboard',
    components: {
      default: () => import('@/views/teams/TeamDashboard.vue'),
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
      default: () => import('@/views/teams/TeamMembers.vue'),
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
      default: () => import('@/views/teams/TeamSettings.vue'),
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
