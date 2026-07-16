// src/router/guards.routes.ts

import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { usePageTitle } from '@/shared/composables/usePageTitle';
import { useAuthStore } from '@/shared/stores/authStore';
import { useLanguageStore } from '@/shared/stores/languageStore';
import { isSsoOnlyMode } from '@/utils/features';
import { isValidInternalPath } from '@/utils/redirect';
import { RouteLocationNormalized, RouteLocationRaw, Router } from 'vue-router';

import { processQueryParams } from './queryParams.handler';

export async function setupRouterGuards(router: Router): Promise<void> {
  const { setTitle } = usePageTitle();
  let currentTitle: string | null = null;

  // Apply custom domain layout defaults for guest/public routes only.
  // Prevents the canonical OTS logo/branding from leaking on custom domain
  // pages that lack explicit beforeEnter guards (e.g. secret reveal pages).
  //
  // Authenticated workspace routes (requiresAuth) skip this guard so they
  // get the canonical logo, full navigation, and user menu. Context switchers
  // (org/domain) independently hide themselves on custom domains via
  // useScopeSwitcherVisibility (isCustom check).
  router.beforeEach((to: RouteLocationNormalized) => {
    const bootstrapStore = useBootstrapStore();
    if (bootstrapStore.domain_strategy !== 'custom') return true;

    // Authenticated routes use default layout — canonical logo, full nav.
    if (to.meta.requiresAuth) return true;

    // Auth routes (signin, signup, etc.) handle their own branding via
    // titleLogo in AuthView — don't override their layout props.
    if (to.meta.isAuthRoute) return true;

    const existing = (to.meta.layoutProps ?? {}) as Record<string, unknown>;

    // Guard overrides win over route-defined static defaults.
    // Per-route beforeEnter guards run AFTER beforeEach and can
    // still override these values for route-specific needs.
    //
    // Masthead is always OFF on custom domains: the top masthead renders a
    // duplicate logo/title/subtitle band, and each branded page body already
    // owns its own centred logo + copy (BrandedHomepage, IncomingForm) or is
    // intentionally distraction-free (secret reveal). This mirrors the
    // custom-domain layout in public.routes.ts ("logo goes in page content").
    // Gating it on logo presence previously produced a duplicate header on
    // /incoming and leaked the masthead onto the reveal page whenever a brand
    // logo was configured.
    to.meta.layoutProps = {
      ...existing,
      displayMasthead: false,
      displayNavigation: false,
      displayFooterLinks: false,
      displayFeedback: false,
    };

    return true;
  });

  // Block access to routes for disabled auth features (e.g. signup, signin).
  // Runs as a separate guard to keep complexity per-function within limits.
  router.beforeEach((to: RouteLocationNormalized) => {
    const redirect = handleDisabledAuthFeature(to);
    return redirect ?? true;
  });

  // Block access to routes marked excludeSsoOnly when SSO-only mode is active.
  router.beforeEach((to: RouteLocationNormalized) => {
    const redirect = handleSsoOnlyRoute(to);
    return redirect ?? true;
  });

  router.beforeEach(async (to: RouteLocationNormalized) => {
    const authStore = useAuthStore();
    const languageStore = useLanguageStore();

    logNavigation(to, authStore);
    processQueryParams(to.query as Record<string, string>);

    if (to.name === 'NotFound') return true;

    // Handle MFA requirement checks
    const mfaRedirect = handleMfaAccess(to, authStore);
    if (mfaRedirect) return mfaRedirect;


    // Handle root path redirect
    if (to.path === '/') return authStore.isFullyAuthenticated ? { name: 'Dashboard' } : true;

    // Redirect fully authenticated users away from auth routes (respect redirect param)
    // MFA pending users should still access auth routes like /mfa-verify
    if (isAuthRoute(to) && authStore.isFullyAuthenticated) {
      const redirect = handleAuthRouteRedirect(to);
      if (redirect) return redirect;
    }

    // Validate authentication for protected routes
    if (requiresAuthentication(to)) {
      const isAuthenticated = await validateAuthentication(authStore, to);
      if (!isAuthenticated) return redirectToSignIn(to);

      const userPreferences = await fetchCustomerPreferences();
      if (userPreferences.locale) {
        languageStore.setCurrentLocale(userPreferences.locale);
      }
    }

    return true; // Always return true for non-auth routes
  });

  // Org-role gate (meta.requiresOrgRole); after the auth guard so it only runs
  // for signed-in users.
  router.beforeEach(async (to) => (await handleOrgRoleRequirement(to)) ?? true);

  // Colonel gate (meta.requiresColonel); admin bundle only. After the auth guard
  // so a logged-out user is sent to /signin first and this only fires for an
  // authenticated-but-non-colonel. No-op on the customer router (no route sets
  // requiresColonel). Returns false to abort the SPA nav when it hard-navigates
  // out of the admin bundle; null (allow) becomes true via the `?? true`.
  router.beforeEach((to) => handleColonelRequirement(to) ?? true);

  // Update page title after navigation completes
  router.afterEach((to: RouteLocationNormalized) => {
    // Find the title from the matched routes, starting from the most specific
    // This handles nested routes properly by inheriting from parent routes
    const nearestWithTitle = to.matched
      .slice()
      .reverse()
      .find((r) => r.meta && r.meta.title);

    let newTitle: string | null = null;

    if (nearestWithTitle) {
      newTitle = nearestWithTitle.meta.title as string;
    } else if (to.name && typeof to.name === 'string') {
      // Fallback to route name if no title is specified in the route hierarchy
      newTitle = to.name;
    }

    // Only update title if it has changed
    if (newTitle !== currentTitle) {
      currentTitle = newTitle;
      setTitle(newTitle);
    }
  });
}

function requiresAuthentication(route: RouteLocationNormalized): boolean {
  return !!route.meta?.requiresAuth;
}

function isAuthRoute(route: RouteLocationNormalized): boolean {
  return !!route.meta?.isAuthRoute;
}

/**
 * Handle MFA verification access control
 * @param to - Target route
 * @param authStore - Auth store with awaitingMfa and isFullyAuthenticated getters
 * @returns Redirect object or null if no redirect needed
 */
function handleMfaAccess(
  to: RouteLocationNormalized,
  authStore: {
    awaitingMfa: boolean;
    isFullyAuthenticated: boolean;
    isAuthenticated: boolean | null;
  }
) {
  const { awaitingMfa, isFullyAuthenticated, isAuthenticated } = authStore;

  // DEBUG: Log MFA state on every navigation
  loggingService.debug('[MFA Guard] State check:', {
    targetPath: to.path,
    targetName: to.name,
    awaitingMfa,
    isAuthenticated,
    isFullyAuthenticated,
  });

  // Redirect to MFA verification if awaiting second factor
  if (awaitingMfa && to.path !== '/mfa-verify') {
    loggingService.debug('[MFA Guard] Redirecting to /mfa-verify (awaiting MFA)');
    return { path: '/mfa-verify' };
  }

  // Prevent access to MFA verify page when not awaiting MFA
  if (to.path === '/mfa-verify' && !awaitingMfa) {
    // Use isFullyAuthenticated to determine redirect target
    const redirect = isFullyAuthenticated ? { name: 'Dashboard' } : { path: '/signin' };
    loggingService.debug('[MFA Guard] Redirecting from /mfa-verify:', {
      redirect,
      reason: 'not awaiting MFA',
    });
    return redirect;
  }

  return null;
}

/**
 * Block access to routes that require a disabled auth feature.
 *
 * Routes can declare `meta.requiresFeature: 'signup' | 'signin'` to
 * indicate they need a specific authentication feature to be enabled.
 * When the feature is disabled (via AUTH_SIGNUP, AUTH_SIGNIN, or the
 * master AUTH_ENABLED toggle), the user is redirected to '/'.
 */
function handleDisabledAuthFeature(to: RouteLocationNormalized) {
  const feature = to.meta.requiresFeature;
  if (!feature) return null;

  const bootstrapStore = useBootstrapStore();
  const { authentication } = bootstrapStore;

  if (!authentication?.enabled || !authentication[feature]) {
    loggingService.debug(
      '[RouterGuard] Redirecting - auth feature disabled:',
      { feature, path: to.path }
    );
    return { path: '/' };
  }

  return null;
}

/**
 * Block access to routes marked with `meta.excludeSsoOnly: true`
 * when SSO-only mode is active.
 *
 * Authenticated routes redirect to '/account' (profile page).
 * Unauthenticated routes redirect to '/signin' (SSO sign-in page).
 * Note: /signin is explicitly excluded to prevent redirect loops.
 */
export function handleSsoOnlyRoute(to: RouteLocationNormalized) {
  if (!to.meta.excludeSsoOnly) return null;
  if (!isSsoOnlyMode()) return null;
  // Prevent redirect loop: never redirect /signin to itself
  if (to.path === '/signin') return null;

  loggingService.debug(
    '[RouterGuard] Redirecting - SSO-only mode blocks route:',
    { path: to.path }
  );

  // Authenticated users land on profile; unauthenticated on sign-in
  const authStore = useAuthStore();
  if (authStore.isFullyAuthenticated) {
    return { path: '/account' };
  }
  return { path: '/signin' };
}

/** True when `role` meets the `required` minimum (owner ⊃ admin). */
function roleMeetsRequirement(
  role: string | null | undefined,
  required: 'owner' | 'admin'
): boolean {
  if (required === 'owner') return role === 'owner';
  return role === 'owner' || role === 'admin';
}

/**
 * Enforce per-route org-role requirements declared via `meta.requiresOrgRole`.
 *
 * Single-org routes carry the org in the path (:extid or :orgid); the role is
 * resolved from that org — cached list, bootstrap-seeded current org, or a
 * fetch when the role isn't yet known (deep link). The organizations list page
 * (`/orgs`) has no single-org context, so it is satisfied when ANY org the user
 * belongs to meets the required role; the list is fetched first so a fresh deep
 * link doesn't bounce a real owner.
 *
 * Returns a redirect to '/dashboard' (outside every org route, so no redirect
 * loop) when the requirement isn't met, or null to allow navigation. Fails
 * closed: an unknown role and a rejected fetch both redirect, because the
 * list endpoint enforces no role and provides no backend backstop.
 */
export async function handleOrgRoleRequirement(
  to: RouteLocationNormalized
): Promise<RouteLocationRaw | null> {
  const required = to.meta.requiresOrgRole;
  if (!required) return null;

  const store = useOrganizationStore();
  // Resolve the ORG id from the path. Domain routes are
  // /org/:orgid/domains/:extid — there :extid is the DOMAIN id, so :orgid must
  // win; settings routes carry the org as :extid only.
  const orgExtid = (to.params.orgid ?? to.params.extid) as string | undefined;

  // Single-org routes test the org named in the path; the list page (no org in
  // the path) is met when any membership qualifies.
  const meets = orgExtid
    ? await singleOrgMeetsRole(store, orgExtid, required)
    : await anyOrgMeetsRole(store, required);

  return meets ? null : { path: '/dashboard' };
}

type OrganizationStore = ReturnType<typeof useOrganizationStore>;

/**
 * List-page scope (`/orgs`): met when any NON-DEFAULT org the user belongs to
 * satisfies `required`. The list is fetched first so a fresh deep link doesn't
 * bounce a real owner; a failed fetch fails closed.
 *
 * Default workspaces are excluded for non-owners because every user gets one —
 * checking them would let regular members access the orgs list page (see #3326).
 * Owners of default workspaces (self-signup users) are allowed through.
 */
async function anyOrgMeetsRole(
  store: OrganizationStore,
  required: 'owner' | 'admin'
): Promise<boolean> {
  if (!store.isListFetched) {
    try {
      await store.fetchOrganizations();
    } catch {
      return false;
    }
  }
  return store.organizations.some(
    (o) => (!o.is_default || o.current_user_role === 'owner') && roleMeetsRequirement(o.current_user_role, required)
  );
}

/**
 * Single-org scope: resolve the org named by `extid` (cached list, bootstrap
 * current org, or a fetch when the role is unknown) and test its role. A
 * rejected fetch — e.g. a non-member's backend 403 — fails closed.
 */
async function singleOrgMeetsRole(
  store: OrganizationStore,
  extid: string,
  required: 'owner' | 'admin'
): Promise<boolean> {
  let org =
    store.getOrganizationByExtid(extid) ??
    (store.currentOrganization?.extid === extid ? store.currentOrganization : null);

  if (!org?.current_user_role) {
    try {
      org = await store.fetchOrganization(extid);
    } catch {
      return false;
    }
  }

  return roleMeetsRequirement(org?.current_user_role, required);
}

/**
 * Enforce the colonel-only requirement declared via `meta.requiresColonel`
 * (set on every admin-console route via adminDefaultMeta).
 *
 * Client-side defence-in-depth: the backend already gates /colonel on
 * role=colonel and 403s the admin APIs, but without this guard an
 * authenticated non-colonel loads the full admin shell client-side before the
 * API calls fail. The role is read synchronously from the server-injected
 * bootstrap customer (no fetch).
 *
 * Redirect subtlety: the admin router has NO /dashboard and NO /signin route,
 * so a SPA redirect (e.g. `{ path: '/dashboard' }`) would resolve to the admin
 * NotFound view still inside the /colonel shell. A non-colonel must be
 * hard-navigated OUT of the admin bundle into the customer app via
 * window.location.assign('/'); the guard returns `false` to abort the in-SPA
 * navigation while the full page load takes over.
 *
 * Returns null to allow navigation (colonel, or a route without the flag), or
 * false to abort after triggering the hard navigation.
 */
export function handleColonelRequirement(to: RouteLocationNormalized): false | null {
  if (!to.meta.requiresColonel) return null;

  const role = useBootstrapStore().cust?.role;
  if (role === 'colonel') return null;

  loggingService.debug('[RouterGuard] Non-colonel blocked from admin route:', {
    path: to.path,
    role,
  });

  window.location.assign('/');
  return false;
}

/**
 * Handle redirects for authenticated users accessing auth routes.
 * Returns a redirect target or null if no redirect needed.
 */
function handleAuthRouteRedirect(to: RouteLocationNormalized) {
  // Allow reset-password with token regardless of auth state - the token is the authorization
  if (to.path === '/reset-password' && to.query.key) {
    return null;
  }
  // Redirect /forgot to the authenticated reset password page
  if (to.path === '/forgot') {
    return { path: '/account/settings/security/reset-password' };
  }
  // Respect redirect param if valid. isValidInternalPath additionally caps
  // length at 2048 and rejects embedded '://' that the ad-hoc slash check missed.
  const redirectParam = to.query.redirect as string | undefined;
  return isValidInternalPath(redirectParam) ? { path: redirectParam } : { name: 'Dashboard' };
}

function redirectToSignIn(from: RouteLocationNormalized) {
  return {
    path: '/signin',
    query: { redirect: from.fullPath },
  };
}

/** Debug logging helper for navigation guard */
function logNavigation(to: RouteLocationNormalized, authStore: AuthValidator) {
  loggingService.debug('[RouterGuard] Navigation to:', {
    path: to.path,
    name: to.name,
    requiresAuth: to.meta?.requiresAuth,
    isAuthRoute: to.meta?.isAuthRoute,
    authStoreState: {
      isAuthenticated: authStore.isAuthenticated,
      needsCheck: authStore.needsCheck,
    },
  });
}

/**
 * Interface Segregation Pattern for Auth Validation
 *
 * Instead of using the full store type (which includes many Pinia internals),
 * we define a minimal interface containing only the properties needed for
 * authentication validation. This follows the Interface Segregation Principle:
 * clients should not depend on methods they don't use.
 *
 * Evolution of this solution:
 * 1. Initially tried defining full AuthStore type with Pinia generics - too complex
 * 2. Attempted using StoreGeneric & partial types - worked but was hard to maintain
 * 3. Settled on this interface approach because:
 *    - Avoids Pinia's complex typing system altogether
 *    - Makes no assumptions about store implementation
 *    - Clearly documents what validation actually needs
 *
 * Benefits:
 * 1. Cleaner type definitions
 * 2. Better testability (can mock just these properties)
 * 3. Decoupled from Pinia implementation details
 * 4. Clearer contract for what validation requires
 *
 * The store automatically satisfies this interface through TypeScript's
 * structural typing, without explicit type casting or declarations.
 */
interface AuthValidator {
  needsCheck: boolean;
  isAuthenticated: boolean | null;
  checkWindowStatus: () => Promise<boolean | null>;
}

/**
 * Validates authentication state for protected route access
 * @param store - Auth store interface containing authentication state/methods
 * @param route - Vue Router normalized route object
 * @returns Promise<boolean> indicating if authentication is valid
 *
 * Code paths:
 * 1. Public route - Returns true without auth check
 * 2. Initial/stale auth - Performs async verification if needsCheck=true
 * 3. Cached auth - Returns existing isAuthenticated state (false if undefined)
 */
async function validateAuthentication(
  store: AuthValidator, // tried AuthStore, etc
  route: RouteLocationNormalized
): Promise<boolean> {
  if (!requiresAuthentication(route)) {
    loggingService.debug('[validateAuthentication] Public route, skipping auth check');
    return true;
  }

  loggingService.debug('[validateAuthentication] Checking auth for protected route:', {
    path: route.path,
    needsCheck: store.needsCheck,
    isAuthenticated: store.isAuthenticated,
  });

  if (store.needsCheck) {
    loggingService.debug('[validateAuthentication] needsCheck=true, calling checkWindowStatus');
    const authStatus = await store.checkWindowStatus();
    loggingService.debug('[validateAuthentication] checkWindowStatus returned:', { authStatus });
    return authStatus ?? false;
  }

  loggingService.debug('[validateAuthentication] Using cached auth state:', {
    isAuthenticated: store.isAuthenticated,
  });
  return store.isAuthenticated ?? false;
}

/**
 * Returns a dictionary of the customer's preferences.
 *
 * Currently the customer object is passed from backend on the initial
 * page load so there is no fetch happening. This implementation should
 * allow us to drop-in a request to the server when we need to.
 */
async function fetchCustomerPreferences(): Promise<{ locale?: string }> {
  const bootstrapStore = useBootstrapStore();
  // Explicitly handle null case and type narrow
  const locale = bootstrapStore.cust?.locale ?? undefined;
  return { locale };
}

export type { AuthValidator };

export {
  fetchCustomerPreferences,
  isAuthRoute,
  redirectToSignIn,
  requiresAuthentication,
  validateAuthentication,
};
