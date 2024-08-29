import { createRouter, createWebHistory, RouteRecordRaw } from 'vue-router'
import AccountDomainAdd from '@/views/account/AccountDomainAdd.vue'
import AccountDomains from  '@/views/account/AccountDomains.vue'
import Homepage from '@/views/Homepage.vue'

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account/domains/add',
    name: 'AccountDomainAdd',
    component: AccountDomainAdd,
  },
  {
    path: '/account/domains/:domain/verify',
    name: 'AccountDomainVerify',
    component: () => import('@/views/account/AccountDomainVerify.vue'),
    props: true,
  },
  {
    path: '/account/domains',
    name: 'AccountDomains',
    component: AccountDomains,
  },
  {
    path: '/pricing',
    name: 'Pricing',
    component: () => import('@/views/PricingDual.vue'),
  },
  {
    path: '/',
    name: 'Dashboard',
    component: () => import('@/views/Dashboard.vue'),
  },
  {
    path: '/',
    name: 'Homepage',
    component: Homepage,
  },

]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
