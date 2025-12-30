// src/router/layout.config.ts

// Shared layout configuration for route definitions.
// Centralizes layout props to reduce duplication and ensure consistency.
// Note: Workspace app has its own WorkspaceLayout in src/apps/workspace/layouts/

import ManagementFooter from '@/shared/components/layout/ManagementFooter.vue';
import ManagementHeader from '@/shared/components/layout/ManagementHeader.vue';
import ManagementLayout from '@/shared/layouts/ManagementLayout.vue';

/**
 * Standard layout props for authenticated pages with full navigation.
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
 * Standard components configuration for routes using ManagementLayout.
 */
export const improvedLayoutComponents = {
  header: ManagementHeader,
  footer: ManagementFooter,
} as const;

/**
 * Standard meta configuration for authenticated routes.
 */
export const improvedLayoutMeta = {
  layout: ManagementLayout,
  layoutProps: standardLayoutProps,
} as const;

export { ManagementFooter, ManagementHeader, ManagementLayout };
