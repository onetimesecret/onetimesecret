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
  /**
   * Navigation target when switching organization.
   * - undefined: Just update store (current behavior)
   * - 'same': Stay on current route pattern, replace :extid with new org's extid
   * - Path with :extid (e.g., '/org/:extid'): Replace :extid and navigate
   * - Path without :extid (e.g., '/dashboard'): Navigate directly
   */
  onOrgSwitch?: string;
  /**
   * Navigation target when switching domain.
   * - undefined: Just update store (current behavior)
   * - 'same': Stay on current route pattern, replace :extid with new domain's extid
   * - Path with :extid (e.g., '/domains/:extid/brand'): Replace :extid and navigate
   * - Path without :extid (e.g., '/domains'): Navigate directly
   */
  onDomainSwitch?: string;
}

/**
 * Common scope configuration presets for routes.
 * Use these to maintain consistency across route definitions.
 */
export const SCOPE_PRESETS = {
  /** Both switchers visible and interactive (e.g., dashboard, domains list) */
  showBoth: { organization: 'show', domain: 'show' } as const,

  /** Both switchers hidden (e.g., account pages) */
  hideBoth: { organization: 'hide', domain: 'hide' } as const,

  /** Both switchers visible but locked (e.g., receipt pages - shows context without allowing change) */
  lockBoth: { organization: 'locked', domain: 'locked' } as const,

  /** Org interactive, domain locked to current (e.g., domain detail pages) */
  orgShowDomainLocked: { organization: 'show', domain: 'locked' } as const,

  /** Org locked, domain hidden (e.g., billing, org settings) */
  orgLockedDomainHide: { organization: 'locked', domain: 'hide' } as const,

  /** Org interactive, domain hidden (e.g., org list) */
  orgShowDomainHide: { organization: 'show', domain: 'hide' } as const,
} satisfies Record<string, ScopesAvailable>;

export interface RouteMeta {
  title?: string;
  requiresAuth?: boolean;
  isAuthRoute?: boolean;
  layout?: string;
  layoutProps?: Record<string, unknown>;
  scopesAvailable?: ScopesAvailable;
}
