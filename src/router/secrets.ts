import { AsyncDataResult, fetchInitialSecret } from '@/api/secrets'
import QuietLayout from '@/layouts/QuietLayout.vue'
import { SecretDataApiResponse } from '@/types/onetime'
import DashboardIndex from '@/views/dashboard/DashboardIndex.vue'
import DashboardRecent from '@/views/dashboard/DashboardRecent.vue'
import BurnSecret from '@/views/secrets/BurnSecret.vue'
import IncomingSupportSecret from '@/views/secrets/IncomingSupportSecret.vue'
import ShowMetadata from '@/views/secrets/ShowMetadata.vue'
import ShowSecret from '@/views/secrets/ShowSecret.vue'
import { RouteRecordRaw } from 'vue-router'

const routes: Array<RouteRecordRaw> = [

  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    component: ShowSecret,
    //component: () => import('@/views/secrets/ShowSecret.vue'),
    props: true,
    meta: {
      layout: QuietLayout,
      layoutProps: {
        displayMasthead: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: false,
        displayPoweredBy: true,
        noCache: true,
      },
    },
    beforeEnter: async (to, from, next) => {
      try {
        const secretKey = to.params.secretKey as string;
        const initialData: AsyncDataResult<SecretDataApiResponse> = await fetchInitialSecret(secretKey);
        to.meta.initialData = initialData;
        next();
      } catch (error) {
        console.error('Error fetching initial page data:', error);
        next(new Error('Failed to fetch initial page data'));
      }
    },
  },
  {
    path: '/private/:metadataKey',
    name: 'Metadata link',
    component: ShowMetadata,
    props: true,
    meta: {
      layoutProps: {
        displayFeedback: false,
        noCache: true,
      }
    },
  },
  {
    path: '/private/:metadataKey/burn',
    name: 'Burn secret',
    component: BurnSecret,
    props: true,
    meta: {
      layoutProps: {
        displayFeedback: false,
      }
    }
  },
  {
    path: '/dashboard',
    name: 'Dashboard',
    component: DashboardIndex,
    meta: { requiresAuth: true }
  },
  {
    path: '/recent',
    name: 'Recents',
    component: DashboardRecent,
    meta: { requiresAuth: true }
  },
  {
    path: '/incoming',
    name: 'Inbound Secrets',
    component: IncomingSupportSecret,
    meta: { requiresAuth: false }
  },

]

export default routes;
