// src/shared/constants/signin.ts

/**
 * Key under which useAuth.verifyAccount() hands the "just verified" signal to
 * the /signin page via router history `state` — never the URL query.
 *
 * It is a one-shot UI flag: the sign-in page shows a persistent success banner
 * and defaults to the password tab, then clears the flag so a refresh does not
 * re-trigger it. Carrying it in history state (instead of `?verified=1`) keeps
 * the address bar clean and, because it never changes the route's fullPath,
 * avoids remounting the fullPath-keyed routed component in App.vue — which would
 * otherwise discard the banner state. See src/apps/session/views/Login.vue.
 *
 * The name is deliberately app-specific to avoid clobbering vue-router's own
 * reserved state keys (back / current / forward / replaced / position / scroll),
 * which share the same history-state object.
 *
 * Shared between the writer (useAuth.verifyAccount) and the reader (Login.vue).
 */
export const SIGNIN_VERIFIED_STATE_KEY = 'signinVerified';
