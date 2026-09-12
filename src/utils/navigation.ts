// src/utils/navigation.ts

import { isValidInternalPath } from '@/utils/redirect';

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
