import { AsyncDataResult, fetchInitialSecret } from '@/api/secrets'
import { SecretDataApiResponse } from '@/types/onetime'
import DashboardIndex from '@/views/dashboard/DashboardIndex.vue'
import DashboardRecent from '@/views/dashboard/DashboardRecent.vue'
import BurnSecret from '@/views/secrets/BurnSecret.vue'
import ShowMetadata from '@/views/secrets/ShowMetadata.vue'
import ShowSecret from '@/views/secrets/ShowSecret.vue'
import { RouteRecordRaw } from 'vue-router'
import DefaultHeader from '@/components/layout/DefaultHeader.vue'
import DefaultFooter from '@/components/layout/DefaultFooter.vue'

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
        displayFeedback: false,
        displayVersion: false,
      },
    },
  },
  {
    path: '/recent',
    name: 'Recents',
    component: DashboardRecent,
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
  },

  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    components: {
      default: ShowSecret,
      //header: DefaultHeader,
      //footer: DefaultFooter,
    },
    props: true,
    meta: {
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
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
        noCache: true,
        displayMasthead: false,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
  },
  {
    path: '/private/:metadataKey/burn',
    name: 'Burn secret',
    component: BurnSecret,
    props: true,
    meta: {
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
      },
    }
  },

]

export default routes;
