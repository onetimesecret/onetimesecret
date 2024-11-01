import { fetchInitialSecret } from '@/api/secrets';
import { AsyncDataResult, SecretDataApiResponse } from '@/types/onetime';
import ShowSecret from '@/views/secrets/ShowSecret.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [

  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    components: {
      default: ShowSecret,
    },
    props: true,
    meta: {

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
