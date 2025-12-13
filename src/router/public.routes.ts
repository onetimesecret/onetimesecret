// src/router/public.routes.ts

import DefaultFooter from '@/shared/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/shared/components/layout/DefaultHeader.vue';
import DefaultLayout from '@/shared/layouts/TransactionalLayout.vue';
import { WindowService } from '@/services/window.service';
import HomepageContainer from '@/apps/secret/conceal/Homepage.vue';
import { RouteRecordRaw } from 'vue-router';

// Extend RouteRecordRaw meta to include our custom componentMode
declare module 'vue-router' {
  interface RouteMeta {
    componentMode?: string;
  }
}

// Determine which homepage component mode to use
function determineComponentMode(): string {
  const ui = WindowService.get('ui');
  if (!ui?.enabled) {
    return 'disabled-ui';
  }

  const authentication = WindowService.get('authentication');
  const hasSession = document.cookie.includes('ots-session');
  const homepageMode = WindowService.get('homepage_mode');

  // Only show disabled-homepage if user has no session and one of:
  //  - auth is required
  //  - if homepage is in external mode
  if (!hasSession && (authentication?.required || homepageMode === 'external')) {
    console.debug('Homepage Mode disabled-homepage ' + homepageMode);
    return 'disabled-homepage';
  }

  return 'normal';
}

// Get layout props for the given component mode
function getLayoutPropsForMode(componentMode: string, domainStrategy: string) {
  const baseProps = {
    displayMasthead: true,
    displayNavigation: true,
    displayFooterLinks: true,
    displayFeedback: true,
    displayPoweredBy: false,
    displayVersion: true,
    displayToggles: true,
  };

  let layoutProps = { ...baseProps };

  // Apply component mode specific overrides
  switch (componentMode) {
    case 'disabled-ui':
      layoutProps = {
        ...layoutProps,
        displayMasthead: false,
        displayNavigation: false,
        displayFeedback: false,
        displayVersion: false,
      };
      break;
    case 'disabled-homepage':
      layoutProps = {
        ...layoutProps,
        displayFeedback: false,
        displayVersion: false,
      };
      break;
  }

  // Apply custom domain overrides if needed
  // Custom domains get minimal layout - logo goes in content area, not MastHead
  if (domainStrategy === 'custom') {
    layoutProps = {
      ...layoutProps,
      displayMasthead: false, // Logo goes in page content for centered experience
      displayNavigation: false,
      displayFooterLinks: true, // Keep Terms/Privacy links
      displayFeedback: false,
      displayVersion: false,
      displayPoweredBy: true, // Show "Powered by Onetime Secret"
    };
  }

  return layoutProps;
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
      const domainStrategy = WindowService.get('domain_strategy') as string;
      const componentMode = determineComponentMode();
      const layoutProps = getLayoutPropsForMode(componentMode, domainStrategy);

      to.meta.componentMode = componentMode;
      to.meta.layoutProps = {
        ...to.meta.layoutProps,
        ...layoutProps,
      };
    },
  },
  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/apps/secret/support/Feedback.vue'),
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
