import DefaultLayout from '@/layouts/DefaultLayout.vue'
import { RouteRecordRaw } from 'vue-router'

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account/domains/:domain/verify',
    name: 'AccountDomainVerify',
    component: () => import('@/views/account/AccountDomainVerify.vue'),
    meta: {
      requiresAuth: true,
      layout: DefaultLayout,
    },
    props: true,
  },
  {
    path: '/account/domains/add',
    name: 'AccountDomainAdd',
    component: () => import('@/views/account/AccountDomainAdd.vue'),
    meta: {
      requiresAuth: true,
      layout: DefaultLayout,
      layoutProps: {
        displayFeedback: false,
      }
    },
    props: true,
  },
  {
    path: '/account/domains',
    name: 'AccountDomains',
    component: () => import('@/views/account/AccountDomains.vue'),
    meta: {
      requiresAuth: true,
      layout: DefaultLayout,
    },
    props: true,
  },
  {
    path: '/account/domains/:id/brand',
    name: 'DomainBrandSettings',
    component: () => import('@/views/account/DomainBrandSettings.vue'),
    meta: {
      requiresAuth: true,
      layout: DefaultLayout,
    },
    props: true,
  },
  {
    path: '/account',
    name: 'Account',
    component: () => import('@/views/account/AccountIndex.vue'),
    meta: {
      requiresAuth: true,
      layout: DefaultLayout,
    },
  },
  {
    path: '/colonel',
    name: 'Colonel',
    component: () => import('@/views/colonel/ColonelIndex.vue'),
    meta: {
      isAdmin: true,
      requiresAuth: true,
      layout: DefaultLayout,
    },
    props: true,
  },
]

export default routes;
