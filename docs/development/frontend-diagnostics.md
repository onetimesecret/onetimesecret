# Frontend Diagnostics (Sentry)

Error tracking via `@sentry/browser` / `@sentry/vue` (v10), reporting to
self-hosted Sentry at catch.onetimesecret.com. Plugin:
`src/plugins/core/enableDiagnostics.ts`. Module-level capture API
(`captureException` / `captureMessage` for non-Vue contexts):
`src/services/diagnostics.service.ts`.

## Architecture

Isolated-client pattern: explicit `BrowserClient` + `Scope`, no global
`Sentry.init`. The client is bound to *both* scopes (dual-scope): our isolated
`Scope` (manual captures, tags, transaction name) and the global current scope
via `setCurrentClient`. The global binding is required because SDK integrations
resolve their client off the *current* scope, not our isolated one — without it
`browserApiErrors` drops async-callback errors (timers, listeners, XHR) and
`browserTracing` never records transactions (so `beforeSendTransaction`
scrubbing never runs). Both scopes route events through the same client, so all
events still pass this client's `beforeSend`/`beforeSendTransaction` scrubbers.
Consequence of isolation: the transaction name still must be set on our scope
directly — a `router.afterEach` hook sets the matched route record's
parameterized path (`/secret/:secretKey`), never the resolved URL. See the
`setCurrentClient` comment block in `enableDiagnostics.ts` for the full
rationale.

Config arrives from the backend via bootstrap (`config.sentry`: DSN,
environment, sample rates). Release is `__SENTRY_RELEASE__` at build time so
events match the sourcemaps uploaded for that bundle, even when a CDN serves
an older frontend than the running backend.

Sampling: errors 100% (`sampleRate` overridable), traces 1% default.
`sendDefaultPii` stays false. Session Replay is disabled (CSP conflict with
blob workers — see comment in the integrations list).

## Integrations

Tree-shaken explicit list: `breadcrumbs`, `globalHandlers`, `linkedErrors`,
`dedupe`, `httpContext` (attaches `request.url` — without it events have no
URL), `eventFilters` (noise reduction), `browserApiErrors` (full async stack
traces), `functionToString`, `browserTracing({ router })`.

## Actor context and tags

For authenticated sessions, the bootstrap payload can include
`diagnostics_ref`. It is a single-key block — `{ "actor_ref": "<16 lowercase
hex>" }` — and the client sets Sentry `user.id` to `actor_ref`. Nothing else:
no tag accompanies it. It sends no direct identifier such as an email address
or customer ID, but the stable pseudonymous reference is still potentially
personal data.

`actor_ref` is a keyed one-way digest of the customer's external identifier
(extid), derived server-side with this installation's `ACCOUNT_ID_SECRET`.
There is no scope, residency, or federation axis: the ref means "this customer
record, on this install". Separately provisioned regional records therefore do
not correlate by default — correlation would require the same secret and the
same customer record, which is what copying `ACCOUNT_ID_SECRET` between
installations would produce. Do not copy it.

The correlation subject is the customer RECORD, not the person: the ref
survives an email change and does not re-link an account that was deleted and
re-created. Rotating `ACCOUNT_ID_SECRET` re-keys every ref and breaks
correlation with prior events; the discontinuity ages out of Sentry retention.

For anonymous sessions the block is absent, and absence is the signal — the
client clears user context and mints no fallback id. Malformed bootstrap data
(unknown key, wrong ref shape, a legacy block still carrying the retired
`actor_scope`) fails closed the same way.

On the base scope: `service: web`, `site_host` (display domain),
`jurisdiction` (from bootstrap regions). Per-event indexed tags via the
`context` argument of `captureException` — see `TAG_FIELDS` in
diagnostics.service.ts (`errorType`, `schema`, `planid`, `role`, ...).

Organization correlation is not active. The current Colonel organization-detail
schema discards the backend `organization_ref` field, and no frontend code
attaches an organization tag to Sentry.

## Issue grouping

Schema-validation events whose messages include a schema name receive a
fingerprint based on that name. Axios-shaped request errors whose original
exception has `config.url` receive a fingerprint of the request method, the
path normalized by the existing URL scrubbers, and an outcome. The outcome is
the HTTP status when available, otherwise a coarse `aborted`, `network`, or
error-class value.

This does not resolve arbitrary route templates: only paths covered by the
existing scrubbers are normalized. Errors without `config.url`, schema errors
without a schema name, and events that already set a fingerprint retain
Sentry's default or upstream grouping.

## Scrubbing

Three hooks; all defined in enableDiagnostics.ts, patterns in
`src/plugins/core/diagnostics/scrubbers.ts`:

- `beforeSend` — exception/message strings, `request.url`, `request.headers.Referer`, `transaction`, breadcrumb URLs. Two layers: route-param value scrubbing (opt out per route with `meta.sentryScrubParams: false` — governs param values only) plus an always-on pattern net (emails, 62-char and legacy 31-char identifiers, sensitive paths, and sensitive query-param value redaction for `key` / `secret` / `token` / `passphrase`).
- `beforeSendTransaction` — performance events bypass `beforeSend`; scrubs transaction name, `request.url`, span descriptions (free-text scrubber — the URL scrubber would mangle `GET /path` strings), and span `url` / `http.url` / `http.query` / `url.full` data.
- `beforeBreadcrumb` — navigation breadcrumbs via `router.resolve()` metadata; xhr/fetch breadcrumbs via patterns.

Path patterns are generated from Otto routes marked `sensitive=true`:
`src/generated/sentry-scrub-patterns.ts`, regenerate with
`pnpm run generate:sentry-patterns`. `scrubbers.ts` keeps a legacy fallback
pattern for anything the generated set misses.

## Verifying

`pnpm vitest run src/tests/plugins/core/diagnostics/` plus
`src/tests/services/diagnostics.service.spec.ts`.

Backend counterpart: [backend-diagnostics.md](backend-diagnostics.md).
Scrub rules intentionally mirror `lib/onetime/initializers/setup_diagnostics.rb`.
