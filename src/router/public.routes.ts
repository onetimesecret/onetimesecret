// src/router/public.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import { WindowService } from '@/services/window.service';
import HomepageContainer from '@/views/HomepageContainer.vue';
import { RouteRecordRaw } from 'vue-router';

// Extend RouteRecordRaw meta to include our custom componentState
declare module 'vue-router' {
  interface RouteMeta {
    componentState?: string;
  }
}

const routes: Array<RouteRecordRaw> = [
  {
    path: '/',
    name: 'Home',
    components: {
      default: HomepageContainer,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      title: 'web.COMMON.title_home',
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
    beforeEnter: async (to) => {
      // Use window service directly rather than the identity store
      // since the routes start before the pinia stores.
      const domainStrategy = WindowService.get('domain_strategy') as string;

      // Determine component state based on UI and authentication settings
      let componentState = 'normal';

      // Check if UI is completely disabled
      const ui = WindowService.get('ui');
      if (!ui?.enabled) {
        componentState = 'disabled-ui';
      } else {
        // Check if authentication is required but user is not authenticated
        const authentication = WindowService.get('authentication');
        // For route-level checks, we need to check session existence rather than store state
        const hasSession = document.cookie.includes('ots-session');
        if (authentication?.required && !hasSession) {
          componentState = 'disabled-homepage';
        }
      }

      // Store component state in meta for the container component
      to.meta.componentState = componentState;

      // Set layout props based on component state and domain strategy
      let layoutProps = {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      };

      // Apply component state specific overrides
      switch (componentState) {
        case 'disabled-ui':
          // DisabledUI layout: minimal header/nav
          layoutProps = {
            ...layoutProps,
            displayMasthead: false,
            displayNavigation: false,
            displayFooterLinks: true,
            displayFeedback: false,
            displayPoweredBy: false,
            displayVersion: false,
            displayToggles: true,
          };
          break;
        case 'disabled-homepage':
          // DisabledHomepage layout: show header/nav but no feedback
          layoutProps = {
            ...layoutProps,
            displayMasthead: true,
            displayNavigation: true,
            displayFooterLinks: true,
            displayFeedback: false,
            displayPoweredBy: false,
            displayVersion: false,
            displayToggles: true,
          };
          break;
        case 'normal':
        default:
          // Normal homepage layout - keep defaults
          break;
      }

      // Apply custom domain overrides if needed
      if (domainStrategy === 'custom') {
        layoutProps = {
          ...layoutProps,
          displayMasthead: true,
          displayNavigation: false,
          displayFooterLinks: false,
          displayFeedback: false,
          displayVersion: true,
          displayPoweredBy: false,
          displayToggles: true,
        };
      }

      // Set the final layout props
      to.meta.layoutProps = {
        ...to.meta.layoutProps,
        ...layoutProps,
      };
    },
  },
  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/views/Feedback.vue'),
    meta: {
      title: 'web.TITLES.feedback',
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false,
      },
    },
  },
];

export default routes;
