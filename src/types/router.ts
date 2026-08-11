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

  /**
   * Both switchers visible but locked (e.g., receipt pages - shows context
   * without allowing change)
   */
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
  requiresFeature?: 'signup' | 'signin';
  /**
   * When true, this route is excluded when SSO-only mode is active.
   * The route guard redirects authenticated users to '/account'
   * and unauthenticated users to '/signin'.
   *
   * INVARIANT: never set this on a route the SSO flow itself traverses —
   * those routes declare `requiredInSsoOnly` (below), which the guard
   * gives precedence. Enforced by
   * src/tests/router/sso-only-reachability.spec.ts; new routes carrying
   * this flag must be added to its expected matrix.
   */
  excludeSsoOnly?: boolean;
  /**
   * When true, this route IS the SSO flow (or its MFA continuation) and
   * must stay reachable when SSO-only mode is active (site
   * restrict_to='sso'). In that mode most password-auth routes are hidden
   * via `excludeSsoOnly` (above), enforced by handleSsoOnlyRoute in
   * guards.routes.ts. The pinned set of flagged paths lives in
   * src/tests/router/sso-only-reachability.spec.ts (REQUIRED_IN_SSO_ONLY).
   *
   * The guard gives this flag precedence over `excludeSsoOnly`: if someone
   * copy-pastes `excludeSsoOnly` onto one of these routes, runtime
   * behavior stays correct (the route remains reachable) and the sweep
   * spec fails loudly on the double-flagged configuration.
   *
   * History: /mfa-verify once carried `excludeSsoOnly` by copy-paste.
   * handleSsoOnlyRoute runs BEFORE handleMfaAccess, so for awaitingMfa
   * users the ssoOnly guard bounced /mfa-verify -> /signin while
   * handleMfaAccess bounced /signin -> /mfa-verify — an infinite redirect
   * loop. MFA is flow-agnostic: an SSO sign-in can also demand a second
   * factor (the /sso-link-confirm POST returns mfa_required and hands off
   * to /mfa-verify), so the MFA continuation is part of the SSO flow.
   *
   * Enforced by src/tests/router/sso-only-reachability.spec.ts.
   */
  requiredInSsoOnly?: boolean;
  /**
   * When true, this route requires the signed-in customer to have the
   * `colonel` role. Set on every admin-console route (src/apps/admin).
   * Enforced by handleColonelRequirement in guards.routes.ts.
   */
  requiresColonel?: boolean;
  /**
   * Sentry URL scrubbing configuration. Controls which route params are
   * redacted in Sentry events to prevent sensitive data leakage.
   *
   * Fail-safe default: all dynamic params are scrubbed unless explicitly opted out.
   *
   * - `undefined` (default): scrub all route params — safe for routes with
   *   verifiable identifiers (secrets, receipts) or unknown sensitivity
   * - `true`: scrub all route params (explicit, same as default)
   * - `string[]`: scrub only the named params (e.g., `['token']`)
   * - `false`: explicit opt-out, no scrubbing — use for routes where all
   *   params are safe to expose (e.g., `/pricing/:product/:interval`)
   *
   * @see src/router/index.ts for verifiable identifier documentation
   * @see src/plugins/core/enableDiagnostics.ts for beforeSend implementation
   */
  sentryScrubParams?: boolean | string[];
}
