// src/router/piiQueryGuard.ts

import { findPiiQueryKeys } from '@/utils/pii';
import type { RouteLocationNormalized, Router } from 'vue-router';

/**
 * Legacy routes that still carry an email in the query for form prefill
 * (sign-in ⇄ sign-up hand-off, invitation links). These pre-date the
 * "no PII in the query" policy and are scrubbed at the diagnostics layer; the
 * dev warning skips them so the console stays signal, not noise. New routes must
 * NOT be added here — hand PII over via router history state instead.
 */
const LEGACY_PII_QUERY_PATHS = new Set<string>(['/signin', '/signup']);

/**
 * Dev-only navigation guard: warns when a navigation target carries a PII key
 * (email, token, …) in its URL query. URLs leak through browser history, the
 * Referer header, proxy/CDN access logs and Sentry, so PII belongs in router
 * `state`, not the query (see src/utils/pii.ts and src/router/README.md
 * "Query-string policy").
 *
 * This is a developer aid, not a runtime control — it only logs, never blocks a
 * navigation, and is tree-shaken out of production builds by the caller's
 * `import.meta.env.DEV` gate. The diagnostics scrubber is the actual runtime
 * safety-net; this just surfaces the mistake at author time.
 */
export function installPiiQueryDevWarning(router: Router): void {
  router.beforeEach((to: RouteLocationNormalized) => {
    if (LEGACY_PII_QUERY_PATHS.has(to.path)) return true;

    const leaked = findPiiQueryKeys(to.query as Record<string, unknown>);
    if (leaked.length > 0) {
      console.warn(
        `[privacy] PII key(s) [${leaked.join(', ')}] found in the URL query for ` +
          `"${to.fullPath}". URLs leak via history, Referer, access logs and Sentry — ` +
          `pass these via router history state instead of the query. ` +
          `See src/router/README.md "Query-string policy".`
      );
    }
    return true;
  });
}
