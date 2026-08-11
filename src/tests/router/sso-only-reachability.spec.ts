// src/tests/router/sso-only-reachability.spec.ts
//
// Reachability matrix for SSO-only mode (restrict_to='sso') — regression pin
// for the fix/4107 SSO-linking bug where /sso-link-confirm/:token and
// /link-sso/:token carried excludeSsoOnly (meta copied from a sibling route),
// so the one mode guaranteed to need the SSO interstitials bounced them to
// /signin before the consent page could mount. Both failure modes were silent:
// nothing forced a per-route decision on the flag, and nothing cross-checked
// the backend route table. This suite makes both loud:
//
//  1. EXCLUDED_IN_SSO_ONLY is the single expected set of paths carrying
//     excludeSsoOnly, checked exhaustively in BOTH directions — a route
//     gaining or losing the flag fails until this matrix is updated
//     deliberately.
//  2. requiredInSsoOnly (canonical doc: src/types/router.ts) positively marks
//     the routes the SSO flow itself traverses. The flagged set is pinned
//     here in BOTH directions — dropping the flag from one of the four fails,
//     and flagging a new route fails until it is deliberately added — and no
//     route may combine it with excludeSsoOnly.
//  3. Every session-app route must have an explicit GET entry in
//     apps/web/core/routes.txt: these routes are entered by full-page load
//     (emailed links, backend redirects), and a missing entry silently
//     degrades to the SPA not-found fallback — shell renders, status is 404.

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

// public.routes.ts reads bootstrapStore in route guards; give it a store
// before import (same posture as public.routes.spec.ts).
setActivePinia(
  createTestingPinia({
    createSpy: vi.fn,
    stubActions: false,
    initialState: {
      bootstrap: {
        authenticated: false,
        domain_strategy: 'canonical',
        ui: { enabled: true },
        authentication: { required: false },
        homepage_mode: null,
      },
    },
  })
);

const { default: sessionRoutes } = await import('@/apps/session/routes');
const { default: publicRoutes } = await import('@/router/public.routes');

interface FlatRoute {
  path: string;
  meta: Record<string, unknown>;
}

/**
 * Flatten a route table to matchable leaves, merging parent meta into
 * children the way vue-router's `to.meta` does at navigation time (the
 * guard reads the MERGED meta, so a flag on a parent covers its children).
 */
function flatten(
  routes: readonly RouteRecordRaw[],
  parentPath = '',
  parentMeta: Record<string, unknown> = {}
): FlatRoute[] {
  return routes.flatMap((route) => {
    const path = joinPaths(parentPath, route.path);
    const meta = { ...parentMeta, ...(route.meta ?? {}) };
    if (route.children?.length) return flatten(route.children, path, meta);
    return [{ path, meta }];
  });
}

function joinPaths(parent: string, child: string): string {
  if (!parent) return child;
  if (!child) return parent;
  return `${parent.replace(/\/+$/, '')}/${child.replace(/^\/+/, '')}`;
}

const sessionFlat = flatten(sessionRoutes);
const publicFlat = flatten(publicRoutes);
const allFlat = [...sessionFlat, ...publicFlat];

// ── 1. The exhaustive exclusion matrix ────────────────────────────────────
//
// Every path expected to carry excludeSsoOnly, and ONLY those. All are
// password/self-serve surface: routes that only make sense when password
// authentication (or self-serve signup/billing) is available.
const EXCLUDED_IN_SSO_ONLY = new Set([
  // session app — password-flow surface
  '/signup',
  '/signup/:planCode',
  '/forgot',
  '/check-email',
  '/verify-account',
  '/email-login',
  '/reset-password',
  // public app — self-serve billing surface
  '/pricing',
  '/pricing/:product',
  '/pricing/:product/:interval',
]);

// ── 2. The tripwire: routes flagged requiredInSsoOnly ─────────────────────
//
// The routes the SSO flow itself traverses declare requiredInSsoOnly: true
// (canonical doc: src/types/router.ts), and handleSsoOnlyRoute gives that
// flag precedence over excludeSsoOnly. /signin hosts the SSO buttons;
// /mfa-verify handles the second factor an SSO sign-in can demand (loop
// mechanics: see the requiredInSsoOnly doc in src/types/router.ts); the two
// interstitials are the #3840 account-linking consent pages reached
// mid-SSO-sign-in.
const REQUIRED_IN_SSO_ONLY = [
  '/signin',
  '/mfa-verify',
  '/link-sso/:token',
  '/sso-link-confirm/:token',
];

describe('SSO-only mode reachability', () => {
  it('every route matches the expected excludeSsoOnly matrix (both directions)', () => {
    for (const { path, meta } of allFlat) {
      const expected = EXCLUDED_IN_SSO_ONLY.has(path);
      expect(
        Boolean(meta.excludeSsoOnly),
        `${path}: excludeSsoOnly should be ${expected}. If this change is ` +
          `deliberate, update EXCLUDED_IN_SSO_ONLY in this spec — and never ` +
          `exclude a route the SSO flow itself needs (see REQUIRED_IN_SSO_ONLY ` +
          `and the requiredInSsoOnly doc in src/types/router.ts).`
      ).toBe(expected);
    }
  });

  it('the exclusion matrix contains no stale paths', () => {
    const knownPaths = new Set(allFlat.map((r) => r.path));
    for (const path of EXCLUDED_IN_SSO_ONLY) {
      expect(
        knownPaths.has(path),
        `EXCLUDED_IN_SSO_ONLY lists ${path}, which no longer exists — ` +
          `remove or update the entry`
      ).toBe(true);
    }
  });

  it('routes flagged requiredInSsoOnly are exactly the SSO-flow set (both directions)', () => {
    const flagged = allFlat
      .filter((r) => r.meta.requiredInSsoOnly === true)
      .map((r) => r.path);

    for (const path of REQUIRED_IN_SSO_ONLY) {
      expect(
        flagged,
        `${path} must declare requiredInSsoOnly: true — it is part of the ` +
          `SSO flow and must stay reachable in SSO-only mode (see the ` +
          `requiredInSsoOnly doc in src/types/router.ts)`
      ).toContain(path);
    }
    for (const path of flagged) {
      expect(
        REQUIRED_IN_SSO_ONLY,
        `${path} carries requiredInSsoOnly but is not in this spec's ` +
          `expected set. If the route genuinely IS the SSO flow (or its MFA ` +
          `continuation), add it to REQUIRED_IN_SSO_ONLY deliberately; ` +
          `otherwise remove the flag (see the requiredInSsoOnly doc in ` +
          `src/types/router.ts).`
      ).toContain(path);
    }
  });

  it('SSO-flow routes exist and are never excluded in SSO-only mode', () => {
    for (const path of REQUIRED_IN_SSO_ONLY) {
      const route = allFlat.find((r) => r.path === path);
      expect(route, `${path} must exist — the SSO flow depends on it`).toBeDefined();
      expect(
        route?.meta.excludeSsoOnly,
        `${path} is part of the SSO flow and must stay reachable in SSO-only ` +
          `mode (see the requiredInSsoOnly doc in src/types/router.ts)`
      ).toBeFalsy();
      expect(
        EXCLUDED_IN_SSO_ONLY.has(path),
        `${path} must not be listed in EXCLUDED_IN_SSO_ONLY`
      ).toBe(false);
    }
  });

  it('no route combines requiredInSsoOnly with excludeSsoOnly', () => {
    for (const { path, meta } of allFlat) {
      expect(
        meta.requiredInSsoOnly === true && Boolean(meta.excludeSsoOnly),
        `${path} carries BOTH requiredInSsoOnly and excludeSsoOnly — a ` +
          `configuration error: the flags are mutually exclusive. The guard ` +
          `gives requiredInSsoOnly precedence at runtime, but the conflicting ` +
          `flag must be removed (see the requiredInSsoOnly doc in ` +
          `src/types/router.ts).`
      ).toBe(false);
    }
  });
});

// ── 3. Backend shell coverage for full-page-load entry points ─────────────

/** GET path patterns from apps/web/core/routes.txt. */
function backendGetPatterns(): string[] {
  const routesTxt = resolve(
    dirname(fileURLToPath(import.meta.url)),
    '../../../apps/web/core/routes.txt'
  );
  return readFileSync(routesTxt, 'utf8')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.startsWith('GET'))
    .map((line) => line.split(/\s+/)[1]);
}

/**
 * Match a concrete path against a routes.txt pattern: `:param` matches one
 * segment, a trailing `*` matches one or more remaining segments.
 */
function patternMatches(pattern: string, path: string): boolean {
  const patternSegs = pattern.split('/').filter(Boolean);
  const pathSegs = path.split('/').filter(Boolean);
  for (let i = 0; i < patternSegs.length; i++) {
    const seg = patternSegs[i];
    if (seg === '*') return pathSegs.length > i;
    if (i >= pathSegs.length) return false;
    if (!seg.startsWith(':') && seg !== pathSegs[i]) return false;
  }
  return patternSegs.length === pathSegs.length;
}

describe('backend routes.txt covers session-app entry points', () => {
  const patterns = backendGetPatterns();

  it.each(sessionFlat.map((r) => r.path))(
    '%s has an explicit backend entry (200 shell, not the 404 fallback)',
    (path) => {
      // Substitute params with a concrete segment for matching.
      const concrete = path
        .split('/')
        .map((seg) => (seg.startsWith(':') ? 'sample' : seg))
        .join('/');
      const covered = patterns.some((pattern) => patternMatches(pattern, concrete));
      expect(
        covered,
        `${path} is a full-page-load entry point (emailed links, backend ` +
          `redirects) but has no GET entry in apps/web/core/routes.txt — the ` +
          `SPA shell would be served via the not-found fallback with a 404 status`
      ).toBe(true);
    }
  );
});
