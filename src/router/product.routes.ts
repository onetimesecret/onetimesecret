import WideLayout from '@/layouts/WideLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/pricing',
    name: 'Pricing',
    component: () => import('@/views/pricing/PricingSolo.vue'),
    meta: {
      requiresAuth: false,
      layout: WideLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
    props: true,
  },
];

export default routes;
