import { fetchInitialSecret } from '@/api/secrets';
import QuietLayout from '@/layouts/QuietLayout.vue';
import { SecretDataApiResponse } from '@/types/onetime';
import ShowSecret from '@/views/secrets/ShowSecret.vue';
import { RouteRecordRaw } from 'vue-router';
import { AsyncDataResult } from '@/types/onetime'

const routes: Array<RouteRecordRaw> = [


  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    components: {
      default: ShowSecret,
    },
    props: true,
    meta: {
      layout: QuietLayout,
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
]

export default routes;
