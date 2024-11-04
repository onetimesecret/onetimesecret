import { fetchInitialSecret } from '@/api/secrets';
import { AsyncDataResult, SecretDataApiResponse } from '@/types/onetime';
import ShowSecretContainer from '@/views/secrets/ShowSecretContainer.vue';
import { RouteRecordRaw } from 'vue-router';
import { useWindowProp } from '@/composables/useWindowProps';

const domain_strategy = useWindowProp('domain_strategy');
const display_domain = useWindowProp('display_domain');
const domain_id = useWindowProp('domain_id');
const domain_branding = useWindowProp('domain_branding');
const site_host = useWindowProp('site_host');

const routes: Array<RouteRecordRaw> = [

  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    components: {
      default: ShowSecretContainer,
    },
    props: true,
    meta: {
      domain_strategy: domain_strategy.value,
      display_domain: display_domain.value,
      domain_id: domain_id.value,
      domain_branding: domain_branding.value,
      site_host: site_host.value,
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
