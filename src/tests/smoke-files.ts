// src/tests/smoke-files.ts

/**
 * The vitest files the smoke test runs (`pnpm test:smoke:vitest`, through
 * vitest.smoke.config.ts). The full suite still runs in `pnpm test` and in
 * the T2 TypeScript Unit Tests job; this list is a subset of it.
 *
 * Selection rules. A file is listed only if it is:
 * - high value: it guards a flow whose breakage would hurt users or
 *   security most (create, reveal and burn a secret; sign-in, MFA, CSRF,
 *   redirect safety; scrubbing secrets from error reports; the frontend
 *   and backend contracts);
 * - cheap on CI: well under a second of test time. Each dom file costs
 *   about 1s of wall time in jsdom setup and imports; node files cost
 *   almost nothing;
 * - steady: no subprocesses, git, ICU or locale formatting, TZ, or tight
 *   per-test timeouts, and nothing that behaves differently when
 *   public/web/dist exists (the smoke job downloads the built assets).
 *
 * To change the list, add or remove a path under the project that runs it
 * ('dom' for jsdom, 'node' for the NODE_GLOBS directories in
 * vitest.config.ts), with a one-line reason. Keep the vitest part of the
 * smoke job around a minute: the job is cancelled at 15 minutes and the
 * Ruby part takes about 9.5 of them.
 *
 * Every entry is checked by findSmokeListProblems below, at config load in
 * the smoke job and by src/tests/build/smoke-files.spec.ts in T2 on every
 * PR. A renamed, deleted or moved file fails that PR.
 */

import { existsSync } from 'node:fs';
import { matchesGlob, resolve } from 'node:path';

export const SMOKE_FILES = {
  dom: [
    // Secret creation
    // Form submission, public or authenticated API mode, lifecycle.
    'src/tests/composables/useSecretConcealer.spec.ts',
    // Signed-in create form: submit guards and sticky TTL.
    'src/tests/components/WorkspaceSecretForm.spec.ts',
    // Endpoint selection and the conceal, fetch and reveal API calls.
    'src/tests/stores/secretStore.spec.ts',

    // Reveal, render and burn
    // Error-code capture and the already-destroyed window (one-time view).
    'src/tests/composables/useSecret.spec.ts',
    // Reveal UI: loading, reveal in flight, revealed value on screen.
    'src/tests/shared/components/base/BaseShowSecret.spec.ts',
    // Confirmation before the burn-on-view reveal; refused reveals.
    'src/tests/apps/secret/components/canonical/SecretConfirmationForm.spec.ts',
    // Actor role decides what the UI offers; a wrong role can expose or burn.
    'src/tests/apps/secret/composables/useSecretContext.spec.ts',
    // XSS defence: the sender's Markdown is sanitized before it renders.
    'src/tests/shared/utils/markdown.spec.ts',
    // Receipt fetch, burning the secret, router integration.
    'src/tests/composables/useReceipt.spec.ts',
    // Fetch and burn calls, the canBurn getter, error handling.
    'src/tests/stores/receiptStore.spec.ts',
    // /secret/:key and its key guard; imports the real ShowSecret.vue graph.
    'src/tests/apps/secret/routes/secret.spec.ts',
    // /receipt/:key route config.
    'src/tests/apps/secret/routes/receipt.spec.ts',

    // Auth, MFA, passkeys and step-up
    // Session state: auth status, init, local logout, setAuthenticated.
    'src/tests/stores/authStore.spec.ts',
    // A verification outage (503) never logs the user out (#4460).
    'src/tests/stores/authStore.rejection.spec.ts',
    // Logout flow and state reset.
    'src/tests/composables/useAuth.logout.spec.ts',
    // MFA setup, enable, verifyOtp at login, disable.
    'src/tests/composables/useMfa.spec.ts',
    // Login view: auth errors, query-param cleanup, per-domain sign-in off.
    'src/tests/apps/session/views/Login.spec.ts',
    // MFA challenge view: modes, force-complete guard, passkey verification.
    'src/tests/apps/session/views/MfaChallenge.spec.ts',
    // Passkey registration and authentication; no other file covers them.
    'src/tests/composables/useWebAuthn.spec.ts',
    // Passwordless magic-link sign-in.
    'src/tests/composables/useMagicLink.spec.ts',
    // Redirect after sign-in: rejects outside paths, validates billing intent.
    'src/tests/composables/usePostAuthRedirect.spec.ts',
    // Re-authentication before sensitive account actions.
    'src/tests/composables/useReauth.spec.ts',
    // Admin step-up never elevates without an explicit operator gesture.
    'src/tests/apps/admin/ElevationPrompt.spec.ts',

    // CSRF and API client
    // CSRF token store: initialization and bootstrap shrimp watcher.
    'src/tests/stores/csrfStore.spec.ts',
    // CSRF token on requests and responses, error interceptor, scrubbing.
    'src/tests/plugins/axios/interceptors.spec.ts',
    // Session rejection vs 503 verification outage (#4460).
    'src/tests/plugins/axios/interceptors.rejection.spec.ts',
    // The real createApi(): the passive-activity header stays scoped (ADR-048).
    'src/tests/api/passiveRequest.spec.ts',

    // Routing guards and redirect safety
    // Central router guards: auth redirect params, feature and domain guards.
    'src/tests/router/guards.routes.spec.ts',
    // Account route guards: owner/admin, password, set-password, email change.
    'src/tests/apps/workspace/routes/account.guards.spec.ts',
    // SSO-only installs keep login and the SSO interstitial reachable.
    'src/tests/router/sso-only-reachability.spec.ts',
    // Open-redirect defence against the Ruby/TS parity fixture.
    'src/tests/utils/redirect.spec.ts',

    // Session and boot
    // The bootstrap session state the whole app reads.
    'src/tests/stores/bootstrapStore.spec.ts',
    // Parking across a session transition and its TTL (ADR-046).
    'src/tests/utils/sessionTransition.spec.ts',
    // Boot path shared by main.ts and admin.ts: install, navigate, mount.
    'src/tests/plugins/core/startApp.spec.ts',
    // Reload on a stale chunk after a deploy.
    'src/tests/utils/preloadError.spec.ts',
    // A locale that fails to load falls back to English, never blocks.
    'src/tests/router/guards.localeFallback.spec.ts',

    // Secret and PII scrubbing
    // Secret and receipt keys are scrubbed from URLs sent to Sentry (#3004).
    'src/tests/plugins/core/diagnostics/scrubUrl.spec.ts',
    // Sentry beforeSend scrubs messages and stack frames.
    'src/tests/plugins/core/diagnostics/beforeSend.spec.ts',
    // Generated scrub patterns redact identifiers in v1, v2 and v3 paths.
    'src/tests/generated/sentry-scrub-patterns.spec.ts',
  ],
  node: [
    // Frontend and backend contracts
    // Ruby serializer fields match the TS bootstrap schema, both ways.
    'src/tests/contracts/bootstrap-schema-contract.spec.ts',
    // Recorded real server bootstrap bodies parse (#4458, #4463).
    'src/tests/contracts/bootstrap-wire-contract.spec.ts',
    // Secret schema matches the backend's safe_dump fields.
    'src/tests/contracts/secret-schema-contract.spec.ts',
    // Receipt schema matches the backend's fields.
    'src/tests/contracts/receipt-schema-contract.spec.ts',
    // Customer (signed-in user) schema matches the backend's fields.
    'src/tests/contracts/customer-schema-contract.spec.ts',
    // v2/v3 schemas accept the backend's null booleans.
    'src/tests/contracts/v3-schema-null-safety.spec.ts',
    // The receipt for a burned or destroyed secret parses (#2686).
    'src/tests/contracts/v3-receipt-null-booleans.spec.ts',
    // Secret shape round-trip.
    'src/tests/schemas/shapes/secret.roundtrip.spec.ts',
    // Receipt shape round-trip.
    'src/tests/schemas/shapes/receipt.roundtrip.spec.ts',
    // Session-failure codes on 401s and the 503 verification code.
    'src/tests/schemas/contracts/session-failure.spec.ts',
    // Response shape of the public v1 receipt API.
    'src/tests/schemas/api/v1/receipt-response.spec.ts',
    // Schema layering (contract -> shapes -> api).
    'src/tests/schemas/architecture/import-graph.spec.ts',
    // Opaque ExtId/ObjId types keep internal ids out of public places.
    'src/tests/types/identifiers.spec.ts',

    // Secret and PII scrubbing
    // Sensitive-field helper behind x-sensitive and the scrub generator.
    'src/tests/scripts/openapi/sensitive-spec.spec.ts',
    // ESLint rule against PII in query strings; also shows ESLint loads.
    'src/tests/build/eslint/no-pii-in-query.spec.ts',

    // i18n
    // Auth error messages stay generic (no account enumeration) everywhere.
    // Also needs globals: true, so a config regression shows up here.
    'src/tests/i18n/security-messages.spec.ts',
    // Every t() key in the source exists; fails if locales:sync did not run.
    'src/tests/i18n/key-validation.spec.ts',
    // Generated locale files load and share one key structure.
    'src/tests/i18n/locale-consistency.spec.ts',

    // Build guards
    // The chunk graph the CSP nonce model depends on.
    'src/tests/build/checkCspChunkGraph.spec.ts',
    // English loads with the entries; other locales stay lazy.
    'src/tests/build/checkLocaleChunks.spec.ts',
  ],
} as const;

export type SmokeProjectName = keyof typeof SMOKE_FILES;

/** The part of a vitest project entry the check reads. */
export interface SmokeProject {
  test: { name: string; include: string[]; exclude?: string[] };
}

const matchesAny = (file: string, globs: readonly string[] = []) =>
  globs.some((glob) => matchesGlob(file, glob));

const runsIn = (file: string, project: SmokeProject) =>
  matchesAny(file, project.test.include) && !matchesAny(file, project.test.exclude);

/**
 * Checks SMOKE_FILES against the disk and against each project's own
 * include and exclude globs. Returns one message per problem, or [] when
 * the list is sound:
 * - a path missing on disk (renamed or deleted);
 * - a path listed twice;
 * - a path that the project it is listed under would not run, or that
 *   another project would also run (wrong list, moved under src/tests/e2e,
 *   moved outside src/tests);
 * - a project with no smoke files, or a project missing from the config.
 */
export function findSmokeListProblems(
  root: string,
  projects: readonly SmokeProject[],
  files: Readonly<Record<SmokeProjectName, readonly string[]>> = SMOKE_FILES
): string[] {
  const problems: string[] = [];
  const byName = new Map(projects.map((p) => [p.test.name, p]));
  const seen = new Set<string>();

  for (const name of Object.keys(files) as SmokeProjectName[]) {
    const project = byName.get(name);
    if (!project) {
      problems.push(`no '${name}' project in vitest.config.ts`);
      continue;
    }
    if (files[name].length === 0) problems.push(`the '${name}' list is empty`);

    for (const file of files[name]) {
      if (seen.has(file)) problems.push(`listed twice: ${file}`);
      seen.add(file);
      if (!existsSync(resolve(root, file))) {
        problems.push(`missing on disk (renamed or deleted?): ${file}`);
      }
      if (!runsIn(file, project)) {
        problems.push(`the '${name}' project would not run it: ${file}`);
      }
      for (const other of projects) {
        if (other !== project && runsIn(file, other)) {
          problems.push(`listed under '${name}' but runs in '${other.test.name}': ${file}`);
        }
      }
    }
  }
  return problems;
}
