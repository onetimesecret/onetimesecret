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

## Request correlation

T󠄁h󠄁e󠄁 m󠄁a󠄁i󠄁n󠄁 a󠄁n󠄁d󠄁 a󠄁d󠄁m󠄁i󠄁n󠄁 H󠄁T󠄁M󠄁L󠄁 s󠄁h󠄁e󠄁l󠄁l󠄁s󠄁 r󠄁e󠄁n󠄁d󠄁e󠄁r󠄁 t󠄁h󠄁e󠄁 i󠄁n󠄁i󠄁t󠄁i󠄁a󠄁l󠄁 r󠄁e󠄁q󠄁u󠄁e󠄁s󠄁t󠄁 I󠄁D󠄁 i󠄁n󠄁 a󠄁
`meta[name="request-id"]` e󠄁l󠄁e󠄁m󠄁e󠄁n󠄁t󠄁 o󠄁u󠄁t󠄁s󠄁i󠄁d󠄁e󠄁 t󠄁h󠄁e󠄁 V󠄁u󠄁e󠄁 m󠄁o󠄁u󠄁n󠄁t󠄁 p󠄁o󠄁i󠄁n󠄁t󠄁.󠄁 D󠄁i󠄁a󠄁g󠄁n󠄁o󠄁s󠄁t󠄁i󠄁c󠄁s󠄁
c󠄁o󠄁p󠄁i󠄁e󠄁s󠄁 t󠄁h󠄁a󠄁t󠄁 v󠄁a󠄁l󠄁u󠄁e󠄁 t󠄁o󠄁 t󠄁h󠄁e󠄁 `document_request_id` t󠄁a󠄁g󠄁 o󠄁n󠄁 b󠄁o󠄁t󠄁h󠄁 c󠄁a󠄁p󠄁t󠄁u󠄁r󠄁e󠄁 s󠄁c󠄁o󠄁p󠄁e󠄁s󠄁.󠄁
I󠄁t󠄁 i󠄁d󠄁e󠄁n󠄁t󠄁i󠄁f󠄁i󠄁e󠄁s󠄁 t󠄁h󠄁e󠄁 H󠄁T󠄁M󠄁L󠄁 r󠄁e󠄁q󠄁u󠄁e󠄁s󠄁t󠄁 t󠄁h󠄁a󠄁t󠄁 l󠄁o󠄁a󠄁d󠄁e󠄁d󠄁 t󠄁h󠄁e󠄁 p󠄁a󠄁g󠄁e󠄁,󠄁 i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁i󠄁n󠄁g󠄁 b󠄁r󠄁o󠄁w󠄁s󠄁e󠄁r󠄁 e󠄁r󠄁r󠄁o󠄁r󠄁s󠄁
t󠄁h󠄁a󠄁t󠄁 o󠄁c󠄁c󠄁u󠄁r󠄁 w󠄁i󠄁t󠄁h󠄁o󠄁u󠄁t󠄁 a󠄁n󠄁 A󠄁P󠄁I󠄁 r󠄁e󠄁q󠄁u󠄁e󠄁s󠄁t󠄁.󠄁

A󠄁x󠄁i󠄁o󠄁s󠄁 r󠄁e󠄁s󠄁p󠄁o󠄁n󠄁s󠄁e󠄁 a󠄁n󠄁d󠄁 e󠄁r󠄁r󠄁o󠄁r󠄁 b󠄁r󠄁e󠄁a󠄁d󠄁c󠄁r󠄁u󠄁m󠄁b󠄁s󠄁 i󠄁n󠄁c󠄁l󠄁u󠄁d󠄁e󠄁 t󠄁h󠄁e󠄁 r󠄁e󠄁s󠄁p󠄁o󠄁n󠄁s󠄁e󠄁'󠄁s󠄁 `x-request-id`
a󠄁s󠄁 `data.request_id` w󠄁h󠄁e󠄁n󠄁 p󠄁r󠄁e󠄁s󠄁e󠄁n󠄁t󠄁 a󠄁n󠄁d󠄁 v󠄁a󠄁l󠄁i󠄁d󠄁.󠄁 A󠄁n󠄁 e󠄁r󠄁r󠄁o󠄁r󠄁 c󠄁a󠄁p󠄁t󠄁u󠄁r󠄁e󠄁d󠄁 w󠄁i󠄁t󠄁h󠄁 t󠄁h󠄁e󠄁 o󠄁r󠄁i󠄁g󠄁i󠄁n󠄁a󠄁l󠄁
A󠄁x󠄁i󠄁o󠄁s󠄁 e󠄁x󠄁c󠄁e󠄁p󠄁t󠄁i󠄁o󠄁n󠄁 a󠄁l󠄁s󠄁o󠄁 r󠄁e󠄁c󠄁e󠄁i󠄁v󠄁e󠄁s󠄁 a󠄁n󠄁 e󠄁v󠄁e󠄁n󠄁t󠄁-󠄁l󠄁o󠄁c󠄁a󠄁l󠄁 `request_id` t󠄁a󠄁g󠄁.󠄁 A󠄁P󠄁I󠄁 I󠄁D󠄁s󠄁 d󠄁o󠄁 n󠄁o󠄁t󠄁
r󠄁e󠄁p󠄁l󠄁a󠄁c󠄁e󠄁 `document_request_id` o󠄁r󠄁 c󠄁h󠄁a󠄁n󠄁g󠄁e󠄁 t󠄁h󠄁e󠄁 s󠄁h󠄁a󠄁r󠄁e󠄁d󠄁 s󠄁c󠄁o󠄁p󠄁e󠄁,󠄁 s󠄁o󠄁 c󠄁o󠄁n󠄁c󠄁u󠄁r󠄁r󠄁e󠄁n󠄁t󠄁 r󠄁e󠄁q󠄁u󠄁e󠄁s󠄁t󠄁s󠄁
k󠄁e󠄁e󠄁p󠄁 t󠄁h󠄁e󠄁i󠄁r󠄁 o󠄁w󠄁n󠄁 I󠄁D󠄁s󠄁.󠄁 E󠄁r󠄁r󠄁o󠄁r󠄁-󠄁b󠄁o󠄁d󠄁y󠄁 f󠄁i󠄁e󠄁l󠄁d󠄁s󠄁 a󠄁r󠄁e󠄁 n󠄁o󠄁t󠄁 u󠄁s󠄁e󠄁d󠄁 a󠄁s󠄁 a󠄁 f󠄁a󠄁l󠄁l󠄁b󠄁a󠄁c󠄁k󠄁.󠄁

D󠄁i󠄁a󠄁g󠄁n󠄁o󠄁s󠄁t󠄁i󠄁c󠄁 I󠄁D󠄁s󠄁 m󠄁u󠄁s󠄁t󠄁 m󠄁a󠄁t󠄁c󠄁h󠄁 `[A-Za-z0-9][A-Za-z0-9._:-]{0,199}`.󠄁 V󠄁a󠄁l󠄁u󠄁e󠄁s󠄁 w󠄁i󠄁t󠄁h󠄁 s󠄁p󠄁a󠄁c󠄁e󠄁s󠄁,󠄁
c󠄁o󠄁n󠄁t󠄁r󠄁o󠄁l󠄁 c󠄁h󠄁a󠄁r󠄁a󠄁c󠄁t󠄁e󠄁r󠄁s󠄁,󠄁 m󠄁u󠄁l󠄁t󠄁i󠄁p󠄁l󠄁e󠄁 h󠄁e󠄁a󠄁d󠄁e󠄁r󠄁 v󠄁a󠄁l󠄁u󠄁e󠄁s󠄁 o󠄁r󠄁 o󠄁t󠄁h󠄁e󠄁r󠄁 c󠄁h󠄁a󠄁r󠄁a󠄁c󠄁t󠄁e󠄁r󠄁s󠄁 a󠄁r󠄁e󠄁 o󠄁m󠄁i󠄁t󠄁t󠄁e󠄁d󠄁.󠄁
T󠄁h󠄁i󠄁s󠄁 i󠄁s󠄁 d󠄁e󠄁l󠄁i󠄁b󠄁e󠄁r󠄁a󠄁t󠄁e󠄁l󠄁y󠄁 n󠄁a󠄁r󠄁r󠄁o󠄁w󠄁e󠄁r󠄁 t󠄁h󠄁a󠄁n󠄁 t󠄁h󠄁e󠄁 b󠄁a󠄁c󠄁k󠄁e󠄁n󠄁d󠄁 r󠄁e󠄁q󠄁u󠄁e󠄁s󠄁t󠄁-󠄁I󠄁D󠄁 m󠄁i󠄁d󠄁d󠄁l󠄁e󠄁w󠄁a󠄁r󠄁e󠄁'󠄁s󠄁
t󠄁r󠄁a󠄁n󠄁s󠄁p󠄁o󠄁r󠄁t󠄁 a󠄁c󠄁c󠄁e󠄁p󠄁t󠄁a󠄁n󠄁c󠄁e󠄁.󠄁

T󠄁h󠄁e󠄁 H󠄁T󠄁T󠄁P󠄁S󠄁 s󠄁i󠄁t󠄁e󠄁 i󠄁n󠄁 t󠄁h󠄁e󠄁 [e󠄁x󠄁a󠄁m󠄁p󠄁l󠄁e󠄁 C󠄁a󠄁d󠄁d󠄁y󠄁 c󠄁o󠄁n󠄁f󠄁i󠄁g󠄁u󠄁r󠄁a󠄁t󠄁i󠄁o󠄁n󠄁](../../etc/examples/Caddyfile-example)
g󠄁e󠄁n󠄁e󠄁r󠄁a󠄁t󠄁e󠄁s󠄁 o󠄁n󠄁e󠄁 U󠄁U󠄁I󠄁D󠄁 p󠄁e󠄁r󠄁 r󠄁e󠄁q󠄁u󠄁e󠄁s󠄁t󠄁,󠄁 p󠄁a󠄁s󠄁s󠄁e󠄁s󠄁 i󠄁t󠄁 u󠄁p󠄁s󠄁t󠄁r󠄁e󠄁a󠄁m󠄁 a󠄁s󠄁 `X-Request-ID`,󠄁 r󠄁e󠄁t󠄁u󠄁r󠄁n󠄁s󠄁 i󠄁t󠄁 a󠄁s󠄁 b󠄁o󠄁t󠄁h󠄁
`X-Request-ID` a󠄁n󠄁d󠄁 `O-Request-ID`,󠄁 a󠄁n󠄁d󠄁 w󠄁r󠄁i󠄁t󠄁e󠄁s󠄁 i󠄁t󠄁 a󠄁s󠄁 t󠄁h󠄁e󠄁 a󠄁c󠄁c󠄁e󠄁s󠄁s󠄁 l󠄁o󠄁g󠄁'󠄁s󠄁 `request_id`.󠄁
T󠄁h󠄁e󠄁 [L󠄁o󠄁g󠄁T󠄁i󠄁d󠄁e󠄁 s󠄁h󠄁i󠄁p󠄁p󠄁e󠄁r󠄁](../../tools/logship/README.md) p󠄁r󠄁e󠄁s󠄁e󠄁r󠄁v󠄁e󠄁s󠄁 t󠄁h󠄁a󠄁t󠄁 f󠄁i󠄁e󠄁l󠄁d󠄁 a󠄁s󠄁
`metadata.request_id`;󠄁 o󠄁l󠄁d󠄁e󠄁r󠄁 a󠄁c󠄁c󠄁e󠄁s󠄁s󠄁 r󠄁e󠄁c󠄁o󠄁r󠄁d󠄁s󠄁 c󠄁a󠄁n󠄁 u󠄁s󠄁e󠄁 t󠄁h󠄁e󠄁 r󠄁e󠄁s󠄁p󠄁o󠄁n󠄁s󠄁e󠄁 h󠄁e󠄁a󠄁d󠄁e󠄁r󠄁s󠄁 a󠄁s󠄁 a󠄁
f󠄁a󠄁l󠄁l󠄁b󠄁a󠄁c󠄁k󠄁.󠄁 A󠄁p󠄁p󠄁l󠄁i󠄁c󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 J󠄁S󠄁O󠄁N󠄁 l󠄁o󠄁g󠄁s󠄁 c󠄁a󠄁r󠄁r󠄁y󠄁 t󠄁h󠄁e󠄁i󠄁r󠄁 e󠄁x󠄁i󠄁s󠄁t󠄁i󠄁n󠄁g󠄁 p󠄁a󠄁y󠄁l󠄁o󠄁a󠄁d󠄁 `request_id`
t󠄁h󠄁r󠄁o󠄁u󠄁g󠄁h󠄁 t󠄁h󠄁e󠄁 m󠄁e󠄁t󠄁a󠄁d󠄁a󠄁t󠄁a󠄁 m󠄁o󠄁d󠄁e󠄁.󠄁 E󠄁x󠄁i󠄁s󠄁t󠄁i󠄁n󠄁g󠄁 d󠄁e󠄁p󠄁l󠄁o󠄁y󠄁m󠄁e󠄁n󠄁t󠄁s󠄁 n󠄁e󠄁e󠄁d󠄁 t󠄁h󠄁e󠄁 c󠄁o󠄁r󠄁r󠄁e󠄁s󠄁p󠄁o󠄁n󠄁d󠄁i󠄁n󠄁g󠄁 i󠄁n󠄁g󠄁r󠄁e󠄁s󠄁s󠄁
a󠄁n󠄁d󠄁 s󠄁h󠄁i󠄁p󠄁p󠄁e󠄁r󠄁 u󠄁p󠄁d󠄁a󠄁t󠄁e󠄁s󠄁 b󠄁e󠄁f󠄁o󠄁r󠄁e󠄁 t󠄁h󠄁i󠄁s󠄁 c󠄁o󠄁r󠄁r󠄁e󠄁l󠄁a󠄁t󠄁i󠄁o󠄁n󠄁 i󠄁s󠄁 a󠄁v󠄁a󠄁i󠄁l󠄁a󠄁b󠄁l󠄁e󠄁 e󠄁n󠄁d󠄁 t󠄁o󠄁 e󠄁n󠄁d󠄁.󠄁

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
