// src/router/layout.config.ts

// Shared layout configuration for route definitions.
// Centralizes layout props to reduce duplication and ensure consistency.

import ImprovedFooter from '@/shared/components/layout/ImprovedFooter.vue';
import ImprovedHeader from '@/shared/components/layout/ImprovedHeader.vue';
import ImprovedLayout from '@/shared/layouts/ManagementLayout.vue';

/**
 * Standard layout props for authenticated pages with full navigation.
 * Used across account, billing, and teams routes.
 */
export const standardLayoutProps = {
  displayMasthead: true,
  displayNavigation: true,
  displayFooterLinks: true,
  displayFeedback: true,
  displayPoweredBy: false,
  displayVersion: true,
  showSidebar: false,
} as const;

/**
 * Standard components configuration for routes using ImprovedLayout.
 */
export const improvedLayoutComponents = {
  header: ImprovedHeader,
  footer: ImprovedFooter,
} as const;

/**
 * Standard meta configuration for authenticated routes.
 */
export const improvedLayoutMeta = {
  layout: ImprovedLayout,
  layoutProps: standardLayoutProps,
} as const;

export { ImprovedFooter, ImprovedHeader, ImprovedLayout };
