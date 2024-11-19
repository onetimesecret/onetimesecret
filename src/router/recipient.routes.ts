import ShowSecretContainer from '@/views/secrets/ShowSecretContainer.vue';
import type { RouteRecordRaw } from 'vue-router';

import { resolveSecret } from './resolvers/secretResolver';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    component: ShowSecretContainer,
    props: true,
    beforeEnter: resolveSecret,
    meta: {
      domain_strategy: window.domain_strategy,
      display_domain: window.display_domain,
      domain_id: window.domain_id,
      site_host: window.site_host
    }
  }
]
export default routes;
