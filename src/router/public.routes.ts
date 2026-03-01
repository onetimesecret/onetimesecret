// src/router/public.routes.ts

import HomepageContainer from '@/apps/secret/conceal/Homepage.vue';
import TransactionalFooter from '@/shared/components/layout/TransactionalFooter.vue';
import TransactionalHeader from '@/shared/components/layout/TransactionalHeader.vue';
import TransactionalLayout from '@/shared/layouts/TransactionalLayout.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { SCOPE_PRESETS } from '@/types/router';
import { RouteRecordRaw } from 'vue-router';

// Extend RouteRecordRaw meta to include our custom componentMode
declare module 'vue-router' {
  interface RouteMeta {
    componentMode?: string;
  }
}

// Determine which homepage component mode to use
function determineComponentMode(): string {
  const bootstrapStore = useBootstrapStore();

  if (!bootstrapStore.ui?.enabled) {
    return 'disabled-ui';
  }

  const hasSession = document.cookie.includes('ots-session');

  // Only show disabled-homepage if user has no session and one of:
  //  - auth is required
  //  - if homepage is in external mode
  if (
    !hasSession &&
    (bootstrapStore.authentication?.required || bootstrapStore.homepage_mode === 'external')
  ) {
    console.debug('Homepage Mode disabled-homepage ' + bootstrapStore.homepage_mode);
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
      displayFooterLinks: false,
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
      header: TransactionalHeader,
      footer: TransactionalFooter,
    },
    meta: {
      title: 'web.COMMON.title_home',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
    beforeEnter: async (to) => {
      const bootstrapStore = useBootstrapStore();
      const domainStrategy = bootstrapStore.domain_strategy as string;
      const componentMode = determineComponentMode();
      const layoutProps = getLayoutPropsForMode(componentMode, domainStrategy);
      const hasSession = document.cookie.includes('ots-session');

      to.meta.componentMode = componentMode;
      to.meta.layoutProps = {
        ...to.meta.layoutProps,
        ...layoutProps,
      };

      // Scope visibility: show on canonical site for authenticated users only
      // Custom domains never show scopes (the domain itself IS the scope)
      if (domainStrategy !== 'custom' && hasSession) {
        to.meta.scopesAvailable = SCOPE_PRESETS.showBoth;
      } else {
        to.meta.scopesAvailable = SCOPE_PRESETS.hideBoth;
      }
    },
  },
  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/apps/secret/support/Feedback.vue'),
    meta: {
      title: 'web.TITLES.feedback',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/help',
    name: 'Help',
    component: () => import('@/apps/secret/support/Help.vue'),
    meta: {
      title: 'web.TITLES.help',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/pricing',
    name: 'Pricing',
    component: () => import('@/apps/secret/support/Pricing.vue'),
    meta: {
      title: 'web.TITLES.pricing',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false, // Pricing page has its own feedback toggle
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  // Deep-link routes for external sites to link directly to specific plans
  // URL pattern: /pricing/:product/:interval
  // Examples: /pricing/identity_plus/month, /pricing/team_plus/year
  // Resolves to plan ID: {product}_v{version}_{interval} (e.g., identity_plus_v1_monthly)
  {
    path: '/pricing/:product',
    name: 'PricingProduct',
    component: () => import('@/apps/secret/support/Pricing.vue'),
    meta: {
      title: 'web.TITLES.pricing',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/pricing/:product/:interval',
    name: 'PricingProductInterval',
    component: () => import('@/apps/secret/support/Pricing.vue'),
    meta: {
      title: 'web.TITLES.pricing',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
];

export default routes;
