// src/utils/navigation.ts

import { isValidInternalPath } from '@/utils/redirect';
import type { Router } from 'vue-router';

/**
 * Full-page (non-SPA) navigation to a SERVER-SUPPLIED internal path.
 *
 * Two distinct jobs, both of which the router cannot do:
 *
 * 1. **It leaves the SPA.** The admin console (/colonel) and the customer app
 *    are separate Vite bundles with separate routers, so crossing between them
 *    requires a document load — `router.push('/')` from the console resolves
 *    against the ADMIN route table and 404s. Impersonation crosses that
 *    boundary in both directions (start: console → app, stop: app → console).
 *
 * 2. **It re-reads the bootstrap.** Identity is injected into the document at
 *    render time, so a soft navigation would keep rendering the previous
 *    session's payload. Starting or stopping an impersonation changes WHO the
 *    server says you are; only a document load makes the UI agree with it.
 *
 * The target is validated with {@link isValidInternalPath} — the same
 * accept/reject ruleset the Ruby side applies to redirect params — because it
 * arrives in a response body. A rejected (or absent) target falls back rather
 * than throwing: navigation is the tail end of an action that already
 * succeeded server-side, and stranding the operator on a stale page is worse
 * than landing them somewhere safe. The fallback is validated too, so a
 * caller's typo cannot smuggle in an off-origin destination; '/' is the last
 * resort.
 *
 * @param target - server-supplied path (e.g. `record.redirect`)
 * @param fallback - internal path to use when `target` is missing/unsafe
 */
export function hardNavigate(target: string | null | undefined, fallback: string): void {
  let destination = '/';
  if (isValidInternalPath(target)) {
    destination = target;
  } else if (isValidInternalPath(fallback)) {
    destination = fallback;
  }
  window.location.assign(destination);
}

/**
 * True when `router` has a route of its own for `target`, i.e. the path
 * resolves to something other than the router's `NotFound` catch-all.
 *
 * The customer app and the admin console are separate bundles with separate
 * route tables; the server picks the bundle per path. A `router.push` to a
 * path the current router does not own never reaches the server: the address
 * bar changes and the catch-all renders the SPA's 404 in place. That is what
 * the post-sign-in `?redirect=/colonel` did from the customer bundle. Callers
 * holding an arbitrary internal path check this first and fall back to
 * {@link hardNavigate} when it is false.
 *
 * Both routers name their catch-all 'NotFound' (src/router/index.ts,
 * src/apps/admin/router.ts).
 *
 * @param router - the router of the bundle currently running
 * @param target - a validated internal path, possibly with ?query / #hash
 */
export function routerOwnsPath(router: Router, target: string): boolean {
  return router.resolve(target).name !== 'NotFound';
}
