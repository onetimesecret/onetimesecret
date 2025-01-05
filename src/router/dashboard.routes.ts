import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import { AsyncDataResult, CustomDomainResponse } from '@/schemas/api/responses';
import api from '@/utils/api';
import DashboardIndex from '@/views/dashboard/DashboardIndex.vue';
import DashboardRecent from '@/views/dashboard/DashboardRecent.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/dashboard',
    name: 'Dashboard',
    components: {
      default: DashboardIndex,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: true,
        displayFeedback: true,
        displayVersion: true,
      },
    },
  },
  {
    path: '/recent',
    name: 'Recents',
    components: {
      default: DashboardRecent,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: true,
        displayFeedback: true,
        displayVersion: true,
      },
    },
  },
  {
    path: '/domains/add',
    name: 'AccountDomainAdd',
    components: {
      default: () => import('@/views/account/AccountDomainAdd.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayFeedback: false,
      },
    },
    props: true,
  },
  {
    path: '/domains',
    name: 'DashboardDomains',
    components: {
      default: () => import('@/views/dashboard/DashboardDomains.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
    },
    props: true,
  },
  {
    path: '/domains/:domain/verify',
    name: 'AccountDomainVerify',
    components: {
      default: () => import('@/views/account/AccountDomainVerify.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
    },
    props: true,
  },
  {
    path: '/domains/:domain/brand',
    name: 'AccountDomainBrand',
    components: {
      default: () => import('@/views/account/AccountDomainBrand.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
    },
    props: true,
    beforeEnter: async (to, from, next) => {
      try {
        const domain = to.params.domain as string;
        const response = await api.get<CustomDomainResponse>(
          `/api/v2/account/domains/${domain}/brand`
        );

        const initialData: AsyncDataResult<CustomDomainResponse> = {
          status: response.status,
          data: response.data,
          error: null,
        };

        to.meta.initialData = initialData; // Could fix this by adding a AccountInitialData type
        next();
      } catch (error) {
        console.error('Error fetching domain brand data:', error);
        const initialData: AsyncDataResult<CustomDomainResponse> = {
          status: 500,
          data: null,
          error:
            error instanceof Error ? error.message : 'Failed to fetch domain brand data',
        };

        to.meta.initialData = initialData;
        next();
      }
    },
  },
];

export default routes;
