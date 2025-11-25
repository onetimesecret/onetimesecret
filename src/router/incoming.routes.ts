// src/router/incoming.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import IncomingSecretForm from '@/views/incoming/IncomingSecretForm.vue';
import IncomingSuccessView from '@/views/incoming/IncomingSuccessView.vue';
import { RouteRecordRaw } from 'vue-router';

/**
 * Routes for the incoming secrets feature.
 *
 * Allows anonymous users to send encrypted secrets to pre-configured recipients.
 * - /incoming - Form to create and send a secret
 * - /incoming/success/:key - Success page after secret creation
 */
const routes: Array<RouteRecordRaw> = [
  {
    path: '/incoming',
    name: 'Incoming',
    components: {
      default: IncomingSecretForm,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      title: 'incoming.page_title',
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      },
    },
  },
  {
    path: '/incoming/success/:key',
    name: 'IncomingSuccess',
    components: {
      default: IncomingSuccessView,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      title: 'incoming.success_title',
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      },
    },
    props: {
      default: (route) => ({
        metadataKey: route.params.key,
      }),
      header: false,
      footer: false,
    },
  },
];

export default routes;
