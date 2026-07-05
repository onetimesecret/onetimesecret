// src/router/public.routes.ts

import HomepageContainer from '@/apps/secret/conceal/Homepage.vue';
import TransactionalFooter from '@/shared/components/layout/TransactionalFooter.vue';
import TransactionalHeader from '@/shared/components/layout/TransactionalHeader.vue';
import TransactionalLayout from '@/shared/layouts/TransactionalLayout.vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { SCOPE_PRESETS } from '@/types/router';
import type { LayoutProps } from '@/types/ui/layouts';
import { RouteRecordRaw, type RouteLocationNormalized } from 'vue-router';

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
function getLayoutPropsForMode(componentMode: string, domainStrategy: string): LayoutProps {
  const baseProps: LayoutProps = {
    displayHeader: true,
    displayMasthead: true,
    displayNavigation: true,
    displayFooterLinks: true,
    displayFeedback: true,
    displayPoweredBy: false,
    displayVersion: true,
    displayToggles: true,
  };

  let layoutProps: LayoutProps = { ...baseProps };

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
      // The disabled-homepage view owns its own centred logo (via the
      // dispatcher in apps/secret/views/DisabledHomepage.vue). The
      // top-left masthead is suppressed for canonical and custom domain
      // alike, and we drop the entire header chrome (the padded band)
      // so nothing else competes with the centred mark. The header slot
      // is reserved for a future canonical brand logo configured at the
      // deployment level.
      layoutProps = {
        ...layoutProps,
        displayHeader: false,
        displayMasthead: false,
        displayFeedback: false,
        displayVersion: false,
      };
      break;
  }

  // Apply custom domain overrides if needed
  // Custom domains get minimal layout - logo goes in content area, not MastHead.
  // Navigation stays enabled so TransactionalHeader can render a minimal
  // Sign In link above the page content.
  if (domainStrategy === 'custom') {
    layoutProps = {
      ...layoutProps,
      displayMasthead: false, // Logo goes in page content for centered experience
      displayNavigation: true, // Sign In handled by TransactionalHeader minimal nav
      displayFooterLinks: false,
      displayFeedback: false,
      displayVersion: false,
      displayPoweredBy: true, // Show "Powered by Onetime Secret"
    };
  }

  return layoutProps;
}

/**
 * Authenticated visitors to the public /pricing routes are already signed up
 * (and may be on a paid plan), so the marketing CTAs route them to /signup,
 * which the auth guard then blocks — the click logs but goes nowhere.
 * Redirect them to the in-app plan selector instead, carrying any deep-linked
 * product/interval as the query params PlanSelector already parses. The
 * /billing/plans redirect resolves the current org into /billing/:extid/plans.
 */
export function redirectAuthenticatedToPlans(to: RouteLocationNormalized) {
  const authStore = useAuthStore();
  if (!authStore.isAuthenticated) return true;

  const query: Record<string, string> = {};
  // Route params are scalar, but query params can arrive as arrays
  // (?interval=a&interval=b). Collapse to the first value so the
  // string ops below never see an array and throw mid-navigation.
  const rawProduct = to.params.product ?? to.query.product;
  const product = Array.isArray(rawProduct) ? rawProduct[0] : rawProduct;
  const rawInterval = to.params.interval ?? to.query.interval;
  const interval = Array.isArray(rawInterval) ? rawInterval[0] : rawInterval;
  if (product) query.product = product;
  if (interval) {
    const yearAliases = ['year', 'yearly', 'annual'];
    query.interval = yearAliases.includes(interval.toLowerCase()) ? 'yearly' : 'monthly';
  }

  return { path: '/billing/plans', query };
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
      sentryScrubParams: false,
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
      sentryScrubParams: false,
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
      sentryScrubParams: false,
    },
  },
  {
    path: '/pricing',
    name: 'Pricing',
    component: () => import('@/apps/secret/support/Pricing.vue'),
    beforeEnter: redirectAuthenticatedToPlans,
    meta: {
      title: 'web.TITLES.pricing',
      requiresAuth: false,
      excludeSsoOnly: true,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false, // Pricing page has its own feedback toggle
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  // Deep-link routes for external sites to link directly to specific plans
  // URL pattern: /pricing/:product/:interval
  // Examples: /pricing/identity_plus/month, /pricing/team_plus/year
  // Plan ID is the canonical family form (e.g., identity_plus_v1), interval is separate
  {
    path: '/pricing/:product',
    name: 'PricingProduct',
    component: () => import('@/apps/secret/support/Pricing.vue'),
    beforeEnter: redirectAuthenticatedToPlans,
    meta: {
      title: 'web.TITLES.pricing',
      requiresAuth: false,
      excludeSsoOnly: true,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/pricing/:product/:interval',
    name: 'PricingProductInterval',
    component: () => import('@/apps/secret/support/Pricing.vue'),
    beforeEnter: redirectAuthenticatedToPlans,
    meta: {
      title: 'web.TITLES.pricing',
      requiresAuth: false,
      excludeSsoOnly: true,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  // Developer tool: Icon gallery (not linked from navigation)
  {
    path: '/icons',
    name: 'IconGallery',
    component: () => import('@/views/IconGallery.vue'),
    meta: {
      title: 'Icon Gallery',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: false,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  // Developer tool: preview the disabled-homepage view alongside the live MastHead
  // (not linked from navigation). Renders the same DisabledHomepage content the real
  // disabled-homepage mode shows, but with a prominent notice making clear the
  // site is not actually disabled. Useful for verifying branding env vars
  // (BRAND_LOGO_URL, LOGO_SHOW_NAME, BRAND_PRODUCT_NAME, LOGO_PROMINENT)
  // without toggling UI_ENABLED or auth.required on the backend.
  {
    path: '/disabled',
    name: 'PreviewDisabled',
    components: {
      default: () => import('@/views/PreviewDisabled.vue'),
      header: TransactionalHeader,
      footer: TransactionalFooter,
    },
    meta: {
      title: 'web.COMMON.title_home',
      requiresAuth: false,
      layout: TransactionalLayout,
      layoutProps: {
        // Mirror the real disabled-homepage layout: the dispatcher owns
        // the centred logo, so the entire header chrome is hidden and
        // the preview banner butts directly against the brand stripe.
        displayHeader: false,
        displayMasthead: false,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
];

export default routes;
