import { createRouter, createWebHistory, RouteRecordRaw } from 'vue-router'
import AccountDomainAdd from '@/views/account/AccountDomainAdd.vue'
import AccountDomainVerify from '@/views/account/AccountDomainVerify.vue'

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account/domains/add',
    name: 'AccountDomainAdd',
    component: AccountDomainAdd,
  },
  {
    path: '/account/domains/:domain/verify',
    name: 'AccountDomainVerify',
    component: AccountDomainVerify,
  },

]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
