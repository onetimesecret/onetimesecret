// src/shared/constants/checkEmail.ts

/**
 * Key under which the post-signup flow hands the just-registered email address
 * to the /check-email page via router history `state` — never the URL.
 *
 * The email is PII; a URL query would leak it through browser history, the
 * Referer header, proxy/CDN access logs and Sentry. History state carries it to
 * the next page while staying out of the address bar. See src/utils/pii.ts and
 * the "Query-string policy" section of src/router/README.md.
 *
 * The name is deliberately app-specific to avoid clobbering vue-router's own
 * reserved state keys (back / current / forward / replaced / position / scroll),
 * which share the same history-state object.
 *
 * Shared between the writer (useAuth.signup) and the reader (CheckEmail.vue).
 */
export const CHECK_EMAIL_STATE_KEY = 'checkEmailAddress';
