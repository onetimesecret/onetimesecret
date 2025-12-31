// src/types/router.ts

/**
 * Type extension for route meta to include title property
 * Used by router configuration and page title management
 */

/**
 * Scope switcher visibility states:
 * - 'show': Switcher is visible and interactive
 * - 'locked': Switcher is visible but disabled (context is fixed by route)
 * - 'hide': Switcher is not rendered
 */
export type ScopeSwitcherState = 'show' | 'locked' | 'hide';

/**
 * Configuration for which scope switchers are available on a route.
 * Used by layouts to conditionally render organization/domain selectors.
 */
export interface ScopesAvailable {
  organization?: ScopeSwitcherState;
  domain?: ScopeSwitcherState;
}

export interface RouteMeta {
  title?: string;
  requiresAuth?: boolean;
  isAuthRoute?: boolean;
  layout?: string;
  layoutProps?: Record<string, unknown>;
  scopesAvailable?: ScopesAvailable;
}
